# Maple Key Music Academy - Development Workflow

## 🎯 **Automatic Dependency Management**

Your Docker setup now handles dependencies automatically! No more local `npm install` needed.

## 🚀 **When Pulling Changes with New Dependencies**

### **When a team member adds new dependencies:**
```bash
# 1. Fetch changes from remote
git fetch origin
git checkout feature-branch

# 2. Rebuild containers (installs new dependencies automatically)
docker-compose down
docker-compose build --no-cache
docker-compose up -d

# 3. That's it! Your database and superuser are still there
```

### **When only source code changes (no new dependencies):**
```bash
# 1. Fetch changes
git pull origin feature-branch

# 2. Just restart containers (faster)
docker-compose restart

# 3. Or if you want to be safe:
docker-compose down
docker-compose build
docker-compose up -d
```

## 🔧 **Adding Dependencies (For Any Developer)**

### **Adding new dependencies:**
```bash
# Add new dependency
npm install some-new-library

# Commit and push
git add package.json package-lock.json
git commit -m "Add some-new-library"
git push origin feature-branch
```

**Other team members will need to rebuild when they pull your changes.**

## 📋 **What's Different Now**

### **✅ What You Keep:**
- All database data
- Your superuser account
- All existing records
- Database schema and migrations

### **🔄 What Gets Updated:**
- Frontend dependencies (installed automatically)
- Backend dependencies (installed automatically)
- Container cache (rebuilds fresh)

## 🛠️ **Development Commands**

### **Start Development Environment:**
```bash
cd maple_key_music_academy_docker
docker-compose up -d
```

### **Stop Development Environment:**
```bash
docker-compose down
```

### **View Logs:**
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f frontend
docker-compose logs -f api
```

### **Rebuild After Dependency Changes:**
```bash
docker-compose down
docker-compose build --no-cache
```

## 🎯 **Key Benefits**

1. **No local dependencies** - Everything runs in Docker
2. **Consistent environments** - All team members have identical setups
3. **Data persistence** - Database survives all rebuilds
4. **Easy dependency management** - Just rebuild when dependencies change
5. **Hot reloading** - Source code changes still work instantly

## 🚨 **Important Notes**

- **Always use `--no-cache`** when dependencies might have changed
- **Your database data is safe** - It's stored in Docker volumes
- **No local `npm install`** needed anymore
- **Source code changes** still hot-reload instantly
- **Dependency changes** require container rebuild

## 🔍 **Troubleshooting**

### **If something breaks:**
```bash
# Check container status
docker-compose ps

# View logs
docker-compose logs -f

# Rebuild everything
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

### **If database issues:**
```bash
# Check database volume
docker volume ls | grep postgres

# Database is safe in the volume!
```

## 📞 **Need Help?**

- Check container logs: `docker-compose logs -f`
- Verify containers are running: `docker-compose ps`
- Rebuild if needed: `docker-compose build --no-cache`
- Your database data is always safe in Docker volumes!

---

## 🏗️ **Development vs Production**

### **File Structure**
```
maple_key_music_academy_docker/
├── docker-compose.yaml          # ← DEVELOPMENT (use this locally)
├── docker-compose.prod.yaml     # ← PRODUCTION (GitHub Actions uses this)
├── .envs/
│   ├── env.dev                  # Local credentials (gitignored)
│   └── env.prod                 # Production (NOT used - GitHub Secrets instead)
└── nginx/
    ├── Dockerfile.dev           # Development proxy config
    └── Dockerfile.prod          # Production proxy config

../maple-key-music-academy-frontend/
├── Dockerfile                   # ← PRODUCTION (builds optimized static files)
└── Dockerfile.dev               # ← DEVELOPMENT (runs Vite dev server)
```

### **Development (Local Testing)**
```bash
# Uses: docker-compose.yaml + Dockerfile.dev
docker compose up

# What runs:
# - Frontend: Vite dev server (hot reload) on port 5173
# - Backend: Django runserver (auto-reload) on port 8000
# - Database: PostgreSQL exposed on port 5432
# - Nginx: Proxies everything on port 8000

# Access:
# http://localhost:5173 - Direct frontend (fastest)
# http://localhost:8000 - Through Nginx proxy
```

### **Production (GitHub Actions Deployment)**
```bash
# Uses: docker-compose.prod.yaml + Dockerfile
docker compose -f docker-compose.prod.yaml up -d

# What runs:
# - Frontend: Nginx serving built files (optimized)
# - Backend: Gunicorn WSGI server (production-ready)
# - Database: PostgreSQL (internal only, not exposed)
# - Nginx: Proxies everything

# This runs automatically on production server when you:
# 1. Merge to 'production' branch
# 2. GitHub Actions builds images
# 3. Deploys to Digital Ocean droplet
```

### **Key Differences**

| Feature | Development | Production |
|---------|------------|------------|
| **Command** | `docker compose up` | `docker compose -f docker-compose.prod.yaml up` |
| **Frontend** | Vite dev server (Dockerfile.dev) | Nginx serving static files (Dockerfile) |
| **Backend** | Django runserver | Gunicorn |
| **Hot Reload** | ✅ Yes | ❌ No |
| **Source Maps** | ✅ Yes | ❌ No |
| **Database** | Exposed port 5432 | Internal only |
| **Deploy** | Manual (`docker compose up`) | Auto (GitHub Actions) |

### **Why Two Setups?**

**Development needs:**
- Fast feedback (hot reload)
- Easy debugging (source maps)
- Quick iterations

**Production needs:**
- Optimized builds (minified/compressed)
- Security (no exposed DB, DEBUG=False)
- Reliability (Gunicorn, not runserver)

---

## 🚀 **Quick Command Reference**

### **Development (You)**
```bash
# Start local development
docker compose up

# Rebuild after dependency changes
docker compose down && docker compose up --build

# View logs
docker compose logs -f frontend
docker compose logs -f api
```

### **Production (GitHub Actions)**
```bash
# You don't run these - GitHub Actions does!
# But for reference:
docker compose -f docker-compose.prod.yaml up -d
docker compose -f docker-compose.prod.yaml down
```

### **Deployment Workflow**
```bash
# 1. Develop locally
docker compose up

# 2. Commit changes
git add .
git commit -m "Add feature"
git push origin develop

# 3. Create PRs
# develop → main (code review)
# main → production (triggers deployment)

# 4. GitHub Actions automatically:
# - Builds production images
# - Pushes to Docker Hub
# - SSHs into server
# - Runs docker-compose.prod.yaml
```

---

**Happy coding! 🎵**