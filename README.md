# Maple Key Music Academy - Complete Developer Guide

This repository contains Docker orchestration for running the complete Maple Key Music Academy stack (backend + frontend + database).

**📖 Complete guide from first-time setup to production deployment.**

---

## Table of Contents
- [Quick Start](#quick-start)
- [First-Time Setup](#first-time-setup)
- [Daily Development](#daily-development)
- [Database Migrations](#database-migrations)
- [Feature Development](#feature-development)
- [Production Deployment](#production-deployment)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

**For developers who already have the environment set up:**

```bash
cd maple_key_music_academy_docker
docker compose up  # Start everything

# Access:
# - Frontend: http://localhost:5173
# - Backend: http://localhost:8000
# - Admin: http://localhost:8000/admin
```

---

## 🏛️ Architecture Decision Records

Development and deployment decisions are documented in [ADRs](./docs/adr/README.md).

**Key Infrastructure Decisions:**
- [DK-0001: Docker-Based Development](./docs/adr/DK-0001-docker-based-development.md) - Container orchestration for development environment

---

## First-Time Setup

### Step 1: Clone All Repositories

```bash
# Create project directory
mkdir MapleKey_music_school
cd MapleKey_music_school

# Clone all three repositories
git clone <backend-repo-url> maple_key_music_academy_backend
git clone <frontend-repo-url> maple-key-music-academy-frontend
git clone <docker-repo-url> maple_key_music_academy_docker

# Directory structure:
# MapleKey_music_school/
# ├── maple_key_music_academy_backend/
# ├── maple-key-music-academy-frontend/
# └── maple_key_music_academy_docker/  ← You are here
```

### Step 2: Set Up Environment Variables

```bash
cd maple_key_music_academy_docker

# Copy template
cp .envs/env.dev.example .envs/env.dev

# Edit with your credentials
# Required:
# - GOOGLE_CLIENT_ID (get from team)
# - GOOGLE_CLIENT_SECRET (get from team)
# - EMAIL_HOST_USER (optional, for testing emails)
# - EMAIL_HOST_PASSWORD (optional, Gmail app password)
```

### Step 3: Start Docker Containers

```bash
# First time - build and start
docker compose up --build

# What starts:
# - PostgreSQL database (port 5432)
# - Django backend (port 8000)
# - React frontend (port 5173)
# - Nginx reverse proxy (port 8000)
```

### Step 4: Create Superuser

Open a **new terminal** (keep the first one running):

```bash
cd maple_key_music_academy_docker

# Create superuser
docker compose exec api python manage.py createsuperuser

# Follow prompts:
# - Email: your-email@example.com
# - Password: (choose a secure password)
# - First name: Your Name
# - Last name: Your Last Name
# - User type: management
```

### Step 5: Configure Django Admin (CRITICAL FOR OAUTH)

**Required for OAuth to work:**

1. Visit http://localhost:8000/admin
2. Log in with your superuser credentials

**Create Site (ID=2):**
- Navigate to **Sites** (under SITES)
- Click **Add Site**
- Domain: `localhost:8000`
- Display name: `Maple Key Music Academy Dev`
- Save (note: must be ID=2)

**Configure Google OAuth:**
- Navigate to **Social applications** (under SOCIAL ACCOUNTS)
- Click **Add social application**
- Provider: `Google`
- Name: `Google OAuth Dev`
- Client ID: (from `.envs/env.dev`)
- Secret key: (from `.envs/env.dev`)
- Sites: Select the site you created (ID=2)
- Save

### Step 6: Install Pre-Push Hook (Prevents Migration Conflicts)

**What it does:** Automatically scans ALL Django apps for duplicate migration numbers before every `git push`. Blocks push if duplicates found.

**What it prevents:** The #1 cause of migration conflicts (two developers creating migrations with the same number simultaneously).

**What it doesn't prevent:** Breaking schema changes, data migration failures, or manually edited migrations. Still follow migration best practices.

```bash
cd ../maple_key_music_academy_backend
cp pre-push.sh .git/hooks/pre-push
chmod +x .git/hooks/pre-push

# Test it works
.git/hooks/pre-push
# Should show: ✅ No duplicate migrations found in any app
```

**Note:** This hook automatically detects all apps (billing, custom_auth, and any future apps). You never need to update it when adding new Django apps.

### Step 7: Verify Everything Works

1. Frontend: http://localhost:5173
2. Backend: http://localhost:8000/api/
3. Admin: http://localhost:8000/admin
4. Try "Continue with Google" login
5. Check browser console for errors (F12)

---

## Daily Development

### Starting Your Day

```bash
cd maple_key_music_academy_docker
docker compose up  # Or docker compose up -d for background
```

### Pulling Latest Changes

**Scenario 1: Just Code Changes**
```bash
# Stop containers
docker compose down

# Pull both repos
cd ../maple_key_music_academy_backend && git pull origin develop
cd ../maple-key-music-academy-frontend && git pull origin develop
cd ../maple_key_music_academy_docker

# Restart
docker compose up
```

**Scenario 2: Dependencies Changed** (package.json or requirements.txt)
```bash
# Pull changes first
docker compose down
docker compose build --no-cache
docker compose up
```

**Scenario 3: New Migrations**
```bash
# Migrations apply automatically on startup
docker compose down && docker compose up

# Check logs to verify:
docker compose logs api | grep "Applying billing"
```

### Stopping Development

```bash
docker compose down  # Stop containers (data preserved)

# ⚠️ ONLY if you want to delete database:
docker compose down -v  # Deletes ALL data including superuser
```

---

## Database Migrations

### MIGRATION CONFLICT PREVENTION CHECKLIST

**Read this BEFORE creating any migrations**

#### Before Starting Work:
- [ ] `git checkout develop && git pull origin develop` - Get latest migrations
- [ ] Check no one else is working on models
- [ ] Review existing migration numbers: `ls billing/migrations/ | grep "^0"`

#### Before Creating Migrations:
- [ ] `git pull origin develop` - Pull again
- [ ] Edit your models
- [ ] `docker compose exec api python manage.py makemigrations`

#### After Creating Migrations:
- [ ] Check for duplicates:
  ```bash
  cd billing/migrations
  ls -1 | grep "^0" | cut -d_ -f1 | sort | uniq -d
  # No output = good
  ```
- [ ] Test migration: `docker compose exec api python manage.py migrate`
- [ ] Test rollback: `docker compose exec api python manage.py migrate billing 00XX`
- [ ] Re-apply: `docker compose exec api python manage.py migrate billing`

#### Before Pushing:
- [ ] Double-check no duplicates exist
- [ ] Commit migration WITH code changes
- [ ] Consider impact on other developers
- [ ] Verify migration type (additive vs destructive - see below)

---

### Understanding Migration Types

**CRITICAL: Not all migrations are created equal**

Django migrations fall into two categories based on safety:

#### ✅ Additive Migrations (Safe - Deploy Immediately)

**Definition:** Changes that ADD to the database without breaking existing code or data.

**Examples:**
- Adding a new field with `blank=True` or `default=`
- Adding a new model
- Making a field nullable (more permissive)
- Making a field longer (CharField max_length increase)
- Adding an index

**Why safe:** Existing code continues to work. New field is optional or has a default value.

#### ⚠️ Destructive Migrations (Dangerous - Requires 2-Step Deployment)

**Definition:** Changes that REMOVE or RESTRICT database structure or data.

**Examples:**
- Removing a field
- Renaming a field
- Making a field required (`null=False` when it was `null=True`)
- Making a field shorter (CharField max_length decrease)
- Changing field type (IntegerField → CharField)
- Deleting a model

**Why dangerous:** Running code still expects the old structure. Migration runs but code breaks.

---

### Safe Migration Workflows

#### Workflow 1: Adding a Field (Simple)

**Example:** Add `notes` field to Student model

```bash
# 1. Pull latest
git checkout develop && git pull origin develop
git checkout -b feature/add-student-notes

# 2. Edit model - ALWAYS use blank=True or default=
# In maple_key_music_academy_backend/billing/models.py:
class Student(models.Model):
    # ... existing fields ...
    notes = models.TextField(blank=True)  # ← Safe: optional field

# 3. Create migration
docker compose exec api python manage.py makemigrations
# Output: Created migration 0008_student_notes.py

# 4. Test migration (forward and backward)
docker compose exec api python manage.py migrate
# Test app works: http://localhost:5173
docker compose exec api python manage.py migrate billing 0007  # Rollback
docker compose exec api python manage.py migrate billing       # Re-apply

# 5. Commit and push
cd maple_key_music_academy_backend
git add billing/models.py billing/migrations/0008_student_notes.py
git commit -m "Add notes field to Student model"
git push origin feature/add-student-notes

# 6. Merge to develop → main → production (immediate deploy OK)
```

**✅ Result:** Safe to deploy immediately. No downtime.

---

#### Workflow 2: Removing a Field (2-Step - PRODUCTION ONLY)

**Example:** Remove `old_phone_number` field from Student model

**⚠️ LOCAL DEV: Just delete the field and migrate (database reset is fine)**

**⚠️ PRODUCTION: Requires 2-step deployment to avoid downtime**

##### Step 1: Make Field Optional & Remove Usage (Week 1)

```bash
# 1. Pull latest
git checkout develop && git pull origin develop
git checkout -b feature/remove-old-phone

# 2. Edit model - Make field nullable
# In maple_key_music_academy_backend/billing/models.py:
class Student(models.Model):
    # ... other fields ...
    old_phone_number = models.CharField(max_length=15, blank=True, null=True)  # ← Made optional

# 3. Remove ALL code references to this field
# Check views, serializers, forms, templates
# Use grep to find usages:
cd maple_key_music_academy_backend
grep -r "old_phone_number" billing/

# 4. Create migration
docker compose exec api python manage.py makemigrations
# Output: Created migration 0008_make_old_phone_nullable.py

# 5. Test locally
docker compose exec api python manage.py migrate
# Test app works WITHOUT using old_phone_number field

# 6. Commit and deploy to production
git add .
git commit -m "Make old_phone_number nullable, remove usage from code"
git push origin feature/remove-old-phone
# Merge through: develop → main → production
```

**✅ Deploy to production → WAIT → Monitor for 1-2 days**

##### Step 2: Remove Field Completely (Week 2)

```bash
# 1. Pull latest
git checkout develop && git pull origin develop
git checkout -b feature/remove-old-phone-final

# 2. Delete field from model
# In maple_key_music_academy_backend/billing/models.py:
class Student(models.Model):
    # ... other fields ...
    # old_phone_number deleted ← Remove the entire line

# 3. Create migration
docker compose exec api python manage.py makemigrations
# Output: Created migration 0009_remove_old_phone_number.py

# 4. Test locally
docker compose exec api python manage.py migrate
# Test app still works

# 5. Commit and deploy
git add .
git commit -m "Remove old_phone_number field from Student model"
git push origin feature/remove-old-phone-final
# Merge through: develop → main → production
```

**✅ Result:** Safe removal with zero downtime

---

#### Quick Reference: Do I Need 2-Step Deployment?

| Change Type | Example | Local Dev | Production |
|-------------|---------|-----------|------------|
| **Add optional field** | `notes = TextField(blank=True)` | 1-step ✅ | 1-step ✅ |
| **Add field with default** | `status = CharField(default='active')` | 1-step ✅ | 1-step ✅ |
| **Add new model** | `class Payment(models.Model): ...` | 1-step ✅ | 1-step ✅ |
| **Make field nullable** | `null=False` → `null=True` | 1-step ✅ | 1-step ✅ |
| **Remove field** | Delete field line | 1-step ✅ | **2-step ⚠️** |
| **Rename field** | `old_name` → `new_name` | 1-step ✅ | **2-step ⚠️** |
| **Make field required** | `null=True` → `null=False` | 1-step ✅ | **2-step ⚠️** |
| **Add required field** | `email = EmailField()` (no default) | ❌ Do not use | ❌ Do not use |

**Local Dev Rule:** Reset database anytime (`docker compose down -v`), so 1-step is always fine.

**Production Rule:** Use 2-step for ANY destructive change. Data and uptime matter.

---

### Automated Duplicate Detection: Pre-Push Hook

**What It Is:**
Script that runs automatically every `git push` to check for duplicate migrations across **all Django apps**.

**How It Works:**
1. Automatically runs before push
2. Scans ALL apps' migration directories (billing, custom_auth, future apps)
3. If found: **BLOCKS push** and shows conflicts
4. If none: Allows push to proceed

**What It Prevents:** Duplicate migration numbers (the #1 cause of conflicts)

**What It Doesn't Prevent:** Destructive migrations, breaking changes, or data migration failures. See "Understanding Migration Types" above

**Example Output:**

✅ **Success:**
```
🔍 Checking for duplicate migration numbers...
✅ No duplicate migrations found
```

❌ **Blocked:**
```
❌ ERROR: Duplicate migration numbers detected!
   - 0008_
     billing/migrations/0008_add_field_x.py
     billing/migrations/0008_add_field_y.py
   Fix: Delete your migration, pull latest, recreate
```

### Creating Migrations Safely - Quick Checklist

**For detailed workflows with examples, see "Safe Migration Workflows" above**

```bash
# STEP 1: Pull latest
git checkout develop && git pull origin develop

# STEP 2: Create feature branch
git checkout -b feature/add-student-notes

# STEP 3: Edit models
# Edit ../maple_key_music_academy_backend/billing/models.py
# ⚠️ Adding a field? Use blank=True or default= (see Workflow 1 above)
# ⚠️ Removing a field? Use 2-step deployment (see Workflow 2 above)

# STEP 4: Create migration
docker compose exec api python manage.py makemigrations

# STEP 5: Apply and test locally
docker compose exec api python manage.py migrate
# Visit http://localhost:5173 and test feature

# STEP 6: Test rollback
docker compose exec api python manage.py migrate billing 00XX  # Previous number
docker compose exec api python manage.py migrate billing       # Re-apply

# STEP 7: Commit migration WITH code
cd ../maple_key_music_academy_backend
git add billing/migrations/ billing/models.py
git commit -m "Add notes field to Student model"
git push origin feature/add-student-notes
# Pre-push hook will check for duplicates automatically
```

### If Duplicate Migrations Detected

**Before Pushing (You Created It):**
```bash
# Delete your migration
rm billing/migrations/00XX_your_migration.py

# Pull latest
git pull origin develop

# Recreate (gets next available number)
docker compose exec api python manage.py makemigrations
```

**After Teammate Pushed (You're Pulling It):**
See [Troubleshooting - Teammate Consolidated Migrations](#issue-teammate-consolidated-migrations---database-reset-required)

---

## Feature Development

### Step 1: Create Feature Branch

```bash
# Backend changes:
cd maple_key_music_academy_backend

# OR Frontend changes:
cd maple-key-music-academy-frontend

# Ensure on develop and up to date
git checkout develop && git pull origin develop

# Create feature branch
git checkout -b feature/add-lesson-notes
```

### Step 2: Start Docker Environment

```bash
cd maple_key_music_academy_docker
docker compose up

# Changes auto-reload:
# - Backend: Django auto-reloads on save
# - Frontend: Vite HMR updates instantly
```

### Step 3: Make Your Changes

**Backend:** Edit files in `maple_key_music_academy_backend/`
- Models: `billing/models.py`
- Views: `billing/views.py`
- Serializers: `billing/serializers.py`
- URLs: `billing/urls.py`

**Frontend:** Edit files in `maple-key-music-academy-frontend/`
- Pages: `src/pages/`
- Components: `src/components/`
- API queries: `src/queries/`
- Types: `src/types/`

### Step 4: Test Locally

**Manual Testing:**
1. Visit http://localhost:5173
2. Test your feature
3. Check browser console (F12)
4. Test different user types

**Backend Tests:**
```bash
docker compose exec api python manage.py test
```

### Step 5: Commit and Push

```bash
git add .
git commit -m "Add lesson notes feature

- Add notes field to Lesson model
- Create notes UI in lesson detail page
- Add validation for note length"

# DO NOT include Claude Code signatures

git push origin feature/add-lesson-notes
```

---

## Production Deployment

### Branch Strategy

```
feature/your-feature
    ↓ PR & merge
develop
    ↓ PR & merge (code review)
main
    ↓ PR & merge (triggers deployment)
production → 🚀 DEPLOYS TO DIGITAL OCEAN
```

### Deployment Steps

#### Step 1: Merge to Develop

```bash
# Push feature branch
git push origin feature/add-lesson-notes

# On GitHub:
# 1. Create PR: feature → develop
# 2. Request review
# 3. Merge when approved
```

#### Step 2: Test on Develop

```bash
git checkout develop && git pull origin develop
cd maple_key_music_academy_docker
docker compose down && docker compose up --build

# Test:
# ✓ No errors in logs
# ✓ Migrations apply successfully
# ✓ Feature works
# ✓ No regressions
```

#### Step 3: Merge to Main

```bash
# On GitHub:
# 1. Create PR: develop → main
# 2. Code review
# 3. Merge when approved
# ⚠️ NO deployment yet (main is review gate)
```

#### Step 4: Deploy to Production

```bash
# On GitHub:
# 1. Create PR: main → production
# 2. Final review checklist:
#    ✓ All tests passing
#    ✓ Migrations tested
#    ✓ Breaking changes documented
# 3. Merge and GitHub Actions will auto-deploy
```

### Monitor Deployment

**GitHub Actions:**
1. Go to repo → Actions tab
2. Watch workflow progress
3. Check each step completes

**Verify Production:**
```bash
# Check endpoints
curl -I https://maplekeymusic.com
curl -I https://api.maplekeymusic.com

# Test in browser:
# 1. Visit https://maplekeymusic.com
# 2. Open console (F12)
# 3. Test login
# 4. Test your feature
```

### Deployment Infrastructure

**Platform:** Digital Ocean Droplets
**DNS:** Porkbun
**SSL:** Let's Encrypt (auto-configured via Certbot)

**Production URLs:**
- Frontend: https://maplekeymusic.com
- Backend API: https://api.maplekeymusic.com

### Deployment Process Details

**Backend Deployment (maple_key_music_academy_backend):**
1. GitHub Actions builds Docker image
2. Pushes to Docker Hub
3. SSHs into backend droplet
4. Pulls latest Docker images (postgres:15, backend)
5. Stops old containers
6. Runs database migrations
7. Collects static files
8. Starts new containers (postgres, backend, nginx)
9. Configures host Nginx as reverse proxy
10. Sets up/renews SSL certificate via Certbot
11. Verifies deployment health

**Frontend Deployment (maple-key-music-academy-frontend):**
1. GitHub Actions builds Docker image with production build
2. Pushes to Docker Hub
3. SSHs into frontend droplet
4. Pulls latest Docker image
5. Stops old container
6. Starts new container
7. Configures host Nginx as reverse proxy
8. Sets up/renews SSL certificate via Certbot
9. Verifies deployment health

### View Deployment Logs

**GitHub Actions:**
- Go to repository → Actions tab
- Click on the latest workflow run
- View logs for each step

**Docker Logs on Droplet:**
```bash
# SSH into droplet
ssh user@droplet-ip

# View backend logs
docker logs maple-key-backend -f

# View frontend logs
docker logs maple-key-frontend -f

# View database logs
docker logs postgres -f

# View nginx logs
docker logs nginx -f
```

### Rollback (If Needed)

**GitHub UI Method:**
```bash
# 1. Go to repo → Commits
# 2. Find bad commit
# 3. Click "..." → "Revert"
# 4. Create PR with revert
# 5. Merge to production
# GitHub Actions auto-deploys the rollback
```

**Command Line Method:**
```bash
git log --oneline  # Find bad commit
git revert <commit-sha>
git push origin production
```

**Emergency Manual Rollback on Droplet:**
```bash
# SSH into droplet
ssh user@droplet-ip

# Roll back to previous Docker image
docker pull username/maple-key-backend:previous-sha
docker stop maple-key-backend
docker rm maple-key-backend
docker run -d --name maple-key-backend ... username/maple-key-backend:previous-sha
```

---

## Production Database Reset (Emergency Only)

**⚠️ LAST RESORT - Use only when migration state is completely broken and unfixable**

This procedure completely destroys the production database and recreates it from scratch. **ALL DATA WILL BE LOST.**

### When to Use This

Only use when:
- Migration state is completely corrupted (migrations out of sync with schema)
- Faking migrations doesn't work
- Column mismatch errors that can't be resolved
- Database was manually edited outside of migrations
- **You've confirmed all stakeholders understand data will be lost**

### Prerequisites Checklist

Before proceeding:
- [ ] **Backup any critical data** (export students, invoices, users if possible)
- [ ] **Confirm with stakeholders** that data loss is acceptable
- [ ] **Document what caused the issue** to prevent recurrence
- [ ] **SSH access** to production backend droplet
- [ ] **GitHub Actions** deployment is NOT currently running

### Step-by-Step Procedure

**Step 1: SSH into backend server**
```bash
ssh root@<backend-droplet-ip>
```

**Step 2: Stop all containers**
```bash
docker stop maple-key-backend postgres nginx
```

**Step 3: Remove postgres container and ALL volumes**
```bash
# Remove main postgres container
docker rm postgres

# Remove any old postgres containers
docker ps -a | grep postgres
docker rm <any-old-container-ids>

# Remove ALL postgres volumes
docker volume rm postgres_data
docker volume ls | grep postgres  # Check for stranded volumes
docker volume rm <any-postgres-volumes>
```

**Step 4: Recreate postgres with correct credentials**

First, check what credentials the backend expects:
```bash
docker exec maple-key-backend printenv | grep -E "POSTGRES|DATABASE"
# Output will show: DATABASE_URL=postgresql://USER:PASSWORD@postgres:5432/DB_NAME
```

Then create postgres with matching credentials:
```bash
docker run -d \
  --name postgres \
  --network maple-key-network \
  -e POSTGRES_DB=<DB_NAME from above> \
  -e POSTGRES_USER=<USER from above> \
  -e POSTGRES_PASSWORD=<PASSWORD from above> \
  -v postgres_data:/var/lib/postgresql/data \
  postgres:15
```

**Step 5: Wait for postgres to initialize**
```bash
sleep 10
docker logs postgres  # Should show "database system is ready to accept connections"
```

**Step 6: Restart backend and run migrations**
```bash
docker restart maple-key-backend
sleep 5
docker exec -it maple-key-backend python manage.py migrate
```

**Step 7: Create superuser**
```bash
docker exec -it maple-key-backend python manage.py createsuperuser
# Email: your-email@gmail.com (use your Google OAuth email)
# User type: management
```

**Step 8: Configure Django admin**
```bash
# Access Django admin at: https://api.maplekeymusic.com/admin/
# Login with superuser credentials

# 1. Fix Site domain (CRITICAL for OAuth):
#    Sites → Click site ID 2 → Change domain to "maplekeymusic.com" → Save

# 2. Configure Google OAuth:
#    Social Apps → Add → Fill in:
#    - Provider: Google
#    - Name: Google OAuth
#    - Client ID: <from GitHub Secrets>
#    - Client Secret: <from GitHub Secrets>
#    - Sites: Move "maplekeymusic.com" from Available → Chosen → Save

# 3. Pre-approve your email for OAuth:
#    Approved Emails → Add → Email: your-email@gmail.com, User type: management → Save
```

**Step 9: Start nginx and verify**
```bash
docker start nginx
docker ps  # All 3 containers should be running
```

**Step 10: Test OAuth login**
- Go to https://maplekeymusic.com
- Click "Sign in with Google"
- Should successfully log in

**Step 11: Recreate essential data**
- Pre-approve teacher/student emails in Django admin
- Recreate any critical system settings
- Notify users to re-register if needed

### Post-Reset Checklist

After successful reset:
- [ ] OAuth login works
- [ ] Can create students
- [ ] Can create invoices
- [ ] Email notifications work
- [ ] All containers running: `docker ps`
- [ ] Document what caused the reset

### Troubleshooting Reset Issues

**Issue: "could not translate host name postgres"**
- Fix: Connect postgres to correct network:
  ```bash
  docker network connect maple-key-network postgres
  docker restart maple-key-backend
  ```

**Issue: "password authentication failed"**
- Fix: Postgres credentials don't match backend env vars
- Check: `docker exec maple-key-backend printenv | grep DATABASE`
- Recreate postgres with matching credentials

**Issue: "column X does not exist" after migrations**
- Fix: Migration state is STILL broken
- Repeat full reset from Step 3

**Issue: OAuth redirects to wrong domain**
- Fix: Django admin → Sites → Site ID 2 → Domain must be exact production domain
- No `https://`, no trailing slash, just: `maplekeymusic.com`

---

## Troubleshooting

### Environment Variables Reference

**Local Development:** `.envs/env.dev` (gitignored)

**Required Variables:**
- `SECRET_KEY` - Django secret key
- `DEBUG=True` - Debug mode for development
- `ALLOWED_HOSTS=localhost,127.0.0.1`
- `FRONTEND_URL=http://localhost:5173` - OAuth redirect destination
- `VITE_API_URL=http://localhost:8000/api` - Frontend API base URL
- `GOOGLE_CLIENT_ID` - Google OAuth client ID
- `GOOGLE_CLIENT_SECRET` - Google OAuth secret
- `CORS_ALLOWED_ORIGINS=*` - Frontend origins (use `*` for local dev)

**Database Variables:**
```bash
POSTGRES_DB=maple_key_dev
POSTGRES_USER=maple_key_user
POSTGRES_PASSWORD=your_password
POSTGRES_HOST=db  # Docker service name
POSTGRES_PORT=5432
```

**Email Variables (optional for local):**
```bash
EMAIL_HOST_USER=your-gmail@gmail.com
EMAIL_HOST_PASSWORD=your-app-password
```

**Production Deployment:** GitHub Secrets (never in code)

**Both Repos:**
- `DOCKER_USERNAME` - Docker Hub username
- `DOCKER_PASSWORD` - Docker Hub password/token

**Backend Repo:**
- `VPC_HOST` - Backend droplet IP address
- `VPC_USERNAME` - SSH username for backend droplet
- `VPC_SSH_KEY` - SSH private key for backend droplet
- `VPC_PORT` - SSH port (usually 22)
- `POSTGRES_USER` - Production database user
- `POSTGRES_PASSWORD` - Production database password
- `POSTGRES_DB` - Production database name
- `DJANGO_SECRET_KEY` - Django production secret key
- `ALLOWED_HOSTS` - Production allowed hosts (api.maplekeymusic.com)
- `GOOGLE_CLIENT_ID` - Google OAuth client ID
- `GOOGLE_CLIENT_SECRET` - Google OAuth client secret
- `CORS_ALLOWED_ORIGINS` - Production CORS origins (https://maplekeymusic.com)
- `CERTBOT_EMAIL` - Email for SSL certificate notifications

**Frontend Repo:**
- `VPS_HOST` - Frontend droplet IP address
- `VPS_USERNAME` - SSH username for frontend droplet
- `VPS_SSH_KEY` - SSH private key for frontend droplet
- `VPS_PORT` - SSH port (usually 22)

### Common Local Issues

#### Issue: "Cannot connect to database"

```bash
# Check database running
docker compose ps | grep db

# Check logs
docker compose logs db

# Restart database
docker compose restart db

# If still broken:
docker compose down && docker compose up
```

#### Issue: "Migrations not applying"

```bash
# Check status
docker compose exec api python manage.py showmigrations

# Try manually
docker compose exec api python manage.py migrate

# Check for conflicts
docker compose exec api python manage.py migrate --plan
```

#### Issue: "Teammate Consolidated Migrations - Database Reset Required"

**When This Happens:**
Teammate consolidated conflicting migrations. You'll see:
- "column already exists"
- "migration X conflicts with Y"
- Missing migration files

**Why Reset Required:**
Your local database has OLD migrations applied. New consolidated migration tries to create things that already exist.

**Solution:**

**1. Pull Latest:**
```bash
cd maple_key_music_academy_backend && git pull origin main
cd ../maple-key-music-academy-frontend && git pull origin main
```

**2. Reset Database:**
⚠️ **Deletes all local data (superuser, test data, etc.)**
```bash
cd ../maple_key_music_academy_docker
docker compose down -v  # Note the -v flag
docker compose up
```

**3. Recreate Superuser:**
```bash
docker compose exec api python manage.py createsuperuser
```

**4. Configure Django Admin:**
```bash
# Visit http://localhost:8000/admin
# Configure Site (ID=2) and Google OAuth
# See Step 5 in First-Time Setup
```

**5. Install Pre-Push Hook:**
```bash
cd ../maple_key_music_academy_backend
cp pre-push.sh .git/hooks/pre-push && chmod +x .git/hooks/pre-push
```

**6. Verify:**
- [ ] Frontend loads: http://localhost:5173
- [ ] Backend works: http://localhost:8000/api/
- [ ] Admin works: http://localhost:8000/admin
- [ ] Test creating data

**Why This Happened:**
Multiple developers created migrations with same number simultaneously.

**Prevent Future Issues:**
- **ALWAYS pull develop BEFORE creating migrations**
- Use the pre-push hook (Step 5 above)
- Follow Migration Checklist

#### Issue: "OAuth not working"

```bash
# Verify Django admin setup
# 1. http://localhost:8000/admin
# 2. Sites → Site ID=2 exists
# 3. Social applications → Google OAuth configured
# 4. .envs/env.dev has GOOGLE_CLIENT_ID/SECRET
```

#### Issue: "Frontend can't call backend"

```bash
# Check VITE_API_URL
cat .envs/env.dev | grep VITE_API_URL
# Should be: http://localhost:8000/api

# Check CORS
cat .envs/env.dev | grep CORS_ALLOWED_ORIGINS
# Should be: * (for local dev)

# Restart
docker compose restart api frontend
```

#### Issue: "Deployment fails with DEBUG=True error"

- Fixed: Backend now uses `DEBUG=False` in production

#### Issue: "SSL certificate not auto-renewing"

```bash
# SSH into droplet
sudo certbot renew --dry-run
sudo certbot certificates
```

#### Issue: "Database connection errors in production"

- Check GitHub Secrets for correct DB credentials
- Verify postgres container is running: `docker ps | grep postgres`

#### Issue: "CORS errors in browser"

- Verify `CORS_ALLOWED_ORIGINS` GitHub Secret includes https://maplekeymusic.com
- Check browser console for specific blocked origin

#### Issue: "Dependencies not installing"

```bash
# Rebuild with no cache
docker compose down
docker compose build --no-cache
docker compose up
```

### Getting Help

**Before asking:**
1. Check this troubleshooting section
2. Check container logs: `docker compose logs -f`
3. Try rebuilding: `docker compose down && docker compose build --no-cache && docker compose up`

**When asking, provide:**
- What you were trying to do
- What happened instead
- Error messages from logs
- What you've already tried

### Useful Commands

```bash
# Check what's running
docker compose ps

# View all logs
docker compose logs -f

# View specific service
docker compose logs -f api
docker compose logs -f frontend

# Check environment variables
docker compose exec api env | grep DATABASE
docker compose exec frontend env | grep VITE

# Check migrations
docker compose exec api python manage.py showmigrations

# Access database
docker compose exec db psql -U maple_key_user -d maple_key_dev

# Restart service
docker compose restart api

# Rebuild everything
docker compose down && docker compose build --no-cache && docker compose up
```

---

## Development vs Production

### File Structure
```
maple_key_music_academy_docker/
├── docker-compose.yaml          # ← DEVELOPMENT
├── docker-compose.prod.yaml     # ← PRODUCTION
├── .envs/
│   ├── env.dev                  # Local (gitignored)
│   └── env.prod                 # Not used (GitHub Secrets)
└── nginx/
    ├── Dockerfile.dev
    └── Dockerfile.prod
```

### Key Differences

| Feature | Development | Production |
|---------|------------|------------|
| **Command** | `docker compose up` | `docker compose -f docker-compose.prod.yaml up` |
| **Frontend** | Vite dev server | Nginx static files |
| **Backend** | Django runserver | Gunicorn |
| **Hot Reload** | ✅ Yes | ❌ No |
| **Database** | Exposed port 5432 | Internal only |
| **Deploy** | Manual | Auto (GitHub Actions) |

### Why Two Setups?

**Development:** Fast feedback, debugging, quick iterations
**Production:** Optimized builds, security, reliability

---

## Related Documentation

**Reference:**
- [../CLAUDE.md](../CLAUDE.md) - System architecture, models, API reference
- [../maple_key_music_academy_backend/README.md](../maple_key_music_academy_backend/README.md) - Backend details
- [../maple-key-music-academy-frontend/README.md](../maple-key-music-academy-frontend/README.md) - Frontend patterns

---

## Quick Command Reference

```bash
# Start development
docker compose up

# Stop
docker compose down

# Rebuild
docker compose down && docker compose build --no-cache && docker compose up

# View logs
docker compose logs -f api

# Create superuser
docker compose exec api python manage.py createsuperuser

# Migrations
docker compose exec api python manage.py makemigrations
docker compose exec api python manage.py migrate

# Run tests
docker compose exec api python manage.py test
```

---


**Last Updated:** 2025-12-11
