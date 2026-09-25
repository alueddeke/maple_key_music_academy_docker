#!/usr/bin/env bash
# 14 — nginx: the container nginx in front of the backend, then the host
# nginx + certbot + ufw (idempotent — config files and certificates are
# created only when absent).
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
require_deploy_env

# Swap nginx (backend is healthy, safe to briefly interrupt nginx)
docker stop nginx 2>/dev/null || true
docker rm nginx 2>/dev/null || true

rm -rf /tmp/nginx.conf
cat > /tmp/nginx.conf << 'EOF'
server {
    listen 80;
    server_name _;
    client_max_body_size 10M;

    # Serve static files
    location /static/ {
        alias /usr/share/nginx/html/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # Serve media files
    location /media/ {
        alias /usr/share/nginx/html/media/;
        expires 30d;
    }

    # Proxy all other requests to Django
    location / {
        proxy_pass http://maple-key-backend:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        # Preserve X-Forwarded-Proto from Host Nginx (if set), otherwise use $scheme
        # This allows SSL termination at Host Nginx to work correctly
        proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
        proxy_redirect off;
        proxy_buffering off;
        proxy_next_upstream error timeout invalid_header http_502 http_503;
    }

    error_page 503 @maintenance;
    location @maintenance {
        default_type application/json;
        return 503 '{"error": "service_unavailable", "message": "Backend is starting up or unhealthy. Please retry shortly."}';
    }
}
EOF

docker run -d \
  --name nginx \
  --restart unless-stopped \
  --network maple-key-network \
  -p 8000:80 \
  -v /tmp/nginx.conf:/etc/nginx/conf.d/default.conf:ro \
  -v static_volume:/usr/share/nginx/html/static:ro \
  nginx:alpine

# ===== SETUP HOST NGINX =====
echo "Setting up host Nginx..."

# Install Nginx if not already installed
if ! command -v nginx &> /dev/null; then
  echo "Installing Nginx..."
  sudo apt update
  sudo apt install -y nginx
fi

# Install Certbot for SSL certificates
if ! command -v certbot &> /dev/null; then
  echo "Installing Certbot..."
  sudo apt update
  sudo apt install -y certbot python3-certbot-nginx
fi

# Enable and start Nginx
sudo systemctl enable nginx
sudo systemctl start nginx

# Create Nginx configuration for api.maplekeymusic.com (only if it doesn't exist)
# Note: Certbot will automatically add SSL configuration and HTTPS redirect
# We don't overwrite if file exists to preserve SSL config
if [ ! -f /etc/nginx/sites-available/api.maplekeymusic.com ]; then
  sudo tee /etc/nginx/sites-available/api.maplekeymusic.com > /dev/null <<'NGINX_EOF'
server {
    listen 80;
    server_name api.maplekeymusic.com;
    client_max_body_size 10M;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_redirect off;

        # WebSocket support (if needed in the future)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX_EOF
fi

# Enable the site
sudo ln -sf /etc/nginx/sites-available/api.maplekeymusic.com /etc/nginx/sites-enabled/

# Remove default site if it exists
sudo rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx

# ===== SETUP SSL WITH CERTBOT =====
echo "Setting up SSL certificate..."

# Check if certificate already exists
if ! sudo certbot certificates 2>/dev/null | grep -q "api.maplekeymusic.com"; then
  echo "Obtaining new SSL certificate from Let's Encrypt..."
  sudo certbot --nginx \
    --non-interactive \
    --agree-tos \
    --redirect \
    --email "$CERTBOT_EMAIL" \
    -d api.maplekeymusic.com
  echo "✅ SSL certificate obtained and configured!"
else
  echo "SSL certificate already exists. Checking for renewal..."
  sudo certbot renew --quiet
  echo "✅ SSL certificate is up to date!"
fi

# Configure firewall
sudo ufw allow 80/tcp || true
sudo ufw allow 443/tcp || true

echo "✅ Host Nginx configured for api.maplekeymusic.com"
