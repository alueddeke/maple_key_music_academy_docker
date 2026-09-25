#!/usr/bin/env bash
# 03 — push both tags to Docker Hub (what the Actions build_and_push job does).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BACKEND="${BACKEND_DIR:-$HERE/../../maple_key_music_academy_backend}"
: "${DOCKER_USERNAME:?DOCKER_USERNAME must be exported}"
: "${DOCKER_PASSWORD:?DOCKER_PASSWORD must be exported}"
SHA="$(git -C "$BACKEND" rev-parse HEAD)"
echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
docker push "$DOCKER_USERNAME/maple-key-backend:latest"
docker push "$DOCKER_USERNAME/maple-key-backend:$SHA"
