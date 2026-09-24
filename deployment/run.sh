#!/usr/bin/env bash
# Runs the droplet stages 10–15 in order. The numbering is the ordering
# contract; a stage that exits non-zero stops the deploy (each stage owns its
# own rollback, as the inline workflow did).
#
# Environment: deploy.env next to this file (written by the Actions workflow
# or by deploy-from-laptop.sh), sourced here and deleted on exit so no secret
# stays on disk. Either entry point ends up running exactly this.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$HERE/deploy.env"

[ -f "$ENV_FILE" ] || { echo "❌ $ENV_FILE missing — nothing deployed"; exit 1; }
trap 'rm -f "$ENV_FILE"' EXIT
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

for stage in "$HERE"/1[0-9]-*.sh; do
  echo
  echo "▶ $(basename "$stage")"
  bash "$stage"
done

echo
echo "✅ deploy complete"
