# Deploying as a service (Linux)

Runs the backend **and** the Flutter web bundle as one systemd service on a Linux
box. The backend serves `frontend/build/web` from the same port it speaks
WebSocket on, so a phone or laptop on the LAN just opens `http://<host>:3000` —
no separate frontend host, no CORS, no rebuild when the IP changes.

## What gets installed

| Piece | Where |
| --- | --- |
| Backend | `<repo>/backend` → `node dist/index.js` |
| Frontend | `<repo>/frontend/build/web`, served statically by the backend on the same port |
| Service | `~/.config/systemd/user/pi-mobile-agent.service` (systemd **user** unit, no sudo) |
| Autostart | `loginctl enable-linger` + `systemctl --user enable` → starts at boot, restarts on failure |
| Logs | `journalctl --user -u pi-mobile-agent` |

## One-time setup on the target machine

```bash
# 1. Code + runtime
git clone https://github.com/phobicadz/pi-mobile-agent.git ~/source/repos/pi-mobile-agent
# node 18+, git, and `pi` (the Pi CLI, logged in) must be available.
# Flutter is only needed to build the web bundle; install it without sudo:
curl -L -o /tmp/flutter.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_<version>-stable.tar.xz
tar -xJf /tmp/flutter.tar.xz -C ~/        # -> ~/flutter/bin/flutter

# 2. Build + install + start the service
cd ~/source/repos/pi-mobile-agent
./deploy/install-service.sh
```

The script is idempotent — re-run it after every change (`--no-web` skips the
Flutter build). It builds the backend, builds the web bundle, writes the unit to
`~/.config/systemd/user/`, enables linger, and starts the service.

## Controlling the service

```bash
systemctl --user status  pi-mobile-agent
systemctl --user restart pi-mobile-agent
systemctl --user stop    pi-mobile-agent
journalctl --user -u pi-mobile-agent -f          # live logs
curl http://localhost:3000/health               # {"status":"ok","pi_connected":true}
```

## Service configuration

Everything lives in `deploy/pi-mobile-agent.service`:

- `PORT` — single port for the web app, HTTP API and WebSocket.
- `PI_CWD` — directory Pi starts in (change it at runtime with the folder button
  in the app; the backend respawns Pi in the new directory).
- `PATH` — must include wherever `pi` is installed (`~/.local/bin` for the
  managed installer, `/usr/local/bin` for `npm install -g`).
- `PI_PROVIDER` / `PI_MODEL` — **optional**. When unset the backend starts Pi with
  whatever provider/model Pi itself is configured with (`pi /login`,
  `~/.pi/agent/settings.json`, installed provider extensions). Set them only to
  override.

## Notes

- **User unit vs system unit.** A user unit runs as your own user, so it can read
  `~/.pi` (Pi's credentials, sessions, extensions) without any chowning. To run
  it as a system service instead, copy the unit to `/etc/systemd/system/`, add
  `User=<you>` under `[Service]`, drop the `%h` tokens (absolute paths), and use
  `sudo systemctl enable --now pi-mobile-agent` — but then `HOME` must be set
  explicitly for Pi to find its config.
- **Pi auth.** The service inherits the user's environment, so the provider
  credentials Pi was logged in with are used. Run `pi /login` as that user first.
- **Local model servers.** If Pi talks to a local inference server (e.g. a
  llama.cpp server on `127.0.0.1:8083`), start that server as a service too — the
  backend does not manage it.
- **Exposure.** Port 3000 is unauthenticated LAN HTTP. Fine on a trusted network;
  put it behind a reverse proxy with auth/WSS before exposing it beyond the LAN.
- **Docker alternative.** `docker-compose.yml` in the repo root runs the backend in
  a container (`restart: unless-stopped`, `~/.pi` mounted). The systemd route above
  is preferred on a machine you already log into: it reuses the host's Pi install,
  sessions and extensions, and the web bundle is rebuilt in place.

## Currently deployed

`pi-mobile-agent` runs on **mancave desktop** (`desktop.mancave`, Ubuntu 26.04,
user `adam`) at `http://192.168.2.1:3000` — repo in `~/source/repos/pi-mobile-agent`,
Flutter SDK in `~/flutter`, service unit `~/.config/systemd/user/pi-mobile-agent.service`.
