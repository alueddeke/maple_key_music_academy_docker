#!/usr/bin/env bash
# Nightly off-box Postgres backup (MAP-140). Runs on the backend droplet from
# root's crontab:
#
#   30 6 * * * /opt/maple_key_music_academy_docker/scripts/backup_nightly.sh >> /var/log/maplekey-backup.log 2>&1
#
# pg_dump (same form as deployment/10-preflight.sh) → gzip → verify → upload to
# the S3-compatible bucket via rclone → prune remote objects older than 30 days
# → write the node-exporter textfile metric backup_last_success_timestamp.
# Any failure exits non-zero and leaves the metric untouched, so the Grafana
# rule "Nightly backup stale" (alerts.yaml, uid backup-stale) fires once the
# last success is older than 26 h. The pre-deploy backup in 10-preflight.sh is
# separate and unchanged.
#
# Bucket credentials: /root/.config/maplekey/backup.env (mode 600, droplet
# only, written from 1Password "Maple Key Backup Spaces Key" — OPS-RUNBOOK
# script D). It exports BACKUP_BUCKET and RCLONE_CONFIG_SPACES_* (rclone's
# env-configured remote "spaces:"); nothing secret is passed on a command line.
#
#   scripts/backup_nightly.sh                                  # prod: container "postgres"
#   BACKUP_DIR=/tmp/w scripts/backup_nightly.sh --container maple_key_db \
#       --local-dir /tmp/bucket --textfile-dir /tmp/tf         # dry run: local dir stands in for the bucket
set -euo pipefail

CONTAINER=postgres
LOCAL_DEST=""
TEXTFILE_DIR=/var/lib/node_exporter/textfile_collector
ENV_FILE=/root/.config/maplekey/backup.env
BACKUP_DIR="${BACKUP_DIR:-$HOME/maplekey-backups}"
RETENTION_DAYS=30
LOCAL_KEEP_DAYS=3

while [ $# -gt 0 ]; do
  case "$1" in
    --container)    CONTAINER="$2"; shift 2 ;;
    --local-dir)    LOCAL_DEST="$2"; shift 2 ;;
    --textfile-dir) TEXTFILE_DIR="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

FILE=""
trap 'rc=$?; [ -n "$FILE" ] && rm -f "$FILE.partial"; echo "$(date -u +%FT%TZ) backup FAILED (exit $rc, line $LINENO)" >&2; exit $rc' ERR

echo "$(date -u +%FT%TZ) backup start (container $CONTAINER)"

if [ -z "$LOCAL_DEST" ]; then
  command -v rclone >/dev/null || { echo "rclone not installed (apt-get install -y rclone)" >&2; exit 1; }
  [ -f "$ENV_FILE" ] || { echo "missing $ENV_FILE (OPS-RUNBOOK script D)" >&2; exit 1; }
  [ "$(stat -c %a "$ENV_FILE")" = 600 ] || { echo "$ENV_FILE must be mode 600" >&2; exit 1; }
  set -a; . "$ENV_FILE"; set +a
  : "${BACKUP_BUCKET:?BACKUP_BUCKET not set in $ENV_FILE}"
  : "${RCLONE_CONFIG_SPACES_ACCESS_KEY_ID:?not set in $ENV_FILE}"
  : "${RCLONE_CONFIG_SPACES_SECRET_ACCESS_KEY:?not set in $ENV_FILE}"
  : "${RCLONE_CONFIG_SPACES_ENDPOINT:?not set in $ENV_FILE}"
  REMOTE="spaces:$BACKUP_BUCKET/postgres"
fi

# DB name and role come from the container's own env — prod maple_key_db,
# local dev maple_key_dev; nothing hardcoded.
PGUSER=$(docker exec "$CONTAINER" printenv POSTGRES_USER)
PGDB=$(docker exec "$CONTAINER" printenv POSTGRES_DB)

mkdir -p "$BACKUP_DIR"
FILE="$BACKUP_DIR/nightly-$(date -u +%Y%m%d-%H%M%S).sql.gz"
docker exec "$CONTAINER" pg_dump -U "$PGUSER" "$PGDB" | gzip > "$FILE.partial"
[ -s "$FILE.partial" ] || { echo "dump is empty" >&2; false; }
gzip -t "$FILE.partial"
mv "$FILE.partial" "$FILE"
echo "dump ok: $FILE ($(du -h "$FILE" | cut -f1))"

if [ -n "$LOCAL_DEST" ]; then
  mkdir -p "$LOCAL_DEST"
  cp "$FILE" "$LOCAL_DEST/"
  find "$LOCAL_DEST" -name 'nightly-*.sql.gz' -mtime +"$RETENTION_DAYS" -print -delete
  echo "dry run: copied to $LOCAL_DEST"
else
  # copyto verifies size + hash after the upload; a mismatch is an error.
  rclone copyto "$FILE" "$REMOTE/$(basename "$FILE")"
  rclone delete "$REMOTE" --min-age "${RETENTION_DAYS}d" --include 'nightly-*.sql.gz' -v
  echo "uploaded: $REMOTE/$(basename "$FILE")"
fi

# Local copies are a convenience for a fast restore; the bucket is the backup.
# pre-deploy-*.sql.gz (10-preflight.sh) is never touched here.
find "$BACKUP_DIR" -name 'nightly-*.sql.gz' -mtime +"$LOCAL_KEEP_DAYS" -delete

# Success marker for node-exporter's textfile collector — atomic rename so a
# scrape never reads a half-written file.
mkdir -p "$TEXTFILE_DIR"
cat > "$TEXTFILE_DIR/backup.prom.tmp" <<EOF
# HELP backup_last_success_timestamp Unix time of the last nightly Postgres backup that reached off-box storage.
# TYPE backup_last_success_timestamp gauge
backup_last_success_timestamp $(date -u +%s)
EOF
mv "$TEXTFILE_DIR/backup.prom.tmp" "$TEXTFILE_DIR/backup.prom"
echo "$(date -u +%FT%TZ) backup ok"
