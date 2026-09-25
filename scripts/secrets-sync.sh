#!/usr/bin/env bash
# Push secrets + plain prod config from the 1Password vault "Private" to GitHub Actions secrets.
# Values travel op -> gh in a pipe and are never echoed.
#
#   bash scripts/secrets-sync.sh --check   # show mapping + which items exist, change nothing
#   bash scripts/secrets-sync.sh           # set every mapped secret on both repos
#
# Rotation = change the value in 1Password, run this, redeploy.
# Needs: `op` signed in (op signin), `gh` authed with repo scope.
set -euo pipefail
VAULT="Private"
BACKEND=alueddeke/maple_key_music_academy_backend
FRONTEND=alueddeke/maple-key-music-academy-frontend

# GitHub secret name | repo(s) | op reference (Item/field)
# Item titles are the 1Password titles exactly. Field names are 1Password's
# defaults per category: API Credential -> "credential", Password ->
# "password", SSH Key -> "private key". Add fields by those names if you
# created an item under a different category.
MAP=(
  "GOOGLE_CLIENT_ID       backend           Google Prod Client ID/credential"
  "VITE_GOOGLE_CLIENT_ID  frontend          Google Prod Client ID/credential"
  "GOOGLE_CLIENT_SECRET   backend           Google Prod Client Secret/credential"
  "RESEND_API_KEY         backend           Resend Prod API Key/credential"
  "HELCIM_API_TOKEN       backend           Helcim Prod Token/credential"
  "HELCIM_WEBHOOK_SECRET  backend           Helcim Prod Webhook Secret/credential"
  "HELCIM_TERMINAL_ID     backend           Helcim Prod Terminal ID/credential"
  "POSTGRES_PASSWORD      backend           Postgres Prod Password/password"
  "DJANGO_SECRET_KEY      backend           Django Prod Secret Key/credential"
  "DOCKER_USERNAME        backend,frontend  Docker Hub Token/username"
  "DOCKER_PASSWORD        backend,frontend  Docker Hub Token/credential"
  "VPC_SSH_KEY            backend           Droplet Deploy SSH Key/private key"
  "VPS_SSH_KEY            frontend          Droplet Deploy SSH Key/private key"
  # Plain production config (not secret) — one secure note, one field per variable,
  # so the laptop deploy path (deployment/deploy-from-laptop.sh) and GitHub read the
  # same values (MAP-191).
  "POSTGRES_USER          backend           MapleKey Prod Config/POSTGRES_USER"
  "POSTGRES_DB            backend           MapleKey Prod Config/POSTGRES_DB"
  "ALLOWED_HOSTS          backend           MapleKey Prod Config/ALLOWED_HOSTS"
  "CORS_ALLOWED_ORIGINS   backend           MapleKey Prod Config/CORS_ALLOWED_ORIGINS"
  "PLATFORM_ADMIN_EMAILS  backend           MapleKey Prod Config/PLATFORM_ADMIN_EMAILS"
  "FRONTEND_URL           backend           MapleKey Prod Config/FRONTEND_URL"
  "DEFAULT_FROM_EMAIL     backend           MapleKey Prod Config/DEFAULT_FROM_EMAIL"
  "HELCIM_SUBDOMAIN       backend           MapleKey Prod Config/HELCIM_SUBDOMAIN"
  "CERTBOT_EMAIL          backend           MapleKey Prod Config/CERTBOT_EMAIL"
)
# Not synced on purpose: VPC_HOST/_PORT/_USERNAME (droplet address, set once by hand).
# Grafana admin password (item "Maple Key Prod Grafana") is read by script B
# in OPS-RUNBOOK.md, not by GitHub.

check_only=false; [[ "${1:-}" == "--check" ]] && check_only=true
ok=0; missing=0
for row in "${MAP[@]}"; do
  name=$(awk '{print $1}' <<<"$row"); repos=$(awk '{print $2}' <<<"$row")
  ref=$(sed -E 's/^[^ ]+ +[^ ]+ +//' <<<"$row")
  if ! op read "op://$VAULT/$ref" >/dev/null 2>&1; then
    printf '  MISSING  %-22s <- op://%s/%s\n' "$name" "$VAULT" "$ref"; missing=$((missing+1)); continue
  fi
  printf '  ok       %-22s <- op://%s/%s  (%s)\n' "$name" "$VAULT" "$ref" "$repos"; ok=$((ok+1))
  $check_only && continue
  for r in ${repos//,/ }; do
    repo=$BACKEND; [[ $r == frontend ]] && repo=$FRONTEND
    op read "op://$VAULT/$ref" | gh secret set "$name" -R "$repo"
  done
done
printf '\n%d mapped, %d missing in 1Password.\n' "$ok" "$missing"
$check_only || echo "Pushed. Redeploy (merge develop -> production) so containers pick up the new values."
