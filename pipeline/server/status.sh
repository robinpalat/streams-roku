#!/usr/bin/env bash
set -euo pipefail
systemctl --user status roku-epg.service --no-pager || true
"$(dirname "$0")/healthcheck.sh" || true
