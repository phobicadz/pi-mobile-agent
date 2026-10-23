#!/usr/bin/env bash
# Build (frontend web bundle + backend) and (re)install the pi-mobile-agent
# systemd user service on this machine. Safe to re-run after every change.
#
#   ./deploy/install-service.sh          # build everything + restart the service
#   ./deploy/install-service.sh --no-web # backend only (skip flutter build)
#
# Requires: node, npm, git; flutter only for the web bundle.
# No sudo needed: the unit is installed as a systemd *user* service and started
# at boot via loginctl enable-linger.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_NAME="pi-mobile-agent"
UNIT_DIR="$HOME/.config/systemd/user"
SKIP_WEB=0
[[ "${1:-}" == "--no-web" ]] && SKIP_WEB=1

log() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

log "Backend: install deps + compile TypeScript"
cd "$ROOT/backend"
npm install
npm run build

if [[ $SKIP_WEB -eq 0 ]]; then
  if command -v flutter >/dev/null 2>&1; then
    log "Frontend: flutter pub get + flutter build web"
    cd "$ROOT/frontend"
    flutter config --no-analytics >/dev/null 2>&1 || true
    flutter pub get
    # No --dart-define needed: the web build connects to the host that served it.
    flutter build web
  else
    echo "flutter not found - skipping the web bundle (API/WebSocket still work)"
  fi
fi

log "Installing systemd user unit: $UNIT_NAME"
mkdir -p "$UNIT_DIR"
# %h expands to the user's home directory inside a systemd user unit; only the
# repo path is rewritten so the unit follows the checkout wherever it lives.
sed "s#%h/source/repos/pi-mobile-agent#$ROOT#g" "$ROOT/deploy/pi-mobile-agent.service" \
  > "$UNIT_DIR/$UNIT_NAME.service"
cat "$UNIT_DIR/$UNIT_NAME.service"

log "Enabling linger (start at boot without a graphical login) + (re)starting"
loginctl enable-linger "$(id -un)" 2>/dev/null || \
  echo "warning: could not enable linger; the service starts on login instead"
systemctl --user daemon-reload
systemctl --user enable --now "$UNIT_NAME"
sleep 2
systemctl --user --no-pager status "$UNIT_NAME" || true

HOST=$(hostname -I 2>/dev/null | awk '{print $1}')
PORT=$(grep -m1 '^Environment=PORT=' "$UNIT_DIR/$UNIT_NAME.service" | cut -d= -f3)
log "Done"
echo "Web app + API:  http://${HOST:-localhost}:${PORT:-3000}"
echo "Health:         curl http://${HOST:-localhost}:${PORT:-3000}/health"
echo "Logs:           journalctl --user -u $UNIT_NAME -f"
echo "Stop/restart:   systemctl --user {stop,restart} $UNIT_NAME"
