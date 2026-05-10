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
- `postgres` — PostgreSQL 15
- `nginx` — reverse proxy

**Database:** user `maple_key_user`, database `maple_key_db`, password in production `.env`.

---

## Pre-Deployment Checklist — MANDATORY

1. [ ] All migrations tested locally (no duplicate numbers)
2. [ ] Production database backup created (see below)
3. [ ] Frontend production build passes: `docker compose exec frontend pnpm run build`
4. [ ] All `@radix-ui/*` dependencies in `package.json` AND installed (see frontend CLAUDE.md)
5. [ ] Changes committed to git

---

## Branch Model

develop → production (two branches only — main branch has been deleted)
All development work goes to develop. Deploy by merging develop into production.

## Deployment Procedure

### Backend

```bash
cd maple_key_music_academy_backend
git checkout production
git pull origin production
git merge develop
git push origin production  # triggers GitHub Actions
```

GitHub Actions automatically:
1. Runs `python manage.py migrate` in a temporary container
2. Verifies all migrations show `[X]` via `showmigrations`
3. Aborts if any migration fails (prevents code/DB mismatch)
4. Starts backend container only after migrations succeed

### Frontend

```bash
cd maple-key-music-academy-frontend

# Test build first — non-negotiable
docker compose exec frontend pnpm run build

git checkout production
git pull origin production
git merge develop
git push origin production  # triggers GitHub Actions
```

### Post-deployment verification

```bash
ssh root@159.203.173.226

# Migrations applied
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

**Create before every major deployment:**

```bash
ssh root@159.203.173.226
docker exec postgres pg_dump -U maple_key_user maple_key_db > backup_$(date +%Y%m%d_%H%M%S).sql
ls -lh backup_*.sql  # verify size (should be 100KB+)
```

**Restore (emergency only):**

```bash
docker compose down
docker exec -i postgres psql -U maple_key_user -d maple_key_db < backup_YYYYMMDD_HHMMSS.sql
docker compose up -d
```

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

GitHub Actions ran `migrate` but found unapplied migrations. Check Actions logs for the specific error — usually a migration conflict. Fix locally, commit, re-deploy.

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

## Rollback Procedures

**Option 1 — Git revert (preferred, keeps history):**

```bash
git revert <commit-hash> --no-edit
git push origin production
```

**Option 2 — Database restore (last resort):**

```bash
ssh root@159.203.173.226
docker compose down
docker exec -i postgres psql -U maple_key_user -d maple_key_db < backup_YYYYMMDD_HHMMSS.sql
docker compose up -d
```

**Option 3 — Hard reset (nuclear, destroys history):**

```bash
git reset --hard <previous-commit>
git push origin production --force
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
