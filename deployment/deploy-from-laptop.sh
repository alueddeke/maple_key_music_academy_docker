#!/usr/bin/env bash
# The laptop entry point (MAP-191): a full backend deploy with GitHub Actions
# out of the picture. Same scripts, same order, same container state as the
# Actions path — only the source of the environment differs (1Password here;
# GitHub secrets there, which secrets-sync.sh fills from the same 1Password
# items).
#
#   bash deployment/deploy-from-laptop.sh              # 00–03 on the laptop, then 10–15 on the droplet
#   bash deployment/deploy-from-laptop.sh --skip-build # droplet stages only (image already on Docker Hub)
#
# Needs: `op` signed in (op signin), docker + buildx, ssh access to the
# droplet with the deploy key. Nothing is written to the laptop's disk: the
# environment is streamed over ssh stdin into ~/deployment/deploy.env (0600)
# on the droplet, which run.sh deletes on exit.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DROPLET="${DROPLET:-root@159.203.173.226}"
VAULT="Private"

# Every value comes from 1Password — the same items secrets-sync.sh pushes to
# GitHub. A failed `op read` aborts (never deploy with an empty value).
read_secret() { # VAR "Item/field"
  local value
  value="$(op read "op://$VAULT/$2")" || { echo "❌ op read failed for $1 (op signin?)"; exit 1; }
  export "$1=$value"
}
# Secrets
read_secret DOCKER_USERNAME       "Docker Hub Token/username"
read_secret DOCKER_PASSWORD       "Docker Hub Token/credential"
read_secret POSTGRES_PASSWORD     "Postgres Prod Password/password"
read_secret DJANGO_SECRET_KEY     "Django Prod Secret Key/credential"
read_secret GOOGLE_CLIENT_ID      "Google Prod Client ID/credential"
read_secret GOOGLE_CLIENT_SECRET  "Google Prod Client Secret/credential"
read_secret RESEND_API_KEY        "Resend Prod API Key/credential"
read_secret HELCIM_API_TOKEN      "Helcim Prod Token/credential"
read_secret HELCIM_TERMINAL_ID    "Helcim Prod Terminal ID/credential"
read_secret HELCIM_WEBHOOK_SECRET "Helcim Prod Webhook Secret/credential"
# Plain production config (not secret, but one source of truth: the
# "MapleKey Prod Config" secure note, one field per variable)
read_secret POSTGRES_USER         "MapleKey Prod Config/POSTGRES_USER"
read_secret POSTGRES_DB           "MapleKey Prod Config/POSTGRES_DB"
read_secret ALLOWED_HOSTS         "MapleKey Prod Config/ALLOWED_HOSTS"
read_secret CORS_ALLOWED_ORIGINS  "MapleKey Prod Config/CORS_ALLOWED_ORIGINS"
read_secret PLATFORM_ADMIN_EMAILS "MapleKey Prod Config/PLATFORM_ADMIN_EMAILS"
read_secret FRONTEND_URL          "MapleKey Prod Config/FRONTEND_URL"
read_secret DEFAULT_FROM_EMAIL    "MapleKey Prod Config/DEFAULT_FROM_EMAIL"
read_secret HELCIM_SUBDOMAIN      "MapleKey Prod Config/HELCIM_SUBDOMAIN"
read_secret CERTBOT_EMAIL         "MapleKey Prod Config/CERTBOT_EMAIL"
# Optional: IMAGE_TAG=<sha> in the environment deploys that tag instead of :latest.

if [ "${1:-}" != "--skip-build" ]; then
  for stage in "$HERE"/0[0-9]-*.sh; do
    echo; echo "▶ $(basename "$stage")"; bash "$stage"
  done
fi

echo "▶ copying deployment/ to $DROPLET"
ssh "$DROPLET" 'mkdir -p ~/deployment'
scp -q "$HERE"/*.sh "$DROPLET":~/deployment/

echo "▶ writing deploy.env on the droplet (streamed, never on this disk)"
bash "$HERE/write-deploy-env.sh" - | ssh "$DROPLET" 'umask 077; cat > ~/deployment/deploy.env'

echo "▶ running droplet stages"
ssh "$DROPLET" 'bash ~/deployment/run.sh'

echo
echo "Tag the deploy in the backend repo (Actions does this automatically):"
echo "  git -C ../maple_key_music_academy_backend tag deploy-$(date -u +%Y-%m-%d-%H%M) && git push origin --tags"
