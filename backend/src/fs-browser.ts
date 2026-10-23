import { existsSync, readdirSync } from "fs";
import os from "os";
import path from "path";

export interface DirEntry {
  name: string;
  path: string;
}

export interface DirListing {
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

function isHiddenDir(name: string): boolean {
  return name.startsWith(".") || HIDDEN_DIRS.has(name);
}

function isDirectory(p: string): boolean {
  try {
    return readdirSync(p) !== undefined && existsSync(p);
  } catch {
    return false;
  }
}

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

/** List subdirectories of a directory, with parent navigation and roots. */export function listDirectory(dirPath: string): DirListing {
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
      entries.push({ name: entry.name, path: fullPath });
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
