import { existsSync, readdirSync, readFileSync, statSync } from "fs";
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

/** Text file extensions we can safely read */
const TEXT_EXTENSIONS = new Set([
  "txt", "md", "json", "js", "ts", "tsx", "jsx", "py", "java", "cpp", "c", "h",
  "html", "css", "scss", "xml", "yaml", "yml", "toml", "ini", "conf", "sh",
  "bash", "zsh", "fish", "dart", "go", "rs", "rb", "php", "sql", "sql",
  "dockerfile", "Dockerfile", "makefile", "Makefile", "gradle", "maven",
  "package.json", "package-lock.json", "tsconfig.json", "eslintrc",
  "prettierrc", "gitignore", "env", "log", "csv", "sql", "dockerfile"
]);

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

/** Check if a file is likely a text file based on extension */
function isTextFile(filePath: string): boolean {
  const ext = path.extname(filePath).toLowerCase().slice(1);
  if (TEXT_EXTENSIONS.has(ext)) return true;
  
  // Check if file has no extension (could be text)
  if (!ext) {
    const name = path.basename(filePath).toLowerCase();
    return TEXT_EXTENSIONS.has(name);
  }
  
  return false;
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

    const isText = isTextFile(resolved);
    const content = readFileSync(resolved, isText ? "utf-8" : "latin1");

    return {
      content,
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
