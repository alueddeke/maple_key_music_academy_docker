#!/usr/bin/env bash
# Writes deploy.env from the current process environment, single-quoting
# every value so any character survives (the MAP-212 lesson: the inline
# workflow once let bash strip `$…` out of a token). Used by both entry
# points: the Actions workflow exports the secrets into its step env and
# calls this; deploy-from-laptop.sh exports them from 1Password and calls
# this. Never prints a value.
#
#   write-deploy-env.sh <output-path>
set -euo pipefail
OUT="${1:?usage: write-deploy-env.sh <output-path>}"
. "$(dirname "$0")/_lib.sh"

umask 077
: > "$OUT"
for v in "${DEPLOY_REQUIRED_VARS[@]}" IMAGE_TAG; do
  value="${!v:-}"
  [ -n "$value" ] || continue
  printf "%s='%s'\n" "$v" "${value//\'/\'\\\'\'}" >> "$OUT"
done
require_deploy_env
echo "deploy.env written: $(wc -l < "$OUT") variables"
