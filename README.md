# Maple Key Music Academy - Complete Developer Guide

This repository contains Docker orchestration for running the complete Maple Key Music Academy stack (backend + frontend + database).

**📖 Complete guide from first-time setup to production deployment.**

---

## Table of Contents
- [Quick Start](#-quick-start)
- [First-Time Setup](#-first-time-setup)
- [Daily Development](#-daily-development)
- [Database Migrations](#-database-migrations)
- [Feature Development](#-feature-development)
- [Production Deployment](#-production-deployment)
- [Troubleshooting](#-troubleshooting)

---

## 🚀 Quick Start

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

## 🎯 First-Time Setup

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
# └── maple_key_music_academy_docker/  ← You're here!
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

### Step 5: Configure Django Admin (CRITICAL)

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

### Step 6: Install Pre-Push Hook (Prevents Migration Conflicts!)

```bash
cd ../maple_key_music_academy_backend
cp pre-push.sh .git/hooks/pre-push
chmod +x .git/hooks/pre-push

# Test it works
.git/hooks/pre-push
# Should show: ✅ No duplicate migrations found
```

### Step 7: Verify Everything Works

1. Frontend: http://localhost:5173
2. Backend: http://localhost:8000/api/
3. Admin: http://localhost:8000/admin
4. Try "Continue with Google" login
5. Check browser console for errors (F12)

---

## 📅 Daily Development

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
# Migrations apply automatically on startup!
docker compose down && docker compose up

# Check logs to verify:
docker compose logs api | grep "Applying billing"
```

### Stopping Development

```bash
docker compose down  # Stop containers (data preserved)

# ⚠️ ONLY if you want to delete database:
docker compose down -v  # Deletes ALL data including superuser!
```

---

## 🗄️ Database Migrations

### 🚨 MIGRATION CONFLICT PREVENTION CHECKLIST

**Read this BEFORE creating any migrations!**

#### Before Starting Work:
- [ ] `git checkout develop && git pull origin develop` - Get latest migrations
- [ ] Check no one else is working on models
- [ ] Review existing migration numbers: `ls billing/migrations/ | grep "^0"`

#### Before Creating Migrations:
- [ ] `git pull origin develop` - Pull again!
- [ ] Edit your models
- [ ] `docker compose exec api python manage.py makemigrations`

#### After Creating Migrations:
- [ ] Check for duplicates:
  ```bash
  cd billing/migrations
  ls -1 | grep "^0" | cut -d_ -f1 | sort | uniq -d
  # No output = good!
  ```
- [ ] Test migration: `docker compose exec api python manage.py migrate`
- [ ] Test rollback: `docker compose exec api python manage.py migrate billing 00XX`
- [ ] Re-apply: `docker compose exec api python manage.py migrate billing`

#### Before Pushing:
- [ ] Double-check no duplicates exist
- [ ] Commit migration WITH code changes
- [ ] Consider impact on other developers

### Automated Duplicate Detection: Pre-Push Hook

**What It Is:**
Script that runs automatically every `git push` to check for duplicate migrations.

**How It Works:**
1. Automatically runs before push
2. Scans `billing/migrations/` for duplicates
3. If found: **BLOCKS push** and shows conflicts
4. If none: Allows push to proceed

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

### Creating Migrations Safely

```bash
# STEP 1: Pull latest
git checkout develop && git pull origin develop

# STEP 2: Create feature branch
git checkout -b feature/add-student-notes

# STEP 3: Edit models
# Edit ../maple_key_music_academy_backend/billing/models.py

# STEP 4: Create migration
docker compose exec api python manage.py makemigrations

# STEP 5: Apply locally
docker compose exec api python manage.py migrate

# STEP 6: Test it works
# Visit http://localhost:5173 and test feature

# STEP 7: Commit migration WITH code
cd ../maple_key_music_academy_backend
git add billing/migrations/ billing/models.py
git commit -m "Add notes field to Student model"
git push origin feature/add-student-notes
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

## 💻 Feature Development

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

# DO NOT include Claude Code signatures!

git push origin feature/add-lesson-notes
```

---

## 🚀 Production Deployment

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
# 3. Merge → 🚀 GitHub Actions auto-deploys!
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

---

## 🆘 Troubleshooting

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
docker compose down -v  # Note the -v flag!
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

## 🏗️ Development vs Production

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

## 📖 Related Documentation

**Reference:**
- [../CLAUDE.md](../CLAUDE.md) - System architecture, models, API reference
- [../maple_key_music_academy_backend/README.md](../maple_key_music_academy_backend/README.md) - Backend details
- [../maple-key-music-academy-frontend/README.md](../maple-key-music-academy-frontend/README.md) - Frontend patterns

---

## 🎯 Quick Command Reference

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

**Happy coding! 🎵**

**Last Updated:** 2024-11-24
