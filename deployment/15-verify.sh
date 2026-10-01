#!/usr/bin/env bash
# 15 — verify: prune old images, confirm the three core containers are up,
# assert the public API answers 401, assert every backend-image container
# runs exactly $IMAGE (MAP-189), and print the running image digests so the
# Actions path and the laptop path can be compared byte-for-byte.
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
require_deploy_env

# Clean up old images
docker image prune -f

# Final verification
# Capture the names once and match them exactly: `docker ps | grep -q` under
# pipefail went false when grep's early exit SIGPIPE'd docker (MAP-230), and a
# substring also matched the image column of other containers.
sleep 3
names=$(docker ps --format '{{.Names}}') || names=""
missing=()
for c in maple-key-backend postgres nginx; do
  grep -qx "$c" <<<"$names" || missing+=("$c")
done
if [ ${#missing[@]} -eq 0 ]; then
  echo "✅ Backend, PostgreSQL, and Nginx deployed successfully!"
  # The public path (nginx → gunicorn) must answer 401 — auth required,
  # nothing cached, nothing redirected. Anything else fails the deploy
  # (MAP-189); the containers are left as they are for inspection.
  FINAL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://api.maplekeymusic.com/api/auth/user/ 2>/dev/null || echo "000")
  echo "Final API health check: HTTP $FINAL_STATUS (expect 401)"
  if [ "$FINAL_STATUS" != "401" ]; then
    echo "❌ API not returning 401 — check logs: docker logs maple-key-backend"
    exit 1
  fi
else
  echo "❌ Container check failed! Not running: ${missing[*]}"
  docker logs maple-key-backend --tail 30 2>&1 || true
  exit 1
fi

# ===== IMAGE-ID ASSERTION (MAP-189) =====
# Every backend-image container must run exactly the image this deploy
# pulled: compare image IDs, never tag strings (a container's .Image is an
# ID; the tag it was started from can be re-pointed later). A silently
# skipped swap, or a worker/scheduler that is not running at all, shows up
# here as a mismatch and fails the deploy — nothing is rolled back (the
# backend already passed health), the operator sees exactly which container
# diverged.
EXPECTED_ID=$(docker image inspect "$IMAGE" --format '{{.Id}}' 2>/dev/null) \
  || { echo "❌ Cannot inspect $IMAGE — was it pulled?"; exit 1; }
mismatch=()
for c in maple-key-backend maple-key-worker maple-key-scheduler; do
  running_id=$(docker inspect "$c" --format '{{.Image}}' 2>/dev/null) || running_id="(not running)"
  [ "$running_id" = "$EXPECTED_ID" ] || mismatch+=("$c=$running_id")
done
if [ ${#mismatch[@]} -gt 0 ]; then
  echo "❌ Image mismatch — expected $IMAGE ($EXPECTED_ID):"
  for m in "${mismatch[@]}"; do echo "  $m"; done
  exit 1
fi
echo "✅ backend, worker and scheduler all run $IMAGE"

echo "Running images (compare across deploy paths):"
for c in maple-key-backend maple-key-worker maple-key-scheduler; do
  printf '  %-22s %s\n' "$c" "$(docker inspect "$c" --format='{{.Config.Image}} {{.Image}}' 2>/dev/null || echo '(not running)')"
done
