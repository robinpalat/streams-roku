#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRS="${BRS:-brs}"
if ! command -v "$BRS" >/dev/null 2>&1; then
  echo "brs interpreter not found. Run: npm install --prefix tests/brs && BRS=tests/brs/node_modules/.bin/brs tests/run_brs_tests.sh" >&2
  exit 2
fi
"$BRS" --root "$ROOT" --component-dirs components \
  source/app_config.brs source/util.brs source/m3u_parser.brs source/m3u_update.brs source/catalog.brs source/epg.brs source/logo_geometry.brs components/EpgGrid.brs \
  tests/brs/m3u_update_test.brs
