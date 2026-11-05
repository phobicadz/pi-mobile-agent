import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import os from "node:os";
import path from "node:path";

/**
 * Whether a finished run should announce itself.
 *
 * The app's switch is the control, but the notice it exists to silence is not
 * the app's own: `notify-completion.ts` (the `pi-setup` Pi extension) calls
 * Home Assistant on `agent_settled` from inside the Pi process — a child of this
 * server, with no socket back to it and no reason to be alive only when the app
 * is. So the setting cannot travel over the WebSocket the app is on; it has to
 * be somewhere the two processes can both see.
 *
 * That is this file. The backend writes it, the extension reads it, and the
 * default when it is missing or unreadable is "on" — the notice is the thing you
 * have to be able to reach for a long task to be worth starting away from a
 * keyboard, so a failed read should not silently cost you the notification.
 *
 * It lives beside Pi's own agent state (`~/.pi/agent/`, where the extension
 * already reads its Home Assistant token) rather than under this repository,
 * because the setting is about the agent and outlives a checkout of the app.
 */
const PREFS_PATH =
  process.env.PI_NOTIFY_PREFS ||
  path.join(os.homedir(), ".pi", "agent", "pi-mobile-notifications.json");

export function loadNotificationsEnabled(): boolean {
  try {
    if (!existsSync(PREFS_PATH)) return true;
    const parsed = JSON.parse(readFileSync(PREFS_PATH, "utf8"));
    // Anything this version cannot read is not a choice: the app's default is.
    return typeof parsed?.enabled === "boolean" ? parsed.enabled : true;
  } catch {
    return true;
  }
}

/** Returns whether the choice was written, so a caller can say that only the
 * remembering failed. */
export function saveNotificationsEnabled(enabled: boolean): boolean {
  try {
    mkdirSync(path.dirname(PREFS_PATH), { recursive: true });
    writeFileSync(PREFS_PATH, JSON.stringify({ enabled }, null, 2) + "\n");
    return true;
  } catch {
    return false;
  }
}
