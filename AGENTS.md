# AGENTS.md — Pi Mobile Agent

A Flutter web app + Node backend that drives a `pi --mode rpc` child process over
WebSocket. The backend serves the built web bundle and the WebSocket from the **same
port (3000)**, so a phone or laptop on the LAN just opens `http://<host>:3000`.

## This machine is the deployment target

`ubuntu-mancave` (this box, `192.168.2.1` / `desktop.mancave`) **is** where the app
runs. Do not SSH to deploy — build and restart here.

```bash
./deploy/install-service.sh            # build backend + web bundle, install unit, restart
./deploy/install-service.sh --no-web   # backend only, skip the Flutter build
```

The script is idempotent and safe to re-run after every change. It needs no sudo
(systemd **user** unit + `loginctl enable-linger`).

## Commands

| Task | Command |
| --- | --- |
| Build + deploy everything | `./deploy/install-service.sh` |
| Backend only | `cd backend && npm install --include=dev && npm run build` |
| Backend dev server (watch) | `cd backend && npm run dev` (tsx, port 3000) |
| Frontend only | `cd frontend && ~/flutter/bin/flutter pub get && ~/flutter/bin/flutter build web` |
| Frontend analyze / test | `cd frontend && ~/flutter/bin/flutter analyze` · `flutter test` |
| Backend tests | `cd backend && npm test` |
| Service status / logs | `systemctl --user status pi-mobile-agent` · `journalctl --user -u pi-mobile-agent -n 100 --no-pager` |
| Restart / stop | `systemctl --user restart\|stop pi-mobile-agent` |
| Health check | `curl http://localhost:3000/health` → `{"status":"ok","pi_connected":true,...}` |
| App | `http://192.168.2.1:3000` |

**Flutter is not on PATH in non-interactive shells.** It lives at `~/flutter/bin/flutter`;
the deploy script finds it itself, but a hand-run `flutter` command needs the full path.
`npm run build` must be run with devDependencies present (`tsc` is one).

## Architecture

```
backend/src/index.ts        Express + WebSocket server; owns currentCwd, spawns `pi --mode rpc`,
                            relays every Pi event to all connected clients
backend/src/pi-rpc-client.ts  RPC protocol wrapper over the pi child's stdio
backend/src/session-store.ts  Reads Pi's on-disk session history (list_sessions, sessionCwdOf)
backend/src/fs-browser.ts     Directory/file browsing for the app's folder picker
frontend/lib/main.dart        Entry; resolves the WebSocket URL (web: same host that served the page)
frontend/lib/services/pi_service.dart   WebSocket client, command send + event/state streams
frontend/lib/providers/pi_view_model.dart  All app state (ChangeNotifier)
frontend/lib/models/pi_models.dart      Wire types (PiState, PiMessage, PiModel, PiUsage, …)
frontend/lib/screens/home_screen.dart   Chat screen + AppBar + drawer menu
frontend/lib/widgets/                 chat_list, chat_bubble, file_browser, model_selector, context_meter
```

Adding a command end-to-end: `pi-rpc-client.ts` method → `case` in `index.ts` →
method in `pi_service.dart` → `PiViewModel` → widget. See `DEVELOPMENT.md`.

## Non-obvious constraints (read before editing)

- **Pi's cwd is fixed at spawn time.** There is no RPC `set_cwd`. Changing the working
  directory means **respawning the Pi child process** in the new directory. `currentCwd`
  is mutable; `piProcessCwd` is where the running child was actually spawned — keep them
  distinct so a resume follows Pi instead of guessing.
- **Pi's RPC `get_state` has no cwd.** The backend injects `cwd`, `cwdDisplay` (shrinkHome)
  and `gitBranch` into every state response. Anything the app bar shows about the
  directory has to come from those injected fields.
- **Sessions are persisted** (no `--no-session`) so `/resume` can reload them. Resuming
  re-enters the directory recorded in the session file.
- **`PI_PROVIDER` / `PI_MODEL` are unset in the unit on purpose** — Pi uses its own
  configured provider/model. Set them only to override.
- **The web build needs no `--dart-define`**: it connects to the host that served the
  page. Native builds do need `SERVER_URL`.
- **Port 3000 is unauthenticated LAN HTTP.** Don't expose it beyond the LAN without a
  reverse proxy with auth/WSS.

## Gotchas hit before

- **`Icons.git_commit` and `Icons.source_branch` do not exist** in the Flutter version
  pinned here (3.47.7 stable). `Icons.merge_type` and `Icons.folder_open` do. A bad
  `Icons.*` name only fails at the web compile step, with `Error: Member not found:`.
- **Do not use `Theme.of(context).colorScheme.onAppBar`** — it isn't a ColorScheme member.
  AppBar children inherit the right foreground colour; leave icon colours unset.
- `flutter build web` prints a harmless `Expected to find fonts for ... cupertino_icons`
  warning and a wasm dry-run notice. Success is the final `✓ Built build/web`.
- `systemctl --user …` from a non-login shell may need `XDG_RUNTIME_DIR`; the service
  itself is fine — verify with `systemctl --user is-active pi-mobile-agent`.
- A `PiViewModel` field that the AppBar reads must be exposed through the ViewModel and
  fed from `piService.stateUpdates`, not read from a widget-local state.
- **When you are driving this repo *from* the app, you are the service's child process.**
  The tree is `systemd → node dist/index.js → pi → your tool calls`, so
  `systemctl --user restart pi-mobile-agent` stops the node process, which stops the Pi
  running you, which ends the tool call with `SIGTERM` (exit 143). The restart still
  succeeds — it just outlives the command that asked for it.
- **A frontend-only change needs no restart.** The backend serves `frontend/build/web`
  from disk with `no-store` on `index.html`, so `flutter build web` is live on the next
  page load. Restart only for a backend change. When in doubt, compare
  `curl -s localhost:3000/main.dart.js | grep -c <a-string-only-the-new-code-has>`
  against the same count in `frontend/build/web/main.dart.js` — they must match.

## Style

- TypeScript ESM (`"type": "module"`), Node 18+ (22 on this box). `tsc` → `backend/dist`.
- Dart: follow the existing file-comment style — this codebase explains *why* in comments,
  not just *what*. Match that when touching `home_screen.dart`, `pi_view_model.dart`, etc.
- Keep tool/UI behaviour independent where a non-interactive mode could hit it.
- Don't add a dependency without a real need; the frontend deliberately keeps the tree small.

## Repo docs

`README.md` (overview) · `DEPLOYMENT.md` (service install, unit config, current host) ·
`DEVELOPMENT.md` (dev workflow, adding a command) · `API_REFERENCE.md` (WebSocket protocol) ·
`PROJECT_STRUCTURE.md` · `QUICKSTART.md` · `CHECKLIST.md`. Several `*_SUMMARY.md` files are
dated change notes, not current docs — don't treat them as authoritative.

## Definition of done

For any change: build it (`./deploy/install-service.sh`), confirm
`curl localhost:3000/health` is ok, and push to `main` (`https://github.com/phobicadz/pi-mobile-agent`).
Restart the service only when a **backend** file changed — and see the child-process note
above before doing that from inside the app.
