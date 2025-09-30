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

**Happy coding! 🎵**