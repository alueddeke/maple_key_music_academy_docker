#!/usr/bin/env bash
# 11 — migration gate: runs against the LIVE database BEFORE stopping any
# running container. If this fails, production keeps serving traffic unchanged.
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
require_deploy_env

banner "Running database migrations..."
if ! docker run --rm \
  --network maple-key-network \
  "${BACKEND_ENV[@]}" \
  "$IMAGE" \
  python manage.py migrate; then
  banner "❌ MIGRATION FAILED — deploy aborted
Production is unchanged and still serving traffic."
  exit 1
fi
echo "✅ Migrations completed successfully"

# Verify no unapplied migrations remain
if ! docker run --rm \
  --network maple-key-network \
  "${BACKEND_ENV[@]}" \
  "$IMAGE" \
  python manage.py migrate --check; then
  echo "❌ Unapplied migrations detected after migrate run — deploy aborted"
  exit 1
fi
echo "✅ All migrations verified as applied"
