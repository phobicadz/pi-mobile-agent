# Code audit — pi-mobile-agent (2025-10-25)

What this repo does: a web app (Flutter) + Node backend that lets you chat with a Pi coding agent on your machine from a phone browser. The backend spawns `pi --mode rpc`, relays prompts/events over a WebSocket, and can browse directories and resume saved sessions. Assumed load: one person (you) on a home LAN, occasionally a few tabs.

## Must fix

### 1. Symlinked folders never show in the directory browser (`backend/src/fs-browser.ts`, `listDirectory`)
- **What this is:** The browser lists subdirectories, and a comment says symlinked folders should be included if they point to a real directory.
- **Problem:** The first line `if (!entry.isDirectory()) continue;` already drops every symlink, so the second check that "includes" them is dead code that can never run. A folder like `~/projects/link-to-repo` never appears.
- **Fix:** Delete the first `continue` and keep only `if (!entry.isDirectory() && !isDirectory(fullPath)) continue;`. One line removed.
- **If we skip it:** Symlinked project folders stay invisible in the app.

### 2. The riskiest code has no tests (`backend/src/session-store.ts`, `backend/src/fs-browser.ts`)
- **What this is:** Path decoding (`--C--Users-Chamb--` → real path), `~` expansion, session JSONL parsing — all hand-written string handling that must work on both Windows and Linux.
- **Problem:** The frontend has 6 test files; the backend has zero. A wrong regex in `decodeSessionDirName` silently hides sessions or lists the wrong folder, and nothing fails.
- **Fix:** One small test file (plain `node --test`) with a handful of path cases per function. No framework needed.
- **If we skip it:** Path bugs ship silently and you find them by the app showing nothing.

### 3. Nothing is authenticated (`backend/src/index.ts`)
- **What this is:** Any client that can reach port 3000 can browse your entire filesystem, read all your session files, and run the agent (which edits files) in any directory.
- **Problem:** On a trusted LAN this is fine; one port-forward or reverse proxy later and it's a door to your whole home folder. `.env.example` already mentions `API_TOKEN` as a "future feature".
- **Fix:** Until exposed beyond the LAN, document "LAN only" in the README. If ever exposed: check one shared token header/query param in the one `wss.on("connection")` handler.
- **If we skip it:** Safe today, dangerous the day someone adds a proxy.

## Should fix

### 4. Every folder browse re-reads your whole session archive (`backend/src/index.ts` → `recentDirectories` → `listPiSessions`)
- **Problem:** `list_dir` calls `listPiSessions({limit: 200})`, which reads **every** `.jsonl` session file in full (sessions can be megabytes) on every browse. Fine today, slow once you have a year of sessions.
- **Fix:** Sort by file `mtime` first (cheap stat), then fully parse only the top `limit` files. Same result, work proportional to the limit instead of the archive.
- **If we skip it:** The folder browser gets steadily slower over months.

### 5. docker-compose healthcheck can never pass (`docker-compose.yml`)
- **Problem:** It runs `curl`, but `node:20-alpine` has no curl. Compose overrides the (correct, node-based) healthcheck from the Dockerfile, so the container is permanently "unhealthy".
- **Fix:** Delete the `healthcheck:` block from compose — the Dockerfile already has a working one. Also delete the unused `volumes: pi-data`.
- **If we skip it:** Monitoring/logs always show a false alarm.

### 6. A dead backend freezes the UI for 30 seconds (`backend/src/pi-rpc-client.ts`, `frontend/lib/services/pi_service.dart`)
- **Problem:** If the Pi child exits or the WebSocket drops, already-sent commands wait their full 30-second timeout before erroring — after a backend restart the app just hangs.
- **Fix:** In both clients, on child-exit / socket-close, fail all entries in `pendingRequests` immediately. A few lines each side.
- **If we skip it:** Every restart costs a confusing 30-second freeze.

### 7. Unrelated files in the repo (`backend/pimoroni_*.py`, `web_scraper.py`, `three-js-demo.html`, `pimoroni_shopify_results.json`)
- **Problem:** One-off Pimoroni shop scraping experiments (the latest commit) live inside the agent app; they're never imported or referenced.
- **Fix:** Move to their own repo/folder. Pure deletion.
- **If we skip it:** Every future reader wonders if they're part of the app.

### 8. Unused dependency declared (`backend/package.json`)
- **Problem:** `@earendil-works/pi-coding-agent` is in `dependencies` but no code imports it — the backend only spawns `pi` from PATH, and the Dockerfile installs the CLI globally separately.
- **Fix:** Remove it from `dependencies`. Faster installs, smaller image.
- **If we skip it:** Slower installs and a misleading dependency list.

### 9. Dead config and imports (`backend/src/index.ts` line 6, `frontend/lib/constants/app_constants.dart`, `backend/.env.example`)
- **Problem:** `readdirSync/readFileSync/statSync` imported but unused; most of `AppConfig` (server URLs, endpoints, `maxEventsToDisplay`, `maxReconnectAttempts`, pagination) is referenced nowhere; `.env.example` documents settings nothing reads (there's no dotenv — config comes from real env vars via systemd/compose).
- **Fix:** Delete the unused imports and constants; rewrite `.env.example` as a short list of the env vars actually read (`PORT`, `PI_CWD`, `PI_PROVIDER`, `PI_MODEL`).
- **If we skip it:** Next reader tunes a knob that does nothing.

## Nice to have

### 10. Roundabout directory check (`fs-browser.ts`, `isDirectory`)
- `readdirSync(p) !== undefined && existsSync(p)` works only because readdirSync throws on files. `existsSync(p)` alone says the same thing. One call instead of two.

### 11. Hardcoded fallback URL repeated (`frontend/lib/screens/settings_screen.dart`)
- `ws://192.168.1.100:3000` is hardcoded 3× although `main.dart` already resolves the right URL from the page origin. Use `AppConfig.defaultServerUrl` or pass the resolved URL in.

### 12. No SIGTERM handler (`backend/src/index.ts`)
- systemd sends SIGTERM on stop; the handler only covers SIGINT. Harmless today (systemd kills the whole cgroup after 15s), but adding `"SIGTERM"` to the same handler is one word.

## Verdict

Healthy core; fix 1 and 2 first (a real bug + untested path logic), then the free wins 5, 8, 9.

Lean: −1,000–1,500 lines (mostly finding 7), −1 dependency possible.

Not checked: `pi_view_model.dart` (760 lines), screens/widgets internals, and whether Pi's RPC replies to `prompt` immediately or only at turn end — if it's at end, the 30-second timeouts in both clients will cut off long agent runs; verify before raising them.
