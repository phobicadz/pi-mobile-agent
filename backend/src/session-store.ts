import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from "fs";
import { randomUUID } from "crypto";
import os from "os";
import path from "path";

export interface PiSessionInfo {
  id: string;
  path: string;
  cwd: string;
  name?: string;
  created: string;
  modified: string;
  messageCount: number;
  preview: string;
}

/**
 * Pi stores sessions as JSONL files under ~/.pi/agent/sessions/<encoded-cwd>/.
 * The directory name is the cwd with path separators (and leading separators)
 * replaced by dashes, e.g. C:\Users\Chamb -> --C--Users-Chamb--.
 */
export function defaultSessionDir(): string {
  const configured = process.env.PI_CODING_AGENT_SESSION_DIR;
  if (configured) return configured;
  const agentDir = process.env.PI_CODING_AGENT_DIR || path.join(os.homedir(), ".pi", "agent");
  return path.join(agentDir, "sessions");
}

function decodeSessionDirName(dirName: string): string {
  // --C--Users-Chamb-- -> C:\Users\Chamb (Pi encodes both / and \ as -)
  return dirName.replace(/^-+/, "").replace(/-+$/, "").replace(/-+/g, path.sep);
}

function textOf(content: unknown): string {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .filter((b) => b && typeof b === "object" && (b as any).type === "text")
      .map((b) => (b as any).text ?? "")
      .join(" ");
  }
  return "";
}

function parseSessionFile(filePath: string): PiSessionInfo | null {
  try {
    const stat = statSync(filePath);
    const lines = readFileSync(filePath, "utf8").split("\n");
    let id = "";
    let cwd = "";
    let created = "";
    let name: string | undefined;
    let messageCount = 0;
    let preview = "";

    for (const line of lines) {
      if (!line.trim()) continue;
      let record: any;
      try {
        record = JSON.parse(line);
      } catch {
        continue;
      }

      if (record.type === "session") {
        id = record.id ?? "";
        cwd = record.cwd ?? "";
        created = record.timestamp ?? "";
        continue;
      }
      if (record.type === "session_info") {
        // A later entry without a name is Pi clearing one ("an absent name means
        // it was cleared"), so it has to unset what an earlier entry set - last
        // entry in the file wins, exactly as it does for the conversation.
        name = typeof record.name === "string" ? record.name : undefined;
        continue;
      }
      if (record.type === "message" && record.message) {
        const role = record.message.role;
        if (role === "user" || role === "assistant") messageCount++;
        if (!preview && role === "user") {
          preview = textOf(record.message.content).slice(0, 160);
        }
      }
    }

    if (!id) id = path.basename(filePath, ".jsonl");
    if (!cwd) cwd = decodeSessionDirName(path.basename(path.dirname(filePath)));
    if (!created) created = stat.mtime.toISOString();

    return {
      id,
      path: filePath,
      cwd,
      name,
      created,
      modified: stat.mtime.toISOString(),
      messageCount,
      preview,
    };
  } catch {
    return null;
  }
}

/**
 * The working directory a saved session restores into.
 *
 * Pi reads this same field when it opens the file (`SessionManager.open` uses
 * the header's `cwd`, falling back to its own process cwd), and then runs the
 * whole session there. Returning undefined means "no recorded cwd", which is
 * exactly the case where Pi keeps the directory it already had - so the caller
 * can leave its own idea of the current directory alone.
 */
export function sessionCwdOf(sessionPath: string): string | undefined {
  try {
    for (const line of readFileSync(sessionPath, "utf8").split("\n")) {
      if (!line.trim()) continue;
      let record: any;
      try {
        record = JSON.parse(line);
      } catch {
        continue;
      }
      if (record.type === "session") {
        return typeof record.cwd === "string" && record.cwd
          ? record.cwd
          : undefined;
      }
      // The header comes first; stop at the conversation rather than reading a
      // long session file for one field.
      if (record.type === "message") return undefined;
    }
    return undefined;
  } catch {
    return undefined;
  }
}

/**
 * List saved Pi sessions, most recently modified first.
 * When cwd is given, only sessions from that working directory are returned.
 */
export function listPiSessions(options: { cwd?: string; limit?: number } = {}): PiSessionInfo[] {
  const root = defaultSessionDir();
  if (!existsSync(root)) return [];

  const wantedCwd = options.cwd ? path.resolve(options.cwd) : undefined;
  const sessions: PiSessionInfo[] = [];

  for (const dirName of readdirSync(root)) {
    const dirPath = path.join(root, dirName);
    let dirStat;
    try {
      dirStat = statSync(dirPath);
    } catch {
      continue;
    }
    if (!dirStat.isDirectory()) continue;

    if (wantedCwd) {
      const decoded = path.resolve(decodeSessionDirName(dirName));
      if (decoded !== wantedCwd) continue;
    }

    for (const fileName of readdirSync(dirPath)) {
      if (!fileName.endsWith(".jsonl")) continue;
      const info = parseSessionFile(path.join(dirPath, fileName));
      if (info) sessions.push(info);
    }
  }

  sessions.sort((a, b) => b.modified.localeCompare(a.modified));
  const limit = options.limit ?? 50;
  return sessions.slice(0, limit);
}

/**
 * What a session is about, for naming it: the text of its user messages, oldest
 * first, cut off at `maxChars`. A title only needs enough of a conversation to
 * tell it apart from the others in the list, not all of it.
 */
export function sessionPromptExcerpt(filePath: string, maxChars = 2000): string {
  const parts: string[] = [];
  let used = 0;

  for (const line of readFileSync(filePath, "utf8").split("\n")) {
    if (!line.trim()) continue;
    let record: any;
    try {
      record = JSON.parse(line);
    } catch {
      continue;
    }
    if (record.type !== "message" || record.message?.role !== "user") continue;

    const text = textOf(record.message.content).trim();
    if (!text) continue;

    const room = maxChars - used;
    if (room <= 0) break;
    parts.push(text.slice(0, room));
    used += Math.min(text.length, room);
  }

  return parts.join("\n\n");
}

/**
 * Name a session that is not the one Pi is running (`session_info` on disk).
 *
 * Pi's own format is an appended entry rather than an edited header: a
 * `session_info` hanging off the last entry, with a fresh id. Appending keeps
 * every existing entry byte-for-byte where it was, which is the safe thing to
 * do to a file someone else may still be reading.
 *
 * Pass null to clear the name, which is what Pi does with an empty `name`.
 * Returns false when the file cannot be rewritten.
 */
export function setSessionNameOnDisk(filePath: string, name: string | null): boolean {
  try {
    const content = readFileSync(filePath, "utf8");
    const lines = content.split("\n").filter((line) => line.trim());

    let parentId: string | null = null;
    for (const line of lines) {
      let record: any;
      try {
        record = JSON.parse(line);
      } catch {
        continue;
      }
      if (typeof record?.id === "string" && record.id) parentId = record.id;
    }

    const id = randomUUID().replace(/-/g, "").slice(0, 8);
    const entry: Record<string, unknown> = {
      type: "session_info",
      id,
      parentId,
      timestamp: new Date().toISOString(),
    };
    if (name) entry.name = name;

    const prefix = content.endsWith("\n") || content === "" ? "" : "\n";
    writeFileSync(filePath, `${content}${prefix}${JSON.stringify(entry)}\n`);
    return true;
  } catch {
    return false;
  }
}
