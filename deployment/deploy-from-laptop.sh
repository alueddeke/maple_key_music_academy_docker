#!/usr/bin/env bash
# The laptop entry point (MAP-191): a full backend deploy with GitHub Actions
# out of the picture. Same scripts, same order, same container state as the
# Actions path — only the source of the environment differs (1Password +
# prod.config.env here; GitHub secrets there).
#
#   bash deployment/deploy-from-laptop.sh              # 00–03 on the laptop, then 10–15 on the droplet
#   bash deployment/deploy-from-laptop.sh --skip-build # droplet stages only (image already on Docker Hub)
#
# Needs: `op` signed in (op signin), docker + buildx, ssh access to the
# droplet with the deploy key, deployment/prod.config.env filled in (copy
# prod.config.env.example; the non-secret values live only in GitHub secrets
# until MAP-190 publishes the table).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DROPLET="${DROPLET:-root@159.203.173.226}"
VAULT="Private"
CONFIG="$HERE/prod.config.env"
[ -f "$CONFIG" ] || { echo "❌ $CONFIG missing — copy prod.config.env.example and fill it in"; exit 1; }

# Secrets: same 1Password items secrets-sync.sh pushes to GitHub. A failed
# `op read` aborts (never deploy with an empty secret).
read_secret() { # VAR "Item/field"
  local value
  value="$(op read "op://$VAULT/$2")" || { echo "❌ op read failed for $1 (op signin?)"; exit 1; }
  export "$1=$value"
}
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
# Plain config (not secrets): prod.config.env
set -a
# shellcheck disable=SC1090
. "$CONFIG"
set +a

if [ "${1:-}" != "--skip-build" ]; then
  for stage in "$HERE"/0[0-9]-*.sh; do
    echo; echo "▶ $(basename "$stage")"; bash "$stage"
  done
fi

ENV_FILE="$(mktemp)"
trap 'rm -f "$ENV_FILE"' EXIT
bash "$HERE/write-deploy-env.sh" "$ENV_FILE"

echo "▶ copying deployment/ to $DROPLET"
ssh "$DROPLET" 'mkdir -p ~/deployment'
scp -q "$HERE"/*.sh "$DROPLET":~/deployment/
scp -q "$ENV_FILE" "$DROPLET":~/deployment/deploy.env

echo "▶ running droplet stages"
ssh "$DROPLET" 'bash ~/deployment/run.sh'

echo
echo "Tag the deploy in the backend repo (Actions does this automatically):"
echo "  git -C ../maple_key_music_academy_backend tag deploy-$(date -u +%Y-%m-%d-%H%M) && git push origin --tags"
