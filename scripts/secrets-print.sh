#!/usr/bin/env bash
# Print every prod secret, grouped by 1Password item, so they can be entered
# into the MapleKey vault one by one. ONE-TIME migration helper.
#
#   bash scripts/secrets-print.sh        # prints to the terminal
#   clear                                 # afterwards. Terminal is the only copy.
#
# Reads: the running containers on the droplet (the materialised copy of the
# GitHub Actions secrets, which are write-only) and ~/.config/maplekey on
# this Mac. Never writes anything.
set -euo pipefail
DROPLET=root@159.203.173.226

section() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

section "From droplet: maple-key-backend container env"
ssh "$DROPLET" 'docker inspect -f "{{range .Config.Env}}{{println .}}{{end}}" maple-key-backend' \
  | grep -E '^(SECRET_KEY|DJANGO_SECRET_KEY|POSTGRES_(DB|USER|PASSWORD)|DATABASE_URL|GOOGLE_CLIENT_(ID|SECRET)|HELCIM_(API_TOKEN|WEBHOOK_SECRET|TERMINAL_ID|SUBDOMAIN)|RESEND_API_KEY|DEFAULT_FROM_EMAIL|ALLOWED_HOSTS|CORS_ALLOWED_ORIGINS|FRONTEND_URL)=' \
  | sort

section "From droplet: postgres container env"
ssh "$DROPLET" 'docker inspect -f "{{range .Config.Env}}{{println .}}{{end}}" postgres' \
  | grep -E '^POSTGRES_' | sort

section "From droplet: grafana container env (admin pw is first-boot only; reset it, do not trust this)"
ssh "$DROPLET" 'docker inspect -f "{{range .Config.Env}}{{println .}}{{end}}" maple_key_grafana' \
  | grep -E '^(GF_SECURITY_ADMIN_PASSWORD|GF_SMTP_PASSWORD|GF_SMTP_ENABLED|MAPLEKEY_ENV)=' | sort

section "From this Mac: ~/.config/maplekey/helcim-prod.env"
cat ~/.config/maplekey/helcim-prod.env 2>/dev/null || echo "(file not found)"

section "From this Mac: SSH keys (the private key that GitHub holds as VPC_SSH_KEY / VPS_SSH_KEY)"
ls -la ~/.ssh/ | grep -vE 'known_hosts|\.pub$|^total|^d'
echo "Identify the droplet key with:  ssh -v $DROPLET exit 2>&1 | grep 'Offering public key'"
echo "Then store the PRIVATE key file contents as a Document/SSH Key item."

section "Not printable, fetch from the provider"
cat <<'TXT'
Docker Hub access token   -> hub.docker.com -> Account -> Security (GitHub: DOCKER_USERNAME / DOCKER_PASSWORD)
Grafana admin password    -> reset: ssh root@159.203.173.226 'docker exec maple_key_grafana grafana cli admin reset-admin-password NEW'
DigitalOcean root/console -> DigitalOcean dashboard
Certbot email             -> plain, GitHub CERTBOT_EMAIL
TXT
printf '\nDone. Run:  clear\n'
