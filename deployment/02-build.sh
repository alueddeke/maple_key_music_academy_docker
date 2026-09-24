#!/usr/bin/env bash
# 02 — build the backend image on the laptop with buildx, tagged :latest and
# :<git sha> exactly as the Actions build_and_push job tags it. The droplet
# is linux/amd64.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BACKEND="${BACKEND_DIR:-$HERE/../../maple_key_music_academy_backend}"
: "${DOCKER_USERNAME:?DOCKER_USERNAME must be exported}"
SHA="$(git -C "$BACKEND" rev-parse HEAD)"
docker buildx build \
  --platform linux/amd64 \
  --load \
  -t "$DOCKER_USERNAME/maple-key-backend:latest" \
  -t "$DOCKER_USERNAME/maple-key-backend:$SHA" \
  "$BACKEND"
echo "built $DOCKER_USERNAME/maple-key-backend:{latest,$SHA}"
