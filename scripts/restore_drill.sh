#!/usr/bin/env bash
# Restore drill (MAP-140): replay one backup into a THROWAWAY Postgres
# container and prove it holds data. Never touches the live database — the
# only container this script runs psql in is the one it creates, with no
# network and no published port; it is removed on every exit.
#
#   scripts/restore_drill.sh ~/maplekey-backups/nightly-YYYYMMDD-HHMMSS.sql.gz   # a local file
#   scripts/restore_drill.sh --latest-remote                                    # newest nightly in the bucket
#
# --latest-remote reads the bucket credentials from the same file as
# backup_nightly.sh (/root/.config/maplekey/backup.env). Pass: both counts
# below are > 0 and psql replayed the dump with ON_ERROR_STOP. Record the
# output on MAP-140 / in OPS-RUNBOOK "Restore drill".
set -euo pipefail

NAME=maplekey-restore-drill
IMAGE=postgres:15             # = prod major (deployment/10-preflight.sh)
ROLE=maple_key_user           # dump's OWNER statements need this role to exist
ENV_FILE=/root/.config/maplekey/backup.env

[ $# -eq 1 ] || { echo "usage: $0 FILE.sql.gz | --latest-remote" >&2; exit 2; }

WORK=$(mktemp -d)
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

if [ "$1" = "--latest-remote" ]; then
  set -a; . "$ENV_FILE"; set +a
  REMOTE="spaces:${BACKUP_BUCKET:?BACKUP_BUCKET not set in $ENV_FILE}/postgres"
  LATEST=$(rclone lsf --files-only --include 'nightly-*.sql.gz' "$REMOTE" | sort | tail -1)
  [ -n "$LATEST" ] || { echo "no nightly-*.sql.gz in $REMOTE" >&2; exit 1; }
  rclone copyto "$REMOTE/$LATEST" "$WORK/$LATEST"
  DUMP="$WORK/$LATEST"
else
  DUMP="$1"
fi
[ -s "$DUMP" ] || { echo "not a non-empty file: $DUMP" >&2; exit 1; }
gzip -t "$DUMP"
echo "restoring $DUMP into throwaway container $NAME"

if docker container inspect "$NAME" >/dev/null 2>&1; then
  echo "container $NAME already exists — a drill is running or was killed; remove it first" >&2
  exit 1
fi
docker run -d --name "$NAME" --network none \
  -e POSTGRES_USER="$ROLE" -e POSTGRES_DB=restore_drill \
  -e POSTGRES_PASSWORD="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')" \
  "$IMAGE" >/dev/null

# TCP probe: the image's init phase answers on the socket only, then restarts;
# 127.0.0.1 is up only once the real server is.
for _ in $(seq 1 60); do
  docker exec "$NAME" pg_isready -q -h 127.0.0.1 -U "$ROLE" && break
  sleep 1
done
docker exec "$NAME" pg_isready -q -h 127.0.0.1 -U "$ROLE"

gunzip -c "$DUMP" | docker exec -i "$NAME" psql -q -v ON_ERROR_STOP=1 -U "$ROLE" -d restore_drill >/dev/null

USERS=$(docker exec "$NAME" psql -At -U "$ROLE" -d restore_drill -c "SELECT count(*) FROM billing_user;")
INVOICES=$(docker exec "$NAME" psql -At -U "$ROLE" -d restore_drill -c "SELECT count(*) FROM billing_prebillinginvoice;")
echo "billing_user: $USERS"
echo "billing_prebillinginvoice: $INVOICES"
[ "$USERS" -gt 0 ] && [ "$INVOICES" -gt 0 ] || { echo "restore drill FAILED: empty tables" >&2; exit 1; }
echo "restore drill PASSED ($(basename "$DUMP")); container removed on exit"
