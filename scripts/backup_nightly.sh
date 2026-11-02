#!/usr/bin/env bash
# Nightly off-box Postgres backup (MAP-140). Runs on the backend droplet from
# root's crontab:
#
#   30 6 * * * /opt/maple_key_music_academy_docker/scripts/backup_nightly.sh >> /var/log/maplekey-backup.log 2>&1
#
# pg_dump (same form as deployment/10-preflight.sh) → gzip → verify → encrypt
# with age to a public recipient → upload to the Backblaze B2 bucket via rclone
# → write the node-exporter textfile metric backup_last_success_timestamp.
# Any failure exits non-zero and leaves the metric untouched, so the Grafana
# rule "Nightly backup stale" (alerts.yaml, uid backup-stale) fires once the
# last success is older than 26 h. The pre-deploy backup in 10-preflight.sh is
# separate and unchanged.
#
# Retention is the bucket's job, not this script's: Object Lock (compliance,
# 30 days) blocks deletion, and the lifecycle rule on postgres/ hides objects
# at 30 days and deletes them 1 day later. The droplet key has no deleteFiles
# capability, so nothing on this box can remove an off-box copy.
#
# Encryption: the droplet holds only the age public recipient, so it can
# encrypt but never decrypt. The identity lives in 1Password
# "Maple Key Backup age Identity" and is supplied to restore_drill.sh on stdin.
#
# Credentials: /root/.config/maplekey/backup.env (mode 600, droplet only,
# written from 1Password "Maple Key Backup B2 Key" by OPS-RUNBOOK script D).
# It exports BACKUP_BUCKET, BACKUP_AGE_RECIPIENT and RCLONE_CONFIG_OFFSITE_*
# (rclone's env-configured remote "offsite:"); nothing secret is passed on a
# command line.
#
#   scripts/backup_nightly.sh                                  # prod: container "postgres"
#   BACKUP_AGE_RECIPIENT=age1… BACKUP_DIR=/tmp/w scripts/backup_nightly.sh \
#       --container maple_key_db --local-dir /tmp/bucket       # dry run: local dir stands in for the bucket, no metric
#   … --local-dir /tmp/bucket --textfile-dir /tmp/tf           # dry run that also writes the metric, to /tmp/tf only
set -euo pipefail

CONTAINER=postgres
LOCAL_DEST=""
TEXTFILE_DIR=/var/lib/node_exporter/textfile_collector
TEXTFILE_EXPLICIT=""
ENV_FILE=/root/.config/maplekey/backup.env
BACKUP_DIR="${BACKUP_DIR:-$HOME/maplekey-backups}"
LOCAL_KEEP_DAYS=3

while [ $# -gt 0 ]; do
  case "$1" in
    --container)    CONTAINER="$2"; shift 2 ;;
    --local-dir)    LOCAL_DEST="$2"; shift 2 ;;
    --textfile-dir) TEXTFILE_DIR="$2"; TEXTFILE_EXPLICIT=1; shift 2 ;;
    --env-file)     ENV_FILE="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

file_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

FILE=""
ENC=""
# shellcheck disable=SC2154  # rc is assigned inside the trap string
trap 'rc=$?; [ -n "$FILE" ] && rm -f "$FILE.partial"; [ -n "$ENC" ] && rm -f "$ENC" "$ENC.partial"; echo "$(date -u +%FT%TZ) backup FAILED (exit $rc, line $LINENO)" >&2; exit $rc' ERR

echo "$(date -u +%FT%TZ) backup start (container $CONTAINER)"

command -v age >/dev/null || { echo "age not installed (apt-get install -y age)" >&2; exit 1; }
if [ -z "$LOCAL_DEST" ]; then
  command -v rclone >/dev/null || { echo "rclone not installed (official .deb from downloads.rclone.org — Ubuntu apt rclone 1.60 is rejected by B2; OPS-RUNBOOK script D)" >&2; exit 1; }
  [ -f "$ENV_FILE" ] || { echo "missing $ENV_FILE (OPS-RUNBOOK script D)" >&2; exit 1; }
  [ "$(file_mode "$ENV_FILE")" = 600 ] || { echo "$ENV_FILE must be mode 600" >&2; exit 1; }
  set -a
  # droplet-only file, path chosen at runtime
  # shellcheck source=/dev/null
  . "$ENV_FILE"
  set +a
  : "${BACKUP_BUCKET:?BACKUP_BUCKET not set in $ENV_FILE}"
  : "${RCLONE_CONFIG_OFFSITE_TYPE:?not set in $ENV_FILE}"
  : "${RCLONE_CONFIG_OFFSITE_ACCOUNT:?not set in $ENV_FILE}"
  : "${RCLONE_CONFIG_OFFSITE_KEY:?not set in $ENV_FILE}"
  REMOTE="offsite:$BACKUP_BUCKET/postgres"
fi
: "${BACKUP_AGE_RECIPIENT:?BACKUP_AGE_RECIPIENT not set (backup.env, or the environment for a dry run)}"
case "$BACKUP_AGE_RECIPIENT" in
  age1*) ;;
  *) echo "BACKUP_AGE_RECIPIENT is not an age public key (age1…)" >&2; exit 1 ;;
esac

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

# Only the encrypted file leaves the box. The plaintext local copy is the same
# exposure as the live database on this droplet.
ENC="$FILE.age"
age -r "$BACKUP_AGE_RECIPIENT" -o "$ENC.partial" "$FILE"
[ "$(head -c 21 "$ENC.partial")" = "age-encryption.org/v1" ] || { echo "encrypted file has no age header" >&2; false; }
mv "$ENC.partial" "$ENC"

if [ -n "$LOCAL_DEST" ]; then
  mkdir -p "$LOCAL_DEST"
  cp "$ENC" "$LOCAL_DEST/"
  echo "dry run: copied to $LOCAL_DEST/$(basename "$ENC")"
else
  # copyto verifies size + hash after the upload; a mismatch is an error.
  # Upload only: the bucket's lock + lifecycle rule handle retention.
  rclone copyto "$ENC" "$REMOTE/$(basename "$ENC")"
  echo "uploaded: $REMOTE/$(basename "$ENC")"
fi
rm -f "$ENC"
ENC=""

# Local plaintext copies are a convenience for a fast restore; the bucket is
# the backup. pre-deploy-*.sql.gz (10-preflight.sh) is never touched here.
find "$BACKUP_DIR" -name 'nightly-*.sql.gz*' -mtime +"$LOCAL_KEEP_DAYS" -delete

# A dry run never touches the real textfile directory: nothing went off-box,
# so writing the metric there would silence backup-stale (W0-M1).
if [ -n "$LOCAL_DEST" ] && [ -z "$TEXTFILE_EXPLICIT" ]; then
  echo "dry run: metric not written (pass --textfile-dir to write it somewhere else)"
else
  # Success marker for node-exporter's textfile collector — atomic rename so
  # a scrape never reads a half-written file.
  mkdir -p "$TEXTFILE_DIR"
  cat > "$TEXTFILE_DIR/backup.prom.tmp" <<EOF
# HELP backup_last_success_timestamp Unix time of the last nightly Postgres backup that reached off-box storage.
# TYPE backup_last_success_timestamp gauge
backup_last_success_timestamp $(date -u +%s)
EOF
  mv "$TEXTFILE_DIR/backup.prom.tmp" "$TEXTFILE_DIR/backup.prom"
fi
echo "$(date -u +%FT%TZ) backup ok"
