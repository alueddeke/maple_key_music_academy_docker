# deployment/ — the backend deploy, as numbered scripts (MAP-191)

One deploy, two entry points, same scripts:

| Entry point | Runs 00–03 (laptop) | Runs 10–15 (droplet) | Environment source |
|---|---|---|---|
| GitHub Actions `Deploy Backend Prod` (backend repo `.github/workflows/deploy.yml`) | as its own `test` + `build_and_push` jobs | `scp deployment/*.sh`, `write-deploy-env.sh -` streamed over ssh stdin, `ssh 'bash ~/deployment/run.sh'` | GitHub Actions secrets (step `env:`) → `write-deploy-env.sh -` |
| `bash deployment/deploy-from-laptop.sh` (Actions down or disabled) | yes (`--skip-build` to skip) | same | 1Password (`op read`, secrets + the "MapleKey Prod Config" note) → `write-deploy-env.sh -` streamed over ssh |

Numbering is the ordering contract. Each droplet stage owns its own gate and rollback — nothing here was rebuilt, only extracted from the inline workflow (backup-first, live-DB migration gate, `OLD_IMAGE` health-check rollback were earned by incidents 2026-05-10 / 2026-06-24).

```
00-tests.sh          pytest in the dev api container (postgres:15)
01-lint.sh           scripts/check-no-fallbacks.sh (MAP-181)
02-build.sh          buildx linux/amd64, tags :latest and :<sha>
03-push.sh           Docker Hub
--- droplet ---
10-preflight.sh      docker login, volumes/network, pull, postgres up, pg_isready, backup (empty-file abort)
11-migration-gate.sh migrate + migrate --check against the live DB, before any container moves
12-swap-backend.sh   OLD_IMAGE, collectstatic, swap, 30 s health poll, rollback to OLD_IMAGE
13-swap-worker.sh    send-run worker + scheduler (no rollback — backend already healthy)
14-swap-nginx.sh     container nginx, host nginx, certbot, ufw (idempotent)
15-verify.sh         prune, container check, public API check, running image digests
run.sh               sources deploy.env (then deletes it), runs 10–15 in order
_lib.sh              required vars, IMAGE, the single BACKEND_ENV array
write-deploy-env.sh  process env → deploy.env (file, or `-` for stdout), every value `printf %q`-quoted
```

`deploy.env` never lives in git and is removed by `run.sh` on exit. Neither entry point writes it locally (the Actions runner's 0600 file could not be read by the scp-action container — first run 2026-09-26): `write-deploy-env.sh -` streams it over ssh stdin into `~/deployment/deploy.env` (0600). All 19 values, secrets and plain config alike, come from the 1Password vault `Private`; `scripts/secrets-sync.sh` pushes the same items to GitHub, so both paths read one source.
