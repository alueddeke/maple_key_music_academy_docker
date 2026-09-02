#!/usr/bin/env bash
# Rotate the PROD Postgres password. Runs on the Mac, drives the droplet.
# Backend + worker are unavailable for ~20-30s (they hold the old password in
# DATABASE_URL and must be recreated; env is immutable on a running container).
#
#   bash scripts/rotate-postgres-password.sh                 # new value from 1Password item "Postgres prod"
#   bash scripts/rotate-postgres-password.sh 'NEWPASSWORD'   # or pass it explicitly
#
# Order: 1) GitHub secret (inert until the next deploy, but the deploy's backup
# and migrate steps need it to match the DB)  2) ALTER USER on the DB
# 3) recreate backend + worker with the new DATABASE_URL, mirroring deploy.yml
# 4) verify. Rollback if step 3 fails: ALTER USER back to the previous value
# (1Password keeps it in the item's history), then re-run.
set -euo pipefail
DROPLET=root@159.203.173.226
REPO=alueddeke/maple_key_music_academy_backend

NEW="${1:-$(op read 'op://Private/Postgres Prod Password/password')}"
# Alphanumeric only: the value is embedded in a URL and in a shell string.
[[ "$NEW" =~ ^[A-Za-z0-9]{24,}$ ]] || { echo "password must be alphanumeric, 24+ chars"; exit 1; }

echo "1/3 GitHub secret POSTGRES_PASSWORD"
printf '%s' "$NEW" | gh secret set POSTGRES_PASSWORD -R "$REPO"

echo "2/3 + 3/3 droplet: ALTER USER, recreate backend + worker, verify"
ssh "$DROPLET" "NEW_PW='$NEW' bash -s" <<'REMOTE'
set -euo pipefail
envof() { docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$1" | sed -n "s/^$2=//p"; }
PGUSER=$(envof postgres POSTGRES_USER); PGDB=$(envof postgres POSTGRES_DB)
IMAGE=$(docker inspect -f '{{.Config.Image}}' maple-key-backend)
NEW_URL="postgresql://$PGUSER:$NEW_PW@postgres:5432/$PGDB"

# Build the new env files BEFORE touching anything, so a failure here costs nothing.
umask 077; TMP=$(mktemp -d)
for c in maple-key-backend maple-key-worker; do
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$c" \
    | sed "s#^DATABASE_URL=.*#DATABASE_URL=$NEW_URL#" > "$TMP/$c.env"
  grep -q "^DATABASE_URL=$NEW_URL\$" "$TMP/$c.env" || { echo "no DATABASE_URL in $c env"; exit 1; }
done

# DB password. Local socket inside the container is trust-auth, so no old password needed.
docker exec postgres psql -U "$PGUSER" -d "$PGDB" -v ON_ERROR_STOP=1 \
  -c "ALTER USER \"$PGUSER\" PASSWORD '$NEW_PW';"
echo "db: password changed"

# Backend: same flags as deploy.yml, env cloned from the old container.
docker stop maple-key-backend >/dev/null && docker rm maple-key-backend >/dev/null
docker run -d --name maple-key-backend --restart unless-stopped \
  --health-cmd "python3 /app/healthcheck.py" --health-interval 30s --health-timeout 10s --health-retries 3 \
  --network maple-key-network -p 127.0.0.1:8001:8000 \
  --env-file "$TMP/maple-key-backend.env" \
  -v /var/log/maple-key:/var/log/maple-key -v static_volume:/app/staticfiles \
  "$IMAGE" >/dev/null

# Worker: same flags as deploy.yml.
docker stop maple-key-worker >/dev/null && docker rm maple-key-worker >/dev/null
docker run -d --name maple-key-worker --restart unless-stopped --network maple-key-network \
  --env-file "$TMP/maple-key-worker.env" -v /var/log/maple-key:/var/log/maple-key \
  "$IMAGE" python3 manage.py process_invoice_send_runs >/dev/null
rm -rf "$TMP"

# Verify: gunicorn answers, Django can open a DB connection with the new password, worker alive.
code=000
for i in 1 2 3 4 5 6; do sleep 5; code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8001/api/auth/user/ || true); [ "$code" = 401 ] && break; done
echo "backend http=$code (want 401)"
docker exec maple-key-backend python3 manage.py shell -c "from django.db import connection; connection.ensure_connection(); print('backend db connection: ok')"
docker exec maple-key-worker python3 manage.py shell -c "from django.db import connection; connection.ensure_connection(); print('worker db connection: ok')"
docker inspect -f 'worker running={{.State.Running}}' maple-key-worker
REMOTE
echo "Done. Update rotated_on on the 1Password item."
