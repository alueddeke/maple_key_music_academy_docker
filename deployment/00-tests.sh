#!/usr/bin/env bash
# 00 — tests on the laptop: the backend suite against the local postgres:15
# (the same thing the Actions `test` job does with a service container).
# Runs in the dev api container so the DB, env and pytest config match CI.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
docker compose exec -T api pytest tests/ -p no:cacheprovider -q --no-cov
