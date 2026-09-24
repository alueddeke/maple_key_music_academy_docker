#!/usr/bin/env bash
# 10 — preflight: registry login, volumes/network, pull the image BEFORE
# touching any running container, make sure postgres is up, then the backup
# that is the explicit opening move of every deploy (Aug 28 audit item 1).
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
require_deploy_env

# Login to Docker Hub
echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin

# Ensure volumes and network exist
docker volume create postgres_data || true
docker volume create static_volume || true
docker network create maple-key-network || true

# Pull new image BEFORE touching any running container
docker pull "$IMAGE"

# ===== ENSURE POSTGRES IS RUNNING =====
# Reuse the existing container if healthy — don't restart it unnecessarily.
# Only start a fresh postgres if the container is absent or stopped.
if ! docker ps --filter "name=^postgres$" --filter "status=running" -q | grep -q .; then
  echo "PostgreSQL not running — starting..."
  docker rm postgres 2>/dev/null || true
  docker run -d \
    --name postgres \
    --restart unless-stopped \
    --network maple-key-network \
    -e "POSTGRES_USER=${POSTGRES_USER}" \
    -e "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" \
    -e "POSTGRES_DB=${POSTGRES_DB}" \
    -v postgres_data:/var/lib/postgresql/data \
    postgres:15
  echo "Waiting for PostgreSQL to be ready..."
  sleep 10
else
  echo "PostgreSQL already running — reusing existing instance"
fi

# Verify postgres is reachable
docker run --rm --network maple-key-network postgres:15 \
  pg_isready -h postgres -U "$POSTGRES_USER" \
  || { echo "❌ Cannot reach PostgreSQL — aborting"; exit 1; }

# ===== BACKUP FIRST =====
# A dump is taken BEFORE migrations or any container change, so rollback
# always has a pre-deploy anchor. Retention: nothing younger than 30 days is
# ever deleted (3-3-30 policy).
banner "Backing up database before deploy..."
BACKUP_DIR="$HOME/maplekey-backups"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/pre-deploy-$(date -u +%Y%m%d-%H%M%S).sql.gz"
docker exec postgres pg_dump \
  -U "$POSTGRES_USER" "$POSTGRES_DB" \
  | gzip > "$BACKUP_FILE"
if [ ! -s "$BACKUP_FILE" ]; then
  echo "❌ Backup file is empty — aborting deploy"
  exit 1
fi
echo "✅ Backup written: $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"
# Prune backups older than 30 days (never younger)
find "$BACKUP_DIR" -name 'pre-deploy-*.sql.gz' -mtime +30 -delete || true
