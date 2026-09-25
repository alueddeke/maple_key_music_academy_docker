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
sleep 3
if docker ps | grep -q maple-key-backend && docker ps | grep -q postgres && docker ps | grep -q nginx; then
  echo "✅ Backend, PostgreSQL, and Nginx deployed successfully!"
  FINAL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://api.maplekeymusic.com/api/auth/user/ 2>/dev/null || echo "000")
  echo "Final API health check: HTTP $FINAL_STATUS (expect 401)"
  if [ "$FINAL_STATUS" != "401" ] && [ "$FINAL_STATUS" != "200" ]; then
    echo "⚠️  API not returning expected status — check logs: docker logs maple-key-backend"
  fi
else
  echo "❌ Container check failed!"
  docker logs maple-key-backend --tail 30 2>/dev/null || true
  exit 1
fi

echo "Running images (compare across deploy paths):"
for c in maple-key-backend maple-key-worker maple-key-scheduler; do
  printf '  %-22s %s\n' "$c" "$(docker inspect "$c" --format='{{.Config.Image}} {{.Image}}' 2>/dev/null || echo '(not running)')"
done
