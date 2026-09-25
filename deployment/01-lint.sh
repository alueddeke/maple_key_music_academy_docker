#!/usr/bin/env bash
# 01 — lint on the laptop: the config-fallback guard the Actions `test` job
# runs first (MAP-181). ruff/eslint are not part of the backend deploy gate
# today; add them here when they gate CI.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BACKEND="${BACKEND_DIR:-$HERE/../../maple_key_music_academy_backend}"
cd "$BACKEND"
bash scripts/check-no-fallbacks.sh
