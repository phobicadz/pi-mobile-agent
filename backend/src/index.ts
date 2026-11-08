import express from "express";
import cors from "cors";
import { WebSocketServer, WebSocket } from "ws";
import { createServer } from "http";
import { spawn, spawnSync } from "child_process";
import { existsSync, readdirSync, readFileSync, statSync } from "fs";
import os from "os";
import path from "path";
import PiRpcClient from "./pi-rpc-client.js";
import type { PromptImage } from "./pi-rpc-client.js";
import {
  deleteSessionOnDisk,
  listPiSessions,
  sessionCwdOf,
  sessionPromptExcerpt,
  setSessionNameOnDisk,
} from "./session-store.js";
import { listDirectory, listFiles, createDirectory, readFile, resolveExistingDir, shrinkHome } from "./fs-browser.js";
import { cloneGitHubRepo, listGitHubRepos } from "./github-repos.js";
import {
  loadNotificationsEnabled,
  saveNotificationsEnabled,
} from "./notification-prefs.js";

const app = express();
const server = createServer(app);
const wss = new WebSocketServer({ server });

app.use(cors());
app.use(express.json());

// Global Pi RPC client instance
let piClient: PiRpcClient | null = null;
let piProcess: ReturnType<typeof spawn> | null = null;
const connectedClients: Set<WebSocket> = new Set();

/**
 * Whether a finished run announces itself, mirrored from the file the Pi
 * extension reads (see `notification-prefs.ts`).
 *
 * Held in memory as well as on disk because the app asks for the current value
 * the moment it connects, and a switch that answers from a file read on every
 * connect is a switch that can fail to answer for a reason the user cannot see.
 * The file is still the thing that matters: it is what the extension acts on.
 */
let notificationsEnabled = loadNotificationsEnabled();

function sendToClients(payload: unknown) {
  const message = JSON.stringify(payload);
  for (const wsClient of connectedClients) {
    if (wsClient.readyState === WebSocket.OPEN) wsClient.send(message);
  }
}

function sendNotificationsState(ws: WebSocket) {
  ws.send(JSON.stringify({ type: "notifications_state", enabled: notificationsEnabled }));
}

// Pi's cwd is fixed at spawn time (RPC has no runtime cwd command), so changing
// the working directory means respawning the Pi child process with a new cwd.
// PI_CWD overrides the directory Pi starts in (useful when running as a service,
// where process.cwd() is the unit's WorkingDirectory).
let currentCwd =
  (process.env.PI_CWD && resolveExistingDir(process.env.PI_CWD)) || process.cwd();

// The directory the running Pi child was spawned in. Pi's own fallback when a
// session file records no working directory is its process cwd, which is this -
// not the mutable currentCwd, which a resume can move. Keeping the two apart is
// what lets the backend follow Pi instead of guessing.
let piProcessCwd = currentCwd;

// Git state for a directory, or null when it is not a git repository (or git is
// unavailable). One `git status --branch --porcelain` answers the branch name and
// the working-tree counts in a single call, which is what the app bar tooltip shows.
type GitStatus = {
  branch: string;
  detached: boolean;
  upstream: string | null;
  ahead: number;
  behind: number;
  staged: number;
  modified: number;
  untracked: number;
  conflicted: number;
};

// get_state is asked for on every connect and after any directory change, and a
// resume can ask twice in the same breath. Repeating git for each of those is
// pointless work, so the answer is held briefly per directory.
const gitStatusCache = new Map<string, { at: number; status: GitStatus | null }>();
const GIT_STATUS_TTL_MS = 1000;

function gitStatus(cwd: string): GitStatus | null {
  const cached = gitStatusCache.get(cwd);
  if (cached && Date.now() - cached.at < GIT_STATUS_TTL_MS) return cached.status;

  let status: GitStatus | null = null;
  try {
    const result = spawnSync(
      "git",
      ["status", "--branch", "--porcelain=v1"],
      {
        cwd,
        encoding: "utf-8",
        timeout: 2000,
        stdio: ["pipe", "pipe", "pipe"],
      },
    );
    // Non-zero here means "not a repository", "not a work tree", or git missing -
    // all of which mean there is no branch to show.
    if (result.status === 0) status = parseGitStatus(result.stdout ?? "");
  } catch (err) {
    status = null;
  }

  gitStatusCache.set(cwd, { at: Date.now(), status });
  return status;
}

function parseGitStatus(output: string): GitStatus | null {
  const lines = output.split("\n").filter((line) => line.length > 0);
  const header = lines[0];
  if (!header || !header.startsWith("## ")) return null;

  const status: GitStatus = {
    branch: "",
    detached: false,
    upstream: null,
    ahead: 0,
    behind: 0,
    staged: 0,
    modified: 0,
    untracked: 0,
    conflicted: 0,
  };

  // `## HEAD (no branch)` is what a detached HEAD looks like; `## main` is a
  // branch with no upstream; `## main...origin/main [ahead 1, behind 2]` is a
  // branch with one. The counts are what a `git status` header line would say.
  const body = header.slice(3);
  if (body.startsWith("HEAD ")) {
    status.detached = true;
  } else {
    const [branchPart, trackingPart] = body.split("...", 2);
    status.branch = branchPart.trim();
    if (trackingPart) {
      const [upstream, ...rest] = trackingPart.split("]");
      status.upstream = upstream.trim();
      const notes = rest.join("]");
      const ahead = /ahead (\d+)/.exec(notes);
      const behind = /behind (\d+)/.exec(notes);
      if (ahead) status.ahead = Number(ahead[1]);
      if (behind) status.behind = Number(behind[1]);
    }
  }

  // Every remaining line is `XY path`; the two status columns say what changed.
  for (const line of lines.slice(1)) {
    const index = line[0] ?? " ";
    const worktree = line[1] ?? " ";
    if (index === "?" && worktree === "?") {
      status.untracked += 1;
    } else if (index === "U" || worktree === "U" || (index === "A" && worktree === "A") || (index === "D" && worktree === "D")) {
      status.conflicted += 1;
    } else {
      if (index !== " ") status.staged += 1;
      if (worktree !== " ") status.modified += 1;
    }
  }

  // A detached HEAD still has something worth showing, but the app labels a
  // branch, so only answer when there is one (or a detached head to name).
  if (!status.branch && !status.detached) return null;
  return status;
}

// Kept for the places that only ever needed the name.
function getGitBranch(cwd: string): string | null {
  const status = gitStatus(cwd);
  if (!status) return null;
  return status.detached ? "HEAD" : status.branch;
}

// Directories recently used by Pi sessions, most recent first (deduplicated).
function recentDirectories(): string[] {
  const seen = new Set<string>();
  const dirs: string[] = [];
  for (const session of listPiSessions({ limit: 200 })) {
    if (session.cwd && !seen.has(session.cwd)) {
      seen.add(session.cwd);
      dirs.push(session.cwd);
    }
  }
  return dirs.slice(0, 10);
}

// Initialize Pi RPC client
async function initializePi(cwd: string = currentCwd) {
  if (piClient) return;

  console.log(`Starting Pi in RPC mode (cwd: ${cwd})...`);
  piProcessCwd = cwd;

  // Spawn Pi process in RPC mode
  // On Windows, "pi" resolves to pi.cmd, which spawn() cannot execute without a shell
  // PI_PROVIDER/PI_MODEL are optional: when unset, Pi starts with its own configured
  // provider/model (pi /login, settings.json, installed provider extensions).
  const args = ["--mode", "rpc"];
  if (process.env.PI_PROVIDER) args.push("--provider", process.env.PI_PROVIDER);
  if (process.env.PI_MODEL) args.push("--model", process.env.PI_MODEL);
  // Sessions are persisted (no --no-session) so /resume can reload them later.
  piProcess = spawn("pi", args, { cwd, shell: process.platform === "win32" });

  const client = new PiRpcClient(piProcess);
  piClient = client;

  // Only clear module state if this client is still the current one — a killed
  // child's late exit event must not clobber a client spawned for a new cwd.
  client.on("error", (err) => {
    console.error("Pi RPC error:", err);
    if (piClient === client) piClient = null;
  });

  client.on("exit", () => {
    console.log("Pi process exited");
    if (piClient === client) {
      piClient = null;
      piProcess = null;
    }
  });

  // Forward all Pi events to connected WebSocket clients
  client.on("event", (event) => {
    for (const wsClient of connectedClients) {
      if (wsClient.readyState === WebSocket.OPEN) {
        wsClient.send(
          JSON.stringify({
            type: "pi_event",
            event,
          })
        );
      }
    }
  });

  console.log("Pi RPC client initialized");
}

// WebSocket connection handler
wss.on("connection", (ws: WebSocket) => {
  console.log("New WebSocket client connected");
  connectedClients.add(ws);

  // The switch has to open in the state the agent is actually in, including on a
  // second device: the setting is one thing the extension acts on, not a
  // preference each browser keeps for itself.
  sendNotificationsState(ws);

  ws.on("message", async (data: string) => {
    try {
      const message = JSON.parse(data);
      await handleClientMessage(ws, message);
    } catch (err) {
      console.error("Error handling message:", err);
      ws.send(
        JSON.stringify({
          type: "error",
          error: "Failed to process message",
        })
      );
    }
  });

  ws.on("close", () => {
    console.log("WebSocket client disconnected");
    connectedClients.delete(ws);
  });

  ws.on("error", (err) => {
    console.error("WebSocket error:", err);
  });
});

const MAX_IMAGES_PER_PROMPT = 8;
const MAX_IMAGE_BASE64_CHARS = 8 * 1024 * 1024;

/**
 * Validate the images the app sent, before any of it reaches Pi.
 *
 * A base64 image is the one part of this protocol that arrives unbounded: a
 * phone photo is several megabytes of text, and a model that cannot take images
 * rejects the whole prompt rather than the image. Saying which one is wrong, in
 * a sentence the app can show, beats a provider error several hops away.
 */
function toPromptImages(raw: unknown): PromptImage[] | undefined {
  if (raw === undefined || raw === null) return undefined;
  if (!Array.isArray(raw)) throw new Error("images must be a list");
  if (raw.length === 0) return undefined;
  if (raw.length > MAX_IMAGES_PER_PROMPT) {
    throw new Error(`At most ${MAX_IMAGES_PER_PROMPT} images per prompt`);
  }

  return raw.map((entry, index) => {
    if (typeof entry !== "object" || entry === null) {
      throw new Error(`image ${index + 1} is not an object`);
    }
    const { data, mimeType } = entry as Record<string, unknown>;
    if (typeof data !== "string" || data.length === 0) {
      throw new Error(`image ${index + 1} has no data`);
    }
    if (data.length > MAX_IMAGE_BASE64_CHARS) {
      throw new Error(
        `image ${index + 1} is too large (${Math.round(
          data.length / 1024 / 1024,
        )} MB)`,
      );
    }
    if (typeof mimeType !== "string" || !mimeType.startsWith("image/")) {
      throw new Error(`image ${index + 1} is not an image`);
    }
    return { data, mimeType };
  });
}

/**
 * The session file the running Pi has open, or null when it has none.
 *
 * Asked for rather than remembered, because the running Pi is the only thing
 * that knows: it opens a new file on the first prompt, and resuming swaps it.
 * Renaming has to know which file is live in order to go through Pi for that
 * one and straight to disk for the rest - appending to a file Pi is itself
 * appending to is how a half-written line gets into a session.
 */
async function liveSessionFile(): Promise<string | null> {
  if (!piClient) return null;
  try {
    const state = await piClient.getState();
    const file = (state.data as Record<string, unknown> | undefined)?.sessionFile;
    return typeof file === "string" && file ? path.resolve(file) : null;
  } catch {
    return null;
  }
}

/** Trim what a model says into something a session list can show. */
function cleanSessionTitle(text: string): string {
  const line =
    text
      .split("\n")
      .map((l) => l.trim())
      .find((l) => l.length > 0) ?? "";

  const title = line
    .replace(/^[-*•\d.)\s]+/, "")
    .replace(/^["'`]+|["'`]+$/g, "")
    .replace(/[.,;:]+$/, "")
    .replace(/\s+/g, " ")
    .trim();

  return title.length > 80 ? `${title.slice(0, 79).trim()}…` : title;
}

/**
 * Ask the model for a short name for a conversation (`pi --print`).
 *
 * A separate one-shot Pi rather than the app's own child: asking the live
 * session to name itself would put both the request and its answer inside the
 * conversation being named. `--no-session` keeps the call out of the session
 * list too, so asking what a session should be called never adds one.
 */
function titleWithModel(excerpt: string): Promise<string> {
  // PI_COMMAND is the same override the RPC child honours.
  const piCommand = process.env.PI_COMMAND || "pi";
  const instruction =
    "The text between <conversation> and </conversation> on stdin is the user " +
    "side of one saved conversation. Name that conversation. Reply with the name " +
    "only: two to five words, lower case, no quotes, no sentence, no " +
    "explanation - it is a label in a list of saved sessions, so it has to say " +
    "what this particular conversation is about.";

  return new Promise((resolve, reject) => {
    // On Windows "pi" is a pi.cmd shim that needs a shell, and a shell would
    // also split the instruction into separate words, so there it is quoted.
    const onWindows = process.platform === "win32";

    let child: ReturnType<typeof spawn>;
    try {
      child = spawn(
        piCommand,
        ["--no-session", "--print", onWindows ? `"${instruction}"` : instruction],
        { cwd: currentCwd, shell: onWindows },
      );
    } catch (err) {
      reject(err);
      return;
    }

    let out = "";
    let errText = "";

    const timer = setTimeout(() => {
      child.kill();
      reject(new Error("The model took too long to name this session"));
    }, 90_000);

    child.stdout?.on("data", (chunk) => (out += chunk.toString()));
    child.stderr?.on("data", (chunk) => (errText += chunk.toString()));
    child.on("error", (err) => {
      clearTimeout(timer);
      reject(err);
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      const title = cleanSessionTitle(out);
      if (title) {
        resolve(title);
        return;
      }
      reject(
        new Error(
          errText.trim() || `No name came back (pi exited with ${code ?? "no code"})`,
        ),
      );
    });

    // Delimited, because a bare block of text on stdin reads to a model as an
    // instruction to answer rather than as the thing to be named.
    child.stdin?.write(`<conversation>\n${excerpt}\n</conversation>\n`);
    child.stdin?.end();
  });
}

async function handleClientMessage(ws: WebSocket, message: any) {
  const { id, command, ...params } = message;

  // Filesystem browsing does not require a live Pi client.
  if (command === "list_dir") {
    try {
      const requested = params.path
        ? resolveExistingDir(params.path)
        : resolveExistingDir(currentCwd) ?? os.homedir();
      if (!requested) {
        ws.send(
          JSON.stringify({
            type: "response",
            id,
            command,
            success: false,
            error: `Not a directory: ${params.path}`,
          })
        );
        return;
      }
      const listing = listDirectory(requested);
      ws.send(
        JSON.stringify({
          type: "response",
          id,
          command,
          success: true,
          data: {
            ...listing,
            current: currentCwd,
            cwdDisplay: shrinkHome(currentCwd),
            recent: recentDirectories(),
          },
        })
      );
    } catch (err) {
      ws.send(
        JSON.stringify({
          type: "error",
          id,
          command,
          error: (err as Error).message,
        })
      );
    }
    return;
  }

  if (command === "list_files") {
    try {
      const requested = params.path
        ? resolveExistingDir(params.path)
        : resolveExistingDir(currentCwd) ?? os.homedir();
      if (!requested) {
        ws.send(
          JSON.stringify({
            type: "response",
            id,
            command,
            success: false,
            error: `Not a directory: ${params.path}`,
          })
        );
        return;
      }
      const listing = listFiles(requested);
      ws.send(
        JSON.stringify({
          type: "response",
          id,
          command,
          success: true,
          data: {
            ...listing,
            current: currentCwd,
            cwdDisplay: shrinkHome(currentCwd),
            recent: recentDirectories(),
          },
        })
      );
    } catch (err) {
      ws.send(
        JSON.stringify({
          type: "error",
          id,
          command,
          error: (err as Error).message,
        })
      );
    }
    return;
  }

  if (command === "create_dir") {
    try {
      const parent = params.path
        ? resolveExistingDir(params.path)
        : resolveExistingDir(currentCwd) ?? os.homedir();
      if (!parent) {
        ws.send(
          JSON.stringify({
            type: "response",
            id,
            command,
            success: false,
            error: `Not a directory: ${params.path}`,
          })
        );
        return;
      }
      const created = createDirectory(parent, params.name);
      ws.send(
        JSON.stringify({
          type: "response",
          id,
          command,
          success: true,
          data: {
            path: created,
            parent,
            name: params.name.trim(),
          },
        })
      );
    } catch (err) {
      ws.send(
        JSON.stringify({
          type: "error",
          id,
          command,
          error: (err as Error).message,
        })
      );
    }
    return;
  }

  // The user's own GitHub repositories, for the file browser's clone picker.
  if (command === "list_repos") {
    try {
      const repos = await listGitHubRepos();
      ws.send(
        JSON.stringify({
          type: "response",
          id,
          command,
          success: true,
          data: { repos },
        })
      );
    } catch (err) {
      ws.send(
        JSON.stringify({
          type: "error",
          id,
          command,
          error: (err as Error).message,
        })
      );
    }
    return;
  }

  if (command === "clone_repo") {
    try {
      const parent = params.path
        ? resolveExistingDir(params.path)
        : resolveExistingDir(currentCwd) ?? os.homedir();
      if (!parent) {
        ws.send(
          JSON.stringify({
            type: "response",
            id,
            command,
            success: false,
            error: `Not a directory: ${params.path}`,
          })
        );
        return;
      }
      const cloned = await cloneGitHubRepo(parent, params.repo);
      ws.send(
        JSON.stringify({
          type: "response",
          id,
          command,
          success: true,
          data: {
            ...cloned,
            parent,
            cwdDisplay: shrinkHome(cloned.path),
          },
        })
      );
    } catch (err) {
      ws.send(
        JSON.stringify({
          type: "error",
          id,
          command,
          error: (err as Error).message,
        })
      );
    }
    return;
  }

  if (command === "read_file") {
    try {
      if (!params.path) {
        ws.send(
          JSON.stringify({
            type: "response",
            id,
            command,
            success: false,
            error: "Missing path parameter",
          })
        );
        return;
      }
      const result = readFile(params.path);
      ws.send(
        JSON.stringify({
          type: "response",
          id,
          command,
          success: true,
          data: result,
        })
      );
    } catch (err) {
      ws.send(
        JSON.stringify({
          type: "error",
          id,
          command,
          error: (err as Error).message,
        })
      );
    }
    return;
  }

  if (command === "set_cwd") {
    try {
      const target = resolveExistingDir(params.path);
      if (!target) {
        ws.send(
          JSON.stringify({
            type: "response",
            id,
            command,
            success: false,
            error: `Not a directory: ${params.path}`,
          })
        );
        return;
      }
      if (target === currentCwd && piClient) {
        ws.send(
          JSON.stringify({
            type: "response",
            id,
            command,
            success: true,
            data: {
              cwd: currentCwd,
              cwdDisplay: shrinkHome(currentCwd),
              unchanged: true,
            },
          })
        );
        return;
      }
      // Pi's cwd is fixed at spawn time, so restart the child in the new directory.
      if (piProcess) {
        piProcess.kill();
        piProcess = null;
        piClient = null;
      }
      currentCwd = target;
      // A new directory is a different repository; anything held for the old one
      // is not an answer about this one.
      gitStatusCache.clear();
      await initializePi(target);
      ws.send(
        JSON.stringify({
          type: "response",
          id,
          command,
          success: true,
          data: {
            cwd: currentCwd,
            cwdDisplay: shrinkHome(currentCwd),
          },
        })
      );
    } catch (err) {
      ws.send(
        JSON.stringify({
          type: "error",
          id,
          command,
          error: (err as Error).message,
        })
      );
    }
    return;
  }

  // Whether a finished run announces itself.
  //
  // Handled here rather than through Pi: the notice it controls is sent by the
  // `notify-completion` extension inside the Pi process, but the setting is not
  // something Pi itself carries — there is no RPC for it, and a run started in a
  // terminal should honour the same switch as one started from the app.
  if (command === "set_notifications") {
    if (typeof params.enabled !== "boolean") {
      ws.send(
        JSON.stringify({
          type: "error",
          id,
          command,
          error: "set_notifications needs a boolean enabled",
        })
      );
      return;
    }

    notificationsEnabled = params.enabled;
    // The choice applies either way; only remembering it can fail, and that is
    // worth saying because the next launch is where it would show up.
    const stored = saveNotificationsEnabled(notificationsEnabled);

    // Every client, not just this one: two devices showing two different states
    // of one switch is how a setting starts getting pressed twice.
    sendToClients({ type: "notifications_state", enabled: notificationsEnabled });
    ws.send(
      JSON.stringify({
        type: "response",
        id,
        command,
        success: true,
        data: { enabled: notificationsEnabled, stored },
      })
    );
    return;
  }

  // The app reporting what the browser and Flutter each think the screen is.
  // Nothing acts on it: it is logged, so a layout problem that only shows on a
  // phone can be read off `journalctl --user -u pi-mobile-agent` instead of
  // guessed at from a description.
  if (command === "client_metrics") {
    console.log(`client_metrics ${JSON.stringify(params.metrics ?? {})}`);
    ws.send(
      JSON.stringify({
        type: "response",
        id,
        command,
        success: true,
        data: {},
      })
    );
    return;
  }

  if (!piClient) {
    ws.send(
      JSON.stringify({
        type: "error",
        error: "Pi client not initialized",
      })
    );
    return;
  }

  try {
    let response;

    switch (command) {
      case "prompt":
        response = await piClient.prompt(params.message, toPromptImages(params.images));
        break;
      case "new_session":
        // A fresh conversation in the directory Pi is already working in. The
        // session being left behind stays on disk, so the session picker can
        // still load it.
        response = await piClient.newSession();
        if (response.data) {
          response.data = {
            ...response.data,
            cwd: currentCwd,
            cwdDisplay: shrinkHome(currentCwd),
          };
        }
        break;
      case "get_state":
        response = await piClient.getState();
        // Pi's RPC state has no cwd; the app needs it to show the current
        // directory in the app bar before anything has been browsed.
        if (response.data) {
          response.data = {
            ...response.data,
            cwd: currentCwd,
            cwdDisplay: shrinkHome(currentCwd),
            gitBranch: getGitBranch(currentCwd),
            gitStatus: gitStatus(currentCwd),
          };
        }
        break;
      case "get_messages":
        response = await piClient.getMessages();
        break;
      case "abort":
        response = await piClient.abort();
        break;
      case "set_model":
        // Pi names a model by provider and model id. Sending a bare "model"
        // string is what made this command answer "Model not found:
        // undefined/undefined" for as long as the app has had a model picker.
        if (!params.provider || !params.modelId) {
          throw new Error("set_model needs a provider and a modelId");
        }
        response = await piClient.setModel(params.provider, params.modelId);
        break;
      case "get_available_models":
        response = await piClient.getAvailableModels();
        break;
      case "get_session_stats":
        // Token/cost totals plus context-window usage, used by the app's
        // progress line after a run settles.
        response = await piClient.getSessionStats();
        break;
      case "list_sessions":
        // Pi's own session history, read from its session store on disk.
        response = {
          success: true,
          data: { sessions: listPiSessions({ cwd: params.cwd }) },
        };
        break;
      case "resume_session":
        // Loads a saved session into the live Pi runtime; the client then
        // fetches the history with get_messages.
        response = await piClient.switchSession(params.sessionPath);
        // Pi does not just load the conversation: it rebuilds the session in the
        // directory that conversation was recorded in. The backend's own idea of
        // the current directory has to follow, or the app keeps showing - and
        // browsing from - the directory from before the resume.
        if ((response.data as any)?.cancelled !== true) {
          const recorded = sessionCwdOf(params.sessionPath);
          const resolved = recorded ? resolveExistingDir(recorded) : null;
          // Same order Pi uses: the directory recorded in the session file, and
          // if it records none, the directory the Pi process was started in.
          currentCwd = resolved ?? piProcessCwd;
          gitStatusCache.clear();
          if (response.data) {
            response.data = {
              ...response.data,
              gitBranch: getGitBranch(currentCwd),
              gitStatus: gitStatus(currentCwd),
              cwd: currentCwd,
              cwdDisplay: shrinkHome(currentCwd),
            };
          }
        }
        break;
      case "rename_session": {
        // A name is a `session_info` entry, which is what Pi's own /name and
        // set_session_name write. The live session goes through Pi so its own
        // idea of the name stays in step with the file; every other session is
        // a file nobody has open, so it is edited directly.
        const target = typeof params.sessionPath === "string" ? params.sessionPath : "";
        const name =
          typeof params.name === "string" && params.name.trim()
            ? params.name.trim().slice(0, 120)
            : null;
        if (!target) throw new Error("rename_session needs a sessionPath");
        if (!existsSync(target)) throw new Error("That session is no longer here");

        const live = await liveSessionFile();
        if (live && path.resolve(target) === live) {
          response = await piClient.setSessionName(name);
        } else if (setSessionNameOnDisk(target, name)) {
          response = { success: true, data: { renamed: true } };
        } else {
          throw new Error("The session file could not be rewritten");
        }
        break;
      }
      case "delete_session": {
        // A saved conversation, not the one being had: the live session's file is
        // open and still being appended to, so removing it from under Pi would
        // leave an app that is in a conversation that no longer exists. The
        // caller starts a new session first, which is what the picker says.
        const target = typeof params.sessionPath === "string" ? params.sessionPath : "";
        if (!target) throw new Error("delete_session needs a sessionPath");

        // Asked before the file is looked for, because a session Pi has just
        // started has a path and no file yet - and "that is no longer here" about
        // the conversation the app is sitting in is the wrong wrong answer.
        const live = await liveSessionFile();
        if (live && path.resolve(target) === live) {
          throw new Error(
            "That is the session you are in. Start a new one and it can be deleted.",
          );
        }

        if (!existsSync(target)) throw new Error("That session is no longer here");

        const deleted = deleteSessionOnDisk(target);
        if (!deleted.ok) {
          throw new Error(deleted.error ?? "The session file could not be removed");
        }
        response = { success: true, data: { deleted: true, method: deleted.method } };
        break;
      }
      case "generate_session_title": {
        // Suggest, never apply: what a model guessed is worth showing someone
        // before it becomes the name of a conversation they were in.
        const target = typeof params.sessionPath === "string" ? params.sessionPath : "";
        if (!target) throw new Error("generate_session_title needs a sessionPath");
        if (!existsSync(target)) throw new Error("That session is no longer here");

        const excerpt = sessionPromptExcerpt(target);
        if (!excerpt.trim()) {
          throw new Error("That session has no messages to name");
        }
        const title = await titleWithModel(excerpt);
        response = { success: true, data: { title } };
        break;
      }
      default:
        ws.send(
          JSON.stringify({
            type: "error",
            id,
            error: `Unknown command: ${command}`,
          })
        );
        return;
    }

    ws.send(
      JSON.stringify({
        type: "response",
        id,
        command,
        success: response.success,
        data: response.data,
        error: response.error,
      })
    );
  } catch (err) {
    console.error(`Error executing command ${command}:`, err);
    ws.send(
      JSON.stringify({
        type: "error",
        id,
        error: (err as Error).message,
      })
    );
  }
}

// HTTP endpoints
app.get("/health", (req, res) => {
  res.json({
    status: "ok",
    pi_connected: !!piClient,
    cwd: currentCwd,
    cwdDisplay: shrinkHome(currentCwd),
  });
});

app.get("/api/models", async (req, res) => {
  try {
    if (!piClient) {
      return res.status(503).json({ error: "Pi not initialized" });
    }
    const response = await piClient.getAvailableModels();
    res.json(response.data);
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.get("/api/sessions", (req, res) => {
  try {
    res.json({ sessions: listPiSessions() });
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.get("/api/state", async (req, res) => {
  try {
    if (!piClient) {
      return res.status(503).json({ error: "Pi not initialized" });
    }
    const response = await piClient.getState();
    res.json({
      ...(response.data ?? {}),
      cwd: currentCwd,
      cwdDisplay: shrinkHome(currentCwd),
    });
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.post("/api/prompt", async (req, res) => {
  try {
    if (!piClient) {
      return res.status(503).json({ error: "Pi not initialized" });
    }
    const { message, images } = req.body;
    const response = await piClient.prompt(message, toPromptImages(images));
    res.json({ success: response.success, data: response.data });
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

// Serve the built Flutter web app (frontend/build/web) from this same port so a
// phone on the LAN can open http://<this-machine-ip>:<PORT> in Safari and reach
// the WebSocket on the same origin. Run `npm run build:web` in the repo root
// first; if the folder is absent the API/WebSocket server still works.
const webBuildDir = path.join(import.meta.dirname, "..", "..", "frontend", "build", "web");
app.use(
  express.static(webBuildDir, {
    // Always revalidate so browsers pick up new builds immediately after
    // `npm run build:web` instead of serving a stale cached main.dart.js.
    //
    // The app shell is not cached at all. A cached index.html is how a phone ends
    // up running an old page while main.dart.js is new - the two halves of one
    // build coming from two different places - and that is not a stale build, it
    // is a build that does not exist: the page and the code disagree about what
    // the page is.
    setHeaders: (res, filePath) => {
      res.setHeader(
        "Cache-Control",
        path.basename(filePath) === "index.html" ? "no-store" : "no-cache",
      );
    },
  }),
);

const PORT = process.env.PORT || 3000;

server.listen(PORT, async () => {
  console.log(`Server listening on port ${PORT}`);
  console.log(`WebSocket: ws://localhost:${PORT}`);
  console.log(`HTTP API: http://localhost:${PORT}/api`);
  const webBuilt = existsSync(path.join(webBuildDir, "index.html"));
  console.log(webBuilt ? `Web app: serving ${webBuildDir}` : "Web app: not built (run 'flutter build web' in the frontend folder)");

  // Initialize Pi on startup
  await initializePi().catch(console.error);
});

// Graceful shutdown
process.on("SIGINT", () => {
  console.log("Shutting down...");
  piClient?.close();
  server.close(() => {
    console.log("Server closed");
    process.exit(0);
  });
});
