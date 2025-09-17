# Maple Key Music Academy - Docker Configuration

This repository contains the Docker configuration for the Maple Key Music Academy application.

## 🐳 What's Included

- **Docker Compose files** for development and production environments
- **Nginx configuration** with SSL support and reverse proxy setup
- **Environment configuration templates** for secure deployment
- **Multi-stage Dockerfiles** for optimized builds

## 📁 Repository Structure

```
maple_key_music_academy_docker/
├── docker-compose.yaml          # Development environment
├── docker-compose.prod.yaml     # Production environment
├── nginx/
│   ├── default.conf             # Nginx configuration
│   ├── Dockerfile.dev           # Development Nginx image
│   └── Dockerfile.prod          # Production Nginx image
├── .envs/
│   ├── env.dev.example          # Development environment template
│   └── env.prod.example         # Production environment template
└── README.md                    # This file
```

## 🚀 Quick Start

### 1. Clone and Setup

```bash
git clone git@github.com:alueddeke/maple_key_music_academy_docker.git
cd maple_key_music_academy_docker
```

### 2. Configure Environment

```bash
# Copy environment templates
cp .envs/env.dev.example .envs/env.dev
cp .envs/env.prod.example .envs/env.prod

# Edit the files with your actual values
nano .envs/env.dev
nano .envs/env.prod
```

### 3. Development Setup

```bash
# Start development environment
docker-compose up -d

# View logs
docker-compose logs -f

# Stop environment
docker-compose down
```

### 4. Production Deployment

```bash
# Start production environment
docker-compose -f docker-compose.prod.yaml up -d

# View logs
docker-compose -f docker-compose.prod.yaml logs -f

# Stop environment
docker-compose -f docker-compose.prod.yaml down
```

## 🔧 Configuration

### Environment Variables

The application uses environment variables for configuration. Key variables include:

- **Database**: PostgreSQL connection settings
- **Django**: Secret key, debug mode, allowed hosts
- **OAuth**: Google OAuth client credentials
- **Frontend**: API URLs and app configuration

### Nginx Configuration

The Nginx setup includes:
- Reverse proxy to Django backend
- Static file serving
- SSL termination (production)
- Gzip compression
- Security headers

## 🔒 Security

- Environment files with secrets are gitignored
- Example files provided for easy setup
- Production configuration includes security headers
- SSL/TLS support for production deployments

## 📝 Notes

- Make sure to replace all placeholder values in environment files
- The production setup assumes SSL certificates are available
- Database data persists in Docker volumes
- Logs are available through Docker Compose

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with both development and production configurations
5. Submit a pull request

## 📞 Support

For questions or issues, please contact the development team or create an issue in the repository.
