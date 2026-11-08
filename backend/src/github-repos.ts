import { existsSync, rmSync } from "fs";
import { spawn } from "child_process";
import path from "path";

/**
 * The user's own GitHub repositories, and cloning one of them into a directory.
 *
 * This is a question about the machine, not about the conversation: it is asked
 * from the file browser, where there is no Pi turn in flight and a clone has to
 * work whether or not a Pi child is even running. So it goes through the GitHub
 * CLI rather than the Pi RPC — which is also the only thing on this box that
 * already knows how to authenticate to a private repository.
 */

export interface GitHubRepo {
  /** `owner/name` — the form a clone is asked for. */
  slug: string;
  /** The repository name alone, which is the directory it clones to. */
  name: string;
  owner: string;
  url: string;
  isPrivate: boolean;
  description: string | null;
  /** When it was last pushed to, which is what "the one I was just working on" means. */
  pushedAt: string | null;
}

/**
 * How many repositories the picker is offered.
 *
 * `gh` paginates to reach this, so it is a real cap and not one page. It is a
 * ceiling on a personal account rather than a design decision; anything past it
 * is still reachable by typing the name, which is what the picker offers for a
 * text that is not in the list.
 */
const REPO_LIMIT = 200;

/** Listing is an API round trip. Two seconds is generous, and a hang is not. */
const LIST_TIMEOUT_MS = 20_000;

/**
 * A clone is bounded by the size of the repository, not by a round trip.
 *
 * Long on purpose: a first clone of a real repo over the LAN is the case this
 * has to survive, and a clone killed at 30s leaves a half-written directory and
 * an error that says nothing about how far it got.
 */
const CLONE_TIMEOUT_MS = 5 * 60_000;

type RunResult = { code: number; stdout: string; stderr: string };

/**
 * Run a command and hand back its exit code and output, never its exit code alone.
 *
 * Async on purpose: `spawnSync` would hold the event loop for the whole clone,
 * and this process is the one relaying Pi's events to every open browser — a
 * blocked loop is a frozen chat on every phone while one directory is copied.
 */
function run(
  command: string,
  args: string[],
  options: { timeoutMs: number; cwd?: string; env?: Record<string, string> }
): Promise<RunResult> {
  return new Promise((resolve) => {
    const child = spawn(command, args, {
      cwd: options.cwd,
      env: { ...process.env, ...options.env },
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";
    let settled = false;

    const timer = setTimeout(() => {
      child.kill();
      stderr += `\n${command} gave up after ${Math.round(options.timeoutMs / 1000)}s`;
    }, options.timeoutMs);

    child.stdout?.on("data", (chunk) => (stdout += chunk.toString()));
    child.stderr?.on("data", (chunk) => (stderr += chunk.toString()));

    child.on("error", (err) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      const missing = (err as NodeJS.ErrnoException).code === "ENOENT";
      resolve({
        code: 127,
        stdout: "",
        stderr: missing ? `${command} is not installed on this machine` : err.message,
      });
    });

    child.on("close", (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({ code: code ?? 1, stdout, stderr });
    });
  });
}

/**
 * A command's failure, phrased as the thing the user can act on.
 *
 * The tool's own words are kept wherever they are the useful ones (a repository
 * that does not exist, a branch that is empty) and replaced only where they are
 * an instruction to go do something outside this app.
 */
function failureMessage(stderr: string, fallback: string): string {
  const text = (stderr ?? "").trim();
  if (!text) return fallback;

  if (/is not installed/i.test(text)) {
    return `${text}. Install the GitHub CLI (gh), or clone by full URL.`;
  }
  if (/not logged in|gh auth login|authentication required/i.test(text)) {
    return "GitHub is not signed in on this machine — run `gh auth login` there first.";
  }

  // Drop git's progress noise and keep the lines that carry the reason.
  const lines = text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("Cloning into") && !line.startsWith("fetch"));
  return lines.slice(-4).join(" ") || fallback;
}

/**
 * Parse whatever was typed into the `owner/name` GitHub works with.
 *
 * Accepted because the picker is not the only way in: a repository belonging to
 * someone else, or one past the listing cap, is typed as `owner/name`, pasted as
 * a URL, or pasted as the `git@github.com:…` form a clone button hands you.
 */
export function repoSlugOf(input: unknown): string | null {
  if (typeof input !== "string") return null;

  let text = input.trim().replace(/\/+$/, "");
  if (!text) return null;

  text = text.replace(/^(https?:\/\/)?(www\.)?github\.com\//i, "");
  text = text.replace(/^ssh:\/\/git@github\.com\/?/i, "");
  text = text.replace(/^git@github\.com:?\/?/i, "");
  text = text.replace(/\.git$/i, "");

  // One slash, both halves looking like GitHub's own names, and neither half
  // starting with a dot (which would be `./x`, `..`, a hidden directory).
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]*\/[A-Za-z0-9][A-Za-z0-9._-]*$/.test(text)) {
    return null;
  }
  if (text.split("/").some((part) => part.startsWith("."))) return null;

  return text;
}

/** The user's own repositories, most recently pushed first. */
export async function listGitHubRepos(): Promise<GitHubRepo[]> {
  const result = await run(
    "gh",
    [
      "repo",
      "list",
      "--limit",
      String(REPO_LIMIT),
      "--json",
      "name,owner,isPrivate,description,pushedAt,url",
    ],
    { timeoutMs: LIST_TIMEOUT_MS }
  );

  if (result.code !== 0) {
    throw new Error(
      failureMessage(result.stderr, "Could not read your GitHub repositories.")
    );
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(result.stdout || "[]");
  } catch {
    throw new Error("Could not read what GitHub returned.");
  }

  const raw = Array.isArray(parsed) ? parsed : [];
  const repos: GitHubRepo[] = [];

  for (const item of raw) {
    const entry = item as Record<string, unknown>;
    const name = typeof entry.name === "string" ? entry.name : "";
    const owner =
      entry.owner && typeof entry.owner === "object"
        ? ((entry.owner as Record<string, unknown>).login as string | undefined) ?? ""
        : "";
    if (!name || !owner) continue;

    repos.push({
      slug: `${owner}/${name}`,
      name,
      owner,
      url: typeof entry.url === "string" ? entry.url : `https://github.com/${owner}/${name}`,
      isPrivate: entry.isPrivate === true,
      description:
        typeof entry.description === "string" && entry.description.trim()
          ? entry.description.trim()
          : null,
      pushedAt: typeof entry.pushedAt === "string" ? entry.pushedAt : null,
    });
  }

  // Most recently pushed first: the repository worth cloning is nearly always
  // one that is still alive, and a name-first list buries it under old ones.
  repos.sort(
    (a, b) =>
      (b.pushedAt ?? "").localeCompare(a.pushedAt ?? "") ||
      a.slug.localeCompare(b.slug)
  );

  return repos;
}

/**
 * Clone `repo` into [dirPath] and report the directory it made.
 *
 * Prefers `gh`, because that is what authenticates to a private repository;
 * plain `git` is the fallback for the case where gh is not installed at all and
 * the repository is public anyway.
 */
export async function cloneGitHubRepo(
  dirPath: string,
  repo: string
): Promise<{ path: string; slug: string; name: string }> {
  const slug = repoSlugOf(repo);
  if (!slug) {
    throw new Error(
      `Not a GitHub repository: "${String(repo ?? "").trim()}" — use owner/name or a github.com URL.`
    );
  }

  const name = slug.split("/")[1];
  const target = path.join(dirPath, name);

  // Refused rather than cloned into: `git clone` into an existing directory is
  // either an error or a second repository inside the first, and neither is what
  // anyone meant when the folder was already there.
  if (existsSync(target)) {
    throw new Error(`Already exists: ${target}`);
  }

  const clone = await cloneCommand(slug, target);

  if (clone.code !== 0) {
    // A failed clone is a directory with half a repository in it, and the next
    // attempt would then be refused by the check above. git usually cleans up
    // after itself; this is what makes the failure leave nothing behind.
    if (existsSync(target)) {
      try {
        rmSync(target, { recursive: true, force: true });
      } catch {
        // Left in place rather than hiding a second failure behind the clone's.
      }
    }
    throw new Error(failureMessage(clone.stderr, `Could not clone ${slug}.`));
  }

  return { path: target, slug, name };
}

async function cloneCommand(slug: string, target: string): Promise<RunResult> {
  // No terminal prompts: with no TTY and no credentials, a clone that is allowed
  // to ask for a username hangs until the timeout instead of failing.
  const gitEnv = { GIT_TERMINAL_PROMPT: "0" };

  const viaGh = await run("gh", ["repo", "clone", slug, target], {
    timeoutMs: CLONE_TIMEOUT_MS,
    env: gitEnv,
  });
  if (viaGh.code === 0) return viaGh;

  // Only a *missing* gh falls through to git. A gh that is installed and
  // unauthenticated is a problem git cannot solve, and its error is the one
  // that says what to do about it.
  if (viaGh.code !== 127) return viaGh;

  return run("git", ["clone", `https://github.com/${slug}`, target], {
    timeoutMs: CLONE_TIMEOUT_MS,
    env: gitEnv,
  });
}
