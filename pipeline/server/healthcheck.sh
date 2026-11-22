#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="$(python3 - <<PY
import json
print(json.load(open('$ROOT/pipeline/config/roku.generated.json'))['port'])
PY
)"
URL="http://127.0.0.1:$PORT/real/latest.json"
if curl -fsS "$URL" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null; then
  echo "OK: $URL"
  exit 0
fi
echo "FAIL: $URL"
exit 1
