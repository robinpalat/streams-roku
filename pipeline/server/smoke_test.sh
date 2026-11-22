#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="$(python3 - <<PY
import json
print(json.load(open('$ROOT/pipeline/config/roku.generated.json'))['port'])
PY
)"
for artifact in latest.json catalog.json epg.json coverage.json; do
  URL="http://127.0.0.1:$PORT/real/$artifact"
  BODY="$(mktemp)"
  CODE="$(curl -sS -o "$BODY" -w '%{http_code}' "$URL")"
  TYPE="$(curl -sSI "$URL" | tr -d '\r' | awk -F': ' 'tolower($1)=="content-type"{print $2}' | tail -1)"
  if [ "$CODE" != "200" ]; then echo "FAIL $artifact HTTP $CODE"; rm -f "$BODY"; exit 1; fi
  if ! python3 -m json.tool "$BODY" >/dev/null; then echo "FAIL $artifact invalid JSON"; rm -f "$BODY"; exit 1; fi
  echo "OK $artifact HTTP 200 ${TYPE:-?} $(wc -c < "$BODY") bytes"
  rm -f "$BODY"
done
if curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/ | grep -q '^200$'; then
  echo "OK puerto 8000 sigue sirviendo su contenido"
fi
