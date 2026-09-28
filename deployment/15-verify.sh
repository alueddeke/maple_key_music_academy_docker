#!/usr/bin/env bash
# 15 — verify: prune old images, confirm the three core containers are up,
# hit the public API, and print the running image digests so the Actions
# path and the laptop path can be compared byte-for-byte (MAP-189 will turn
# the digest print into an assertion).
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
  FINAL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://api.maplekeymusic.com/api/auth/user/ 2>/dev/null || echo "000")
  echo "Final API health check: HTTP $FINAL_STATUS (expect 401)"
  if [ "$FINAL_STATUS" != "401" ] && [ "$FINAL_STATUS" != "200" ]; then
    echo "⚠️  API not returning expected status — check logs: docker logs maple-key-backend"
  fi
else
  echo "❌ Container check failed! Not running: ${missing[*]}"
  docker logs maple-key-backend --tail 30 2>&1 || true
  exit 1
fi

echo "Running images (compare across deploy paths):"
for c in maple-key-backend maple-key-worker maple-key-scheduler; do
  printf '  %-22s %s\n' "$c" "$(docker inspect "$c" --format='{{.Config.Image}} {{.Image}}' 2>/dev/null || echo '(not running)')"
done
