#!/usr/bin/env bash
# 12 — swap the backend: capture OLD_IMAGE for rollback, collectstatic, swap
# the container, health-check on the loopback port, roll back on failure.
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
require_deploy_env

# ===== SAFE TO SWAP CONTAINERS =====
# Migrations passed. Capture current image for rollback before touching anything.
OLD_IMAGE=$(docker inspect maple-key-backend --format='{{.Config.Image}}' 2>/dev/null || echo "")
echo "Old image for rollback: ${OLD_IMAGE:-none}"

# Collect static files (throwaway container, postgres still running)
docker run --rm \
  --network maple-key-network \
  "${BACKEND_ENV[@]}" \
  -v static_volume:/app/staticfiles \
  "$IMAGE" \
  python manage.py collectstatic --noinput

# Create log directory on host (survives container restarts)
mkdir -p /var/log/maple-key

# Swap backend container (postgres stays running throughout)
docker stop maple-key-backend 2>/dev/null || true
docker rm maple-key-backend 2>/dev/null || true

docker run -d \
  --name maple-key-backend \
  --restart unless-stopped \
  --health-cmd "python3 /app/healthcheck.py" \
  --health-interval 30s \
  --health-timeout 10s \
  --health-retries 3 \
  --network maple-key-network \
  -p 127.0.0.1:8001:8000 \
  "${BACKEND_ENV[@]}" \
  -v /var/log/maple-key:/var/log/maple-key \
  -v static_volume:/app/staticfiles \
  "$IMAGE"

# ===== HEALTH CHECK WITH ROLLBACK =====
# Poll /api/auth/user/ directly on port 8001 (loopback-bound, bypasses nginx).
# Expects 401 (auth required) meaning Django/gunicorn is up.
echo "Health checking new backend (30s window)..."
HEALTHY=false
for i in $(seq 1 6); do
  sleep 5
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8001/api/auth/user/ 2>/dev/null || echo "000")
  if [ "$HTTP_STATUS" = "401" ] || [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "301" ]; then
    HEALTHY=true
    echo "✅ Backend healthy (HTTP $HTTP_STATUS) after $((i * 5))s"
    break
  fi
  echo "  Attempt $i/6: HTTP $HTTP_STATUS — waiting..."
done

if [ "$HEALTHY" = "false" ]; then
  banner "❌ Health check failed — rolling back"
  echo "Failed container logs:"
  docker logs maple-key-backend --tail 50 2>/dev/null || true
  docker stop maple-key-backend 2>/dev/null || true
  docker rm maple-key-backend 2>/dev/null || true
  if [ -n "$OLD_IMAGE" ]; then
    echo "Restoring previous image: $OLD_IMAGE"
    docker run -d \
      --name maple-key-backend \
      --restart unless-stopped \
      --network maple-key-network \
      "${BACKEND_ENV[@]}" \
      -v /var/log/maple-key:/var/log/maple-key \
      -v static_volume:/app/staticfiles \
      "$OLD_IMAGE"
    echo "⚠️  Rolled back to $OLD_IMAGE — production restored"
  else
    echo "⚠️  No previous image to roll back to — manual intervention required"
  fi
  exit 1
fi
