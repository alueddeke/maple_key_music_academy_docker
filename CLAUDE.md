# Docker CLAUDE.md

Detailed reference for deployment, infrastructure, and Docker configuration. Read this before deploying, modifying CI/CD, or responding to production incidents.

---

## Production Server

| Detail | Value |
|---|---|
| IP | 159.203.173.226 |
| SSH | `ssh root@159.203.173.226` |
| Platform | Digital Ocean Ubuntu 25.04, NYC3 |
| Frontend | https://maplekeymusic.com |
| Backend API | https://api.maplekeymusic.com |

**Docker containers:**
- `maple-key-backend` — Django API (Gunicorn)
- `maple-key-worker` — invoice send-run worker (same image)
- `maple-key-scheduler` — webhook retry + Helcim sync ticks (same image, MAP-154)
- `postgres` — PostgreSQL 15
- `nginx` — reverse proxy

**Database:** user `maple_key_user`, database `maple_key_db`, password in production `.env`.

**Dev Postgres = prod major version (15)** since MAP-190 (`docker-compose.yaml` `db` was `postgres:14`). A data directory written by 14 does not start under 15, so the first `docker compose up` after pulling this needs a one-time reset:
`docker compose down -v` (deletes the local dev database) → `docker compose up -d` → `/seed-billing-test`.
Nothing on production changes.

---

## Pre-Deployment Checklist — MANDATORY

1. [ ] All migrations tested locally (no duplicate numbers)
2. [ ] Production database backup created (see below)
3. [ ] Frontend production build passes: `docker compose exec frontend pnpm run build`
4. [ ] All `@radix-ui/*` dependencies in `package.json` AND installed (see frontend CLAUDE.md)
5. [ ] Changes committed to git
6. [ ] Any new/changed secret is in 1Password (vault `Private`) and pushed with `scripts/secrets-sync.sh` — see `.planning/SECRETS-INVENTORY.md` (playbook + `/rotate-secret`)
7. [ ] Any change to `deployment/*.sh` is merged to this repo's `develop` — the backend workflow checks the scripts out from there at deploy time (MAP-191)

---

## Branch Model

develop → production (two branches only — main branch has been deleted)
All development work goes to develop. Deploy by a pull request `develop → production`; the owner's merge of that PR is the deploy trigger.

**Hotfix rule — NO EXCEPTIONS:** Even urgent production fixes go to develop first, then the same `develop → production` PR. Never commit directly to production. Direct production commits caused branch drift and a broken prod incident (2026-05-10). The CI pipeline is the safety net — bypassing develop bypasses the process, not just a convention.

**A direct push to `production` is impossible** (MAP-187): branch protection plus the "Production" repository ruleset require a PR with green required checks and block non-fast-forward pushes and branch deletion. See § Production Gate below.

## Deployment Procedure

Backend and frontend use the same five steps. The production approval gate in the root `.claude/CLAUDE.md` applies before step 4: the owner approves the specific changes in the conversation, and only the owner merges.

1. **Sync `develop` with `production`** — production carries its own merge commits, and the gate requires the head to be up to date with the base. The merge is empty (no file changes):
   ```bash
   git -C <repo> fetch origin
   git -C <repo> checkout develop && git -C <repo> pull --ff-only origin develop
   git -C <repo> merge --no-edit origin/production   # empty merge
   git -C <repo> push origin develop
   ```
2. **Open the PR** `develop → production`; the body lists one `Closes MAP-xxx` line per fully shipped ticket (`Part of MAP-xxx` for a partly shipped one):
   ```bash
   gh pr create --repo alueddeke/<repo> --base production --head develop --title "Production: …" --body-file <body.md>
   ```
3. **Required checks green** — backend `test` + `pip-audit`; frontend `build_check` + `quality` + `e2e` (§ Production Gate).
4. **Owner merges** — `gh pr merge <n> --repo alueddeke/<repo> --merge`. The merge's push to `production` starts the deploy workflow.
5. **Actions deploys and tags** the commit `deploy-YYYY-MM-DD-HHMM` (best-effort tag step, both repos). Watch the `deploy` job; then run § Post-deployment verification.

### Backend

GitHub Actions (`Deploy Backend Prod`) runs `test` + `pip-audit` → `build_and_push` → `deploy`. The deploy job does not carry the shell any more (MAP-191): it checks out **this repo's `develop`**, copies `deployment/*.sh` to the droplet, streams `deploy.env` from the GitHub secrets over ssh stdin (`write-deploy-env.sh -`, every value `printf %q`-quoted, written 0600 on the droplet only) and runs `bash ~/deployment/run.sh` — stages `10`–`15` in numbered order:

1. `10-preflight.sh` — docker login, volumes/network, pull the image, postgres up, `pg_isready`, **backup first** (empty file aborts)
2. `11-migration-gate.sh` — `migrate` + `migrate --check` against the live DB before any container moves
3. `12-swap-backend.sh` — capture `OLD_IMAGE`, collectstatic, swap, 30 s health poll, roll back to `OLD_IMAGE` on failure
4. `13-swap-worker.sh` — worker + scheduler (never roll the deploy back)
5. `14-swap-nginx.sh` — container nginx, host nginx, certbot, ufw
6. `15-verify.sh` — prune, container + public API check, running image digests

`run.sh` deletes `deploy.env` on exit. Full map: `deployment/README.md`.

**Same deploy from a laptop (GitHub Actions down or disabled):**

```bash
cd maple_key_music_academy_docker
op signin
bash deployment/deploy-from-laptop.sh            # 00 tests → 01 lint → 02 build → 03 push, then 10–15 on the droplet
bash deployment/deploy-from-laptop.sh --skip-build   # image already on Docker Hub
```

All 19 values come from 1Password (secrets + the "MapleKey Prod Config" note — the same items `scripts/secrets-sync.sh` pushes to GitHub), streamed over ssh into `~/deployment/deploy.env` without touching the laptop's disk; the scripts and their order are identical to the Actions path, so the container state is the same either way (compare the digests `15-verify.sh` prints). Tag the backend commit afterwards (`deploy-YYYY-MM-DD-HHMM`) — Actions does that step itself.

The deploy runs whatever `deployment/*.sh` is on this repo's `develop` at that moment. This repo's `production` branch is a mirror the owner fast-forwards to `develop` after a deploy that used new scripts; nothing deploys from it.

### Frontend

Test build first — non-negotiable — then the same five steps:

```bash
docker compose exec frontend pnpm run build
```

GitHub Actions (frontend `.github/workflows/deploy.yml`) runs `build_check` → build and push `maple-key-frontend:{latest,<sha>}` → deploy on the frontend droplet (inline SSH script: `OLD_IMAGE`, swap, 30 s health poll on `localhost:3000`, rollback, host nginx, certbot) → tag.

### Post-deployment verification

```bash
ssh root@159.203.173.226

# Migrations applied — verification only; the gate itself is 11-migration-gate.sh (migrate + migrate --check)
docker exec maple-key-backend python manage.py showmigrations billing | tail -20

# Container errors
docker logs maple-key-backend --tail 100 | grep -i error
docker logs nginx --tail 50 | grep -i error

# All containers running
docker ps

# API alive
curl https://api.maplekeymusic.com/api/auth/user/

# Frontend loads
curl https://maplekeymusic.com
```

---

## Database Backup

**Every backend deploy takes one first:** `10-preflight.sh` writes `~/maplekey-backups/pre-deploy-YYYYMMDD-HHMMSS.sql.gz` before any migration or container change (empty file aborts the deploy; files younger than 30 days are never pruned). A manual one, e.g. before a hand-run data script:

```bash
ssh root@159.203.173.226
docker exec postgres pg_dump -U maple_key_user maple_key_db | gzip > ~/maplekey-backups/manual-$(date -u +%Y%m%d-%H%M%S).sql.gz
ls -lh ~/maplekey-backups/ | tail -5  # verify size (should be 100KB+)
```

**Restore (emergency only):** the app containers are standalone `docker run` containers, not compose services. Stop the three backend-image containers so nothing writes during the restore; `postgres` stays up (the restore runs through it):

```bash
ssh root@159.203.173.226
docker stop maple-key-backend maple-key-worker maple-key-scheduler
gunzip -c ~/maplekey-backups/pre-deploy-YYYYMMDD-HHMMSS.sql.gz | docker exec -i postgres psql -U maple_key_user -d maple_key_db
docker start maple-key-backend maple-key-worker maple-key-scheduler
```

`psql` replays the dump into the existing database; for a clean replay into an emptied schema, rehearse on a scratch database first (`.planning/OPS-RUNBOOK.md` restore drill).

---

## Common Deployment Failures

### Frontend build fails: missing Radix UI dependency

```
Error: failed to resolve import "@radix-ui/react-tabs"
```

```bash
docker compose exec frontend pnpm add @radix-ui/react-tabs
docker compose exec frontend pnpm run build  # verify
git add package.json pnpm-lock.yaml && git commit -m "Add missing Radix UI dep"
```

### Frontend build fails: TypeScript errors

```
error TS2353: Object literal may only specify known properties
```

```bash
docker compose exec frontend pnpm run build  # read full output
# Fix each error, re-run build until clean
```

### Migration verification failed

```
[ ] 0024_add_school_and_school_settings_models
```

`11-migration-gate.sh` ran `migrate`, then `migrate --check` still found unapplied migrations — the deploy aborted before any container moved, so production is unchanged. Check the `deploy` job log for the specific error — usually a migration conflict. Fix locally, commit to `develop`, re-deploy through the PR path.

### "column already exists"

```
django.db.utils.ProgrammingError: column "school_id" already exists
```

Migration partially ran. Development: `docker compose down -v && docker compose up -d`. Production: restore from backup.

### Check migration status on production

```bash
ssh root@159.203.173.226
docker exec maple-key-backend python manage.py showmigrations billing
```

### Manual migration (if GitHub Actions skipped it)

```bash
ssh root@159.203.173.226
docker exec maple-key-backend python manage.py migrate
```

---

## Production Gate

Configured on GitHub (MAP-187, 2026-09-29; re-read 2026-10-02); changing it is owner-only (the agent's protection PUT is denied). Two layers apply to `production` in the backend and frontend repos, and GitHub enforces their union:

| Repo | Classic branch protection — PR required, applies to admins, no force push; required checks (`strict`: head up to date with base) | Repository ruleset "Production" | Effective gate |
|---|---|---|---|
| `maple_key_music_academy_backend` | `test`, `pip-audit` | required check `test`; blocks non-fast-forward + deletion | PR + `test` + `pip-audit` |
| `maple-key-music-academy-frontend` | `build_check`, `quality` | required checks `build_check`, `e2e`; blocks non-fast-forward + deletion | PR + `build_check` + `quality` + `e2e` |

Consequences: the only way onto `production` is a PR `develop → production` with those checks green, merged by the owner; a force push or a reset of `production` is rejected; `strict` is why step 1 of the deployment procedure (empty sync merge) exists. Check the live settings with `gh api repos/alueddeke/<repo>/branches/production/protection --jq .required_status_checks.contexts` and `gh api repos/alueddeke/<repo>/rulesets`.

---

## Rollback Procedures

Rollback is destructive — confirm something is actually broken before proceeding.

### Step 0 — Detect: Confirm Something Is Actually Broken

Before rolling back, verify the issue. Rollback is irreversible for DB restores.

```bash
# Deploy tags, newest first (each = the production commit that deploy ran)
git -C maple_key_music_academy_backend fetch --tags origin
git -C maple_key_music_academy_backend tag -l 'deploy-*' --sort=-creatordate | head -3
git -C maple_key_music_academy_backend rev-list -n 1 <deploy-tag>   # commit sha = image tag

# API health — expect 401 (healthy) or debug if 5xx/000
curl https://api.maplekeymusic.com/api/auth/user/

# Container errors (SSH first: ssh root@159.203.173.226)
docker logs maple-key-backend --tail 100 | grep -i error

# All containers running, and on which image
docker ps --format '{{.Names}} {{.Image}}'
```

SSH to the VPS first if checking live containers: `ssh root@159.203.173.226`

A deploy whose new backend fails the 30 s `/health/` probe has already rolled itself back: `12-swap-backend.sh` captured `OLD_IMAGE` before the swap and restarted it (worker and scheduler were never swapped). The options below are for a deploy that went green but is wrong.

**Option 1 — Git revert on `develop` (preferred, keeps history):**

**Use when:** The bad deploy contains NO database migrations — code-only change.

```bash
git -C <repo> checkout develop && git -C <repo> pull --ff-only origin develop
git -C <repo> revert <commit-hash> --no-edit      # a merge commit needs -m 1
git -C <repo> push origin develop
```

Then the five-step deployment procedure above (sync → PR `develop → production` → checks → owner merge → Actions deploys). Production never gets a commit `develop` does not have.

**Option 2 — Database restore (last resort):**

**Use when:** A migration ran and broke data integrity, OR the migration cannot be reversed forward.

Stop the three backend-image containers, restore through the running `postgres`, start them again — the steps in § Database Backup → Restore. Then deploy code that matches the restored schema (Option 1 or 3).

**Option 3 — Image rollback (fastest, no git change; backend):**

**Use when:** Production must be back on the previous build now, and the previous image's code runs against the current schema (no migration in between, or only additive ones). This is `12-swap-backend.sh`'s `OLD_IMAGE` rollback, run on purpose: the same droplet stages, every backend-image container re-created from one older `:<sha>` image.

```bash
cd maple_key_music_academy_docker
op signin
IMAGE_TAG=<previous deploy's commit sha> bash deployment/deploy-from-laptop.sh --skip-build
```

The image is already on Docker Hub (every deploy pushed `:<sha>`). The run takes a fresh backup first, the migration gate is a no-op for an older image, `/health/` gates the swap, and `15-verify.sh` asserts backend, worker and scheduler all run the named image. The environment cannot be rebuilt by hand on the droplet (`deploy.env` is deleted after every run) — that is why the rollback goes through the scripts. Afterwards `production` still names the bad commit: follow with Option 1 so the next deploy does not bring it back.

### Post-rollback Verification

Run the same checks as post-deployment to confirm rollback succeeded.

```bash
# API alive — expect 401
curl https://api.maplekeymusic.com/api/auth/user/

# Container errors
docker logs maple-key-backend --tail 100 | grep -i error

# All containers running
docker ps
```

---

## Monitoring & Logs

```bash
ssh root@159.203.173.226

# Live logs
docker logs maple-key-backend --tail 100 -f
docker logs nginx --tail 100 -f
docker logs postgres --tail 100 -f

# Resource usage
docker stats
htop
```

---

## SSL

- Provider: Let's Encrypt via Certbot
- Auto-renewal configured
- Certificate location: `/etc/letsencrypt/`
