#!/usr/bin/env bash
# Restore drill (MAP-140): replay one backup into a THROWAWAY Postgres
# container and prove it holds data. Never touches the live database — the
# only container this script runs psql in is the one it creates, with no
# network and no published port; it is removed on every exit.
#
#   scripts/restore_drill.sh ~/maplekey-backups/nightly-YYYYMMDD-HHMMSS.sql.gz   # a local plaintext file
#   scripts/restore_drill.sh FILE.sql.gz.age < identity                          # a local encrypted file
#   scripts/restore_drill.sh --latest-remote < identity                          # newest nightly in the bucket
#
# Encrypted dumps (*.age — every off-box copy) need the age identity on stdin.
# It never lives on the droplet; pipe it from the Mac:
#
#   op read 'op://Private/Maple Key Backup age Identity/credential' \
#     | ssh root@159.203.173.226 'bash /opt/maple_key_music_academy_docker/scripts/restore_drill.sh --latest-remote'
#
# --latest-remote reads the bucket credentials from the same file as
# backup_nightly.sh (/root/.config/maplekey/backup.env, or --env-file). Pass:
# both counts below are > 0 and psql replayed the dump with ON_ERROR_STOP.
# Record the output on MAP-140 / in OPS-RUNBOOK "Restore drill".
set -euo pipefail

NAME=maplekey-restore-drill
IMAGE=postgres:15             # = prod major (deployment/10-preflight.sh)
ROLE=maple_key_user           # dump's OWNER statements need this role to exist
ENV_FILE=/root/.config/maplekey/backup.env
SRC=""

usage() { echo "usage: $0 FILE.sql.gz | FILE.sql.gz.age | --latest-remote [--env-file PATH]  (encrypted: identity on stdin)" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --env-file)      ENV_FILE="$2"; shift 2 ;;
    --latest-remote) [ -z "$SRC" ] || usage; SRC=--latest-remote; shift ;;
    -*)              usage ;;
    *)               [ -z "$SRC" ] || usage; SRC="$1"; shift ;;
  esac
done
[ -n "$SRC" ] || usage

file_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

# Checked before the cleanup trap exists, so refusing never removes another
# run's container (W0-L1).
if docker container inspect "$NAME" >/dev/null 2>&1; then
  echo "container $NAME already exists — a drill is running or was killed; remove it first" >&2
  exit 1
fi

WORK=$(mktemp -d)
STARTED=""
cleanup() { [ -z "$STARTED" ] || docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

if [ "$SRC" = "--latest-remote" ]; then
  # Same preconditions as backup_nightly.sh (W0-L2).
  command -v rclone >/dev/null || { echo "rclone not installed (apt-get install -y rclone)" >&2; exit 1; }
  [ -f "$ENV_FILE" ] || { echo "missing $ENV_FILE (OPS-RUNBOOK script D)" >&2; exit 1; }
  [ "$(file_mode "$ENV_FILE")" = 600 ] || { echo "$ENV_FILE must be mode 600" >&2; exit 1; }
  set -a
  # droplet-only file, path chosen at runtime
  # shellcheck source=/dev/null
  . "$ENV_FILE"
  set +a
  REMOTE="offsite:${BACKUP_BUCKET:?BACKUP_BUCKET not set in $ENV_FILE}/postgres"
  LATEST=$(rclone lsf --files-only --include 'nightly-*.sql.gz.age' "$REMOTE" | sort | tail -1)
  [ -n "$LATEST" ] || { echo "no nightly-*.sql.gz.age in $REMOTE" >&2; exit 1; }
  rclone copyto "$REMOTE/$LATEST" "$WORK/$LATEST"
  DUMP="$WORK/$LATEST"
else
  DUMP="$SRC"
fi
[ -s "$DUMP" ] || { echo "not a non-empty file: $DUMP" >&2; exit 1; }

case "$DUMP" in
  *.age)
    command -v age >/dev/null || { echo "age not installed (apt-get install -y age)" >&2; exit 1; }
    [ ! -t 0 ] || { echo "encrypted dump: pipe the age identity on stdin (see the header of this script)" >&2; exit 1; }
    (umask 077; cat > "$WORK/identity")
    [ -s "$WORK/identity" ] || { echo "no age identity on stdin" >&2; exit 1; }
    age -d -i "$WORK/identity" -o "$WORK/dump.sql.gz" "$DUMP"
    rm -f "$WORK/identity"
    GZ="$WORK/dump.sql.gz"
    ;;
  *) GZ="$DUMP" ;;
esac
gzip -t "$GZ"
echo "restoring $(basename "$DUMP") into throwaway container $NAME"

docker run -d --name "$NAME" --network none \
  -e POSTGRES_USER="$ROLE" -e POSTGRES_DB=restore_drill \
  -e POSTGRES_PASSWORD="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')" \
  "$IMAGE" >/dev/null
STARTED=1

# TCP probe: the image's init phase answers on the socket only, then restarts;
# 127.0.0.1 is up only once the real server is.
for _ in $(seq 1 60); do
  docker exec "$NAME" pg_isready -q -h 127.0.0.1 -U "$ROLE" && break
  sleep 1
done
docker exec "$NAME" pg_isready -q -h 127.0.0.1 -U "$ROLE"

gunzip -c "$GZ" | docker exec -i "$NAME" psql -q -v ON_ERROR_STOP=1 -U "$ROLE" -d restore_drill >/dev/null

USERS=$(docker exec "$NAME" psql -At -U "$ROLE" -d restore_drill -c "SELECT count(*) FROM billing_user;")
INVOICES=$(docker exec "$NAME" psql -At -U "$ROLE" -d restore_drill -c "SELECT count(*) FROM billing_prebillinginvoice;")
echo "billing_user: $USERS"
echo "billing_prebillinginvoice: $INVOICES"
[ "$USERS" -gt 0 ] && [ "$INVOICES" -gt 0 ] || { echo "restore drill FAILED: empty tables" >&2; exit 1; }
echo "restore drill PASSED ($(basename "$DUMP")); container removed on exit"
