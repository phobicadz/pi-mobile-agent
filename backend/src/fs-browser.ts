import { existsSync, mkdirSync, readdirSync, readFileSync, statSync } from "fs";
import os from "os";
import path from "path";

export interface DirEntry {
  name: string;
  path: string;
  isDirectory?: boolean;
  size?: number;
}

export interface DirListing {
  path: string;
  parent: string | null;
  roots: DirEntry[];
  entries: DirEntry[];
}

export interface FileListing {
  path: string;
  parent: string | null;
  roots: DirEntry[];
  entries: DirEntry[];
}

/** Directories we hide from the browser to keep listings useful. */
const HIDDEN_DIRS = new Set([
  "node_modules",
  "$RECYCLE.BIN",
  "System Volume Information",
  "$AttrData",
  "$WinREAgent",
  "Recovery",
]);

/** Files/patterns we hide from the file listing. */
const HIDDEN_FILES = new Set([
  ".DS_Store",
  "Thumbs.db",
  "$RECYCLE.BIN",
]);

/** Maximum file size we'll read (10 MB) */
const MAX_FILE_SIZE = 10 * 1024 * 1024;

/** How many leading bytes decide whether a file reads as text. */
const TEXT_SNIFF_BYTES = 8192;

/**
 * Whether a file's bytes are text - decided from the bytes, not the name.
 *
 * An extension says what a file claims to be; the bytes say what it is. The
 * extension whitelist this replaces called a .cs file binary, which reached the
 * phone as an uncoloured file labelled "binary" while the app had a C# grammar
 * sitting there unused - the only thing in between was a name nobody had added
 * to a list. A file the app has never heard of (.cshtml, .svelte, a Makefile,
 * no extension at all) is still text if its bytes are.
 */
function looksLikeText(bytes: Buffer): boolean {
  const sample = bytes.subarray(0, Math.min(bytes.length, TEXT_SNIFF_BYTES));
  if (sample.length === 0) return true;

  // A NUL byte is the classic marker: text files do not contain one.
  if (sample.includes(0)) return false;

  let control = 0;
  for (const byte of sample) {
    if (byte === 9 || byte === 10 || byte === 13) continue; // tab, LF, CR
    if (byte < 32) control++;
  }
  // A stray escape or two is a text file with something odd in it; a file made
  // mostly of control bytes is not.
  return control / sample.length < 0.01;
}

function isHiddenDir(name: string): boolean {
  return name.startsWith(".") || HIDDEN_DIRS.has(name);
}

function isHiddenFile(name: string): boolean {
  return name.startsWith(".") || HIDDEN_FILES.has(name);
}

function isDirectory(p: string): boolean {
  try {
    return readdirSync(p) !== undefined && existsSync(p);
  } catch {
    return false;
  }
}

/** Whether a file reads as text, from what its first bytes actually contain. */
/** All filesystem roots: drive letters on Windows, "/" elsewhere. */
export function listRoots(): DirEntry[] {
  if (process.platform === "win32") {
    const drives: DirEntry[] = [];
    for (let code = 65; code <= 90; code++) {
      const letter = String.fromCharCode(code);
      const root = `${letter}:\\`;
      if (existsSync(root)) {
        drives.push({ name: `${letter}:`, path: root });
      }
    }
    return drives;
  }
  return [{ name: "/", path: "/" }];
}

/**
 * Expand a shell-style path: "~" and "~/..." become the service user's home
 * directory, relative paths resolve against it. Without this, "~" was resolved
 * as a literal directory name and every browse/set request silently failed.
 */
export function expandUserPath(input: string): string {
  const trimmed = input.trim();
  const home = os.homedir();
  if (trimmed === "~" || trimmed === "~/" || trimmed === ".") return home;
  if (trimmed.startsWith("~/")) return path.resolve(home, trimmed.slice(2));
  if (!path.isAbsolute(trimmed)) return path.resolve(home, trimmed);
  return path.resolve(trimmed);
}

/** Shorten a path under the home directory to "~" / "~/..." for display. */
export function shrinkHome(dirPath: string): string {
  const home = os.homedir();
  if (dirPath === home) return "~";
  if (dirPath.startsWith(home + path.sep)) return "~" + dirPath.slice(home.length);
  return dirPath;
}

/** Resolve a user-supplied path to an existing absolute directory, or null. */
export function resolveExistingDir(input: string): string | null {
  if (!input || typeof input !== "string") return null;
  const resolved = expandUserPath(input);
  try {
    const entries = readdirSync(resolved);
    void entries;
    return resolved;
  } catch {
    return null;
  }
}

/** List subdirectories of a directory, with parent navigation and roots. */
export function listDirectory(dirPath: string): DirListing {
  const resolved = expandUserPath(dirPath);
  const entries: DirEntry[] = [];
  try {
    for (const entry of readdirSync(resolved, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      // Symlinked directories still report isDirectory() false for the link
      // itself in some cases; include them if they resolve to a directory.
      const fullPath = path.join(resolved, entry.name);
      if (!entry.isDirectory() && !isDirectory(fullPath)) continue;
      if (isHiddenDir(entry.name)) continue;
      entries.push({ name: entry.name, path: fullPath, isDirectory: true });
    }
  } catch {
    // Directory unreadable (permissions) - return empty listing.
  }
  entries.sort((a, b) => a.name.localeCompare(b.name));

  const parent = path.dirname(resolved);
  const atRoot = parent === resolved; // drive root like "C:\", or "/"

  return {
    path: resolved,
    parent: atRoot ? null : parent,
    roots: listRoots(),
    entries,
  };
}

/** List files and directories in a directory. */
export function listFiles(dirPath: string): FileListing {
  const resolved = expandUserPath(dirPath);
  const entries: DirEntry[] = [];
  try {
    for (const entry of readdirSync(resolved, { withFileTypes: true })) {
      if (isHiddenFile(entry.name) && isHiddenDir(entry.name)) continue;

      const fullPath = path.join(resolved, entry.name);
      let isDir = entry.isDirectory();

      try {
        const stat = statSync(fullPath);
        isDir = stat.isDirectory();
        
        entries.push({
          name: entry.name,
          path: fullPath,
          isDirectory: isDir,
          size: isDir ? undefined : stat.size,
        });
      } catch {
        // Skip files we can't stat
        continue;
      }
    }
  } catch {
    // Directory unreadable (permissions) - return empty listing.
  }

  // Sort: directories first, then files
  entries.sort((a, b) => {
    const aIsDir = a.isDirectory || false;
    const bIsDir = b.isDirectory || false;
    if (aIsDir !== bIsDir) return aIsDir ? -1 : 1;
    return a.name.localeCompare(b.name);
  });

  const parent = path.dirname(resolved);
  const atRoot = parent === resolved;

  return {
    path: resolved,
    parent: atRoot ? null : parent,
    roots: listRoots(),
    entries,
  };
}

/** Create a new subdirectory inside dirPath. Returns the created path. */
export function createDirectory(dirPath: string, name: string): string {
  const resolved = expandUserPath(dirPath);
  const trimmed = (name ?? "").trim();

  if (!trimmed) throw new Error("Directory name is required");
  if (/[\\/]/.test(trimmed))
    throw new Error("Directory name cannot contain path separators");
  if (trimmed === "." || trimmed === "..")
    throw new Error("Invalid directory name");
  if (process.platform === "win32" && /[<>:"|?*]/.test(trimmed))
    throw new Error('Directory name cannot contain < > : " | ? * on Windows');

  const target = path.join(resolved, trimmed);
  if (existsSync(target)) throw new Error(`Already exists: ${target}`);

  try {
    mkdirSync(target);
  } catch (err) {
    const message = (err as Error).message;
    if (message.includes("EACCES")) {
      throw new Error(`Permission denied: ${target}`);
    }
    throw err;
  }

  return target;
}

/** Read the contents of a text file. */
export function readFile(
  filePath: string
): {
  content: string;
  size: number;
  isText: boolean;
  encoding: string;
} {
  const resolved = expandUserPath(filePath);

  // Security: prevent reading outside allowed areas (optional, depends on security requirements)
  if (!existsSync(resolved)) {
    throw new Error(`File not found: ${resolved}`);
  }

  try {
    const stat = statSync(resolved);
    if (stat.isDirectory()) {
      throw new Error(`Path is a directory, not a file: ${resolved}`);
    }

    if (stat.size > MAX_FILE_SIZE) {
      throw new Error(`File too large (>${MAX_FILE_SIZE / 1024 / 1024}MB): ${resolved}`);
    }

    // Read the bytes, then decide what they are. Deciding from the extension
    // first is what made a source file the app could colour arrive as binary.
    const bytes = readFileSync(resolved);
    const isText = looksLikeText(bytes);

    return {
      content: bytes.toString(isText ? "utf-8" : "latin1"),
      size: stat.size,
      isText,
      encoding: isText ? "utf-8" : "binary",
    };
  } catch (err) {
    if ((err as Error).message.includes("EACCES")) {
      throw new Error(`Permission denied: ${resolved}`);
    }
    throw err;
  }
}
