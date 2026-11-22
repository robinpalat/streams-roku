#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
python3 -m pipeline.configure
PORT="$(python3 - <<'PY'
import json
print(json.load(open('pipeline/config/roku.generated.json'))['port'])
PY
)"
UNIT="$ROOT/pipeline/server/roku-epg.service.generated"
USER_UNIT_DIR="$HOME/.config/systemd/user"
USER_UNIT="$USER_UNIT_DIR/roku-epg.service"

mkdir -p "$USER_UNIT_DIR" "$HOME/.local/state/streams-roku"
systemctl --user stop roku-epg.service 2>/dev/null || true

# Stop only our previous ad-hoc pipeline.serve process on the configured port.
LINE="$(ss -ltnp "sport = :$PORT" 2>/dev/null | tail -n +2 | head -n 1 || true)"
if [ -n "$LINE" ]; then
  PID="$(printf '%s\n' "$LINE" | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p')"
  if [ -n "$PID" ] && tr '\0' ' ' < "/proc/$PID/cmdline" 2>/dev/null | grep -q 'pipeline.serve'; then
    echo "deteniendo servidor ad-hoc previo en $PORT (pid $PID)"
    kill "$PID" 2>/dev/null || true
    sleep 1
  fi
fi
if ss -ltn "sport = :$PORT" 2>/dev/null | grep -q LISTEN; then
  echo "ERROR: puerto $PORT ocupado por otro proceso; libera el puerto o edita pipeline/config/roku.json" >&2
  exit 1
fi

cp "$UNIT" "$USER_UNIT"
systemctl --user daemon-reload
systemctl --user enable --now roku-epg.service

for i in 1 2 3 4 5; do
  if curl -fsS "http://127.0.0.1:$PORT/real/latest.json" >/dev/null 2>&1; then
    echo "OK: EPG server en http://0.0.0.0:$PORT/real/ (localhost:$PORT)"
    exit 0
  fi
  sleep 1
done

echo "ERROR: el servicio no respondió. Revisa:" >&2
echo "  systemctl --user status roku-epg.service" >&2
echo "  journalctl --user -u roku-epg.service" >&2
exit 1
