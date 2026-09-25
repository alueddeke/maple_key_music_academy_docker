#!/usr/bin/env bash
# shellcheck disable=SC2034  # IMAGE / BACKEND_ENV are consumed by the sourcing stage
# Shared by the droplet stages (10–15). Sourced, never executed.
#
# Every stage runs with the deploy environment already exported (run.sh
# sources deploy.env). Nothing here reads GitHub — the same file drives the
# Actions path and the laptop path (MAP-191).

# The variables every stage needs. Missing one = abort before touching anything.
DEPLOY_REQUIRED_VARS=(
  DOCKER_USERNAME DOCKER_PASSWORD
  POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB
  DJANGO_SECRET_KEY ALLOWED_HOSTS
  GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET
  CORS_ALLOWED_ORIGINS PLATFORM_ADMIN_EMAILS FRONTEND_URL
  RESEND_API_KEY DEFAULT_FROM_EMAIL
  HELCIM_API_TOKEN HELCIM_TERMINAL_ID HELCIM_WEBHOOK_SECRET HELCIM_SUBDOMAIN
  CERTBOT_EMAIL
)

require_deploy_env() {
  local missing=()
  for v in "${DEPLOY_REQUIRED_VARS[@]}"; do
    [ -n "${!v:-}" ] || missing+=("$v")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    echo "❌ deploy env incomplete — missing: ${missing[*]}"
    exit 1
  fi
}

# Image to deploy. IMAGE_TAG defaults to latest (what every deploy has shipped so far).
IMAGE="${DOCKER_USERNAME:-}/maple-key-backend:${IMAGE_TAG:-latest}"
DATABASE_URL="postgresql://${POSTGRES_USER:-}:${POSTGRES_PASSWORD:-}@postgres:5432/${POSTGRES_DB:-}"

# The backend container environment — one definition instead of the seven
# hand-copied `-e` blocks the inline workflow carried (the drift that MAP-218's
# env lines exposed). Every backend-image container gets the same set;
# ANALYTICS_EXCLUDE_TEST_DATA / TEST_ACCOUNT_EMAILS are harmless on the
# throwaway migrate/collectstatic runs (they only affect analytics reads).
BACKEND_ENV=(
  -e "DATABASE_URL=${DATABASE_URL:-}"
  -e "SECRET_KEY=${DJANGO_SECRET_KEY:-}"
  -e "DEBUG=False"
  -e "MAPLEKEY_ENV=prod"
  -e "ALLOWED_HOSTS=${ALLOWED_HOSTS:-}"
  -e "GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID:-}"
  -e "GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET:-}"
  -e "CORS_ALLOWED_ORIGINS=${CORS_ALLOWED_ORIGINS:-}"
  -e "PLATFORM_ADMIN_EMAILS=${PLATFORM_ADMIN_EMAILS:-}"
  -e "FRONTEND_URL=${FRONTEND_URL:-}"
  -e "RESEND_API_KEY=${RESEND_API_KEY:-}"
  -e "DEFAULT_FROM_EMAIL=${DEFAULT_FROM_EMAIL:-}"
  -e "HELCIM_API_TOKEN=${HELCIM_API_TOKEN:-}"
  -e "HELCIM_TERMINAL_ID=${HELCIM_TERMINAL_ID:-}"
  -e "HELCIM_WEBHOOK_SECRET=${HELCIM_WEBHOOK_SECRET:-}"
  -e "HELCIM_SUBDOMAIN=${HELCIM_SUBDOMAIN:-}"
  -e "ANALYTICS_EXCLUDE_TEST_DATA=True"
  -e "TEST_ACCOUNT_EMAILS=a.lueddeke@hotmail.com"
)

banner() {
  echo "========================================="
  echo "$1"
  echo "========================================="
}
