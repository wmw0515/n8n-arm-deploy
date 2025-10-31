#!/bin/bash
# ==============================================
# 增强版一键部署 N8N ARM + Cloudflare DNS HTTPS + 用户认证 + 自动续签
# 使用 Docker 官方安装方式，避免 docker.io 依赖问题
# 域名固定: n8n.aihelp.work
# ==============================================

set -e

echo "开始增强版部署 n8n (ARM) + Nginx + HTTPS + 用户认证 ..."

# ------------------------------
# 1. 安装必要软件（不安装 docker.io）
# ------------------------------
apt update
apt install -y curl wget git sudo nginx certbot python3-certbot-dns-cloudflare lsb-release gnupg ca-certificates

# ------------------------------
# 2. 安装官方 Docker（支持 ARM）
# ------------------------------
echo "安装 Docker 官方版本..."
curl -fsSL https://get.docker.com | sh

# 启动 Docker 并开机自启
systemctl enable docker
systemctl start docker

# 安装 Docker Compose 插件
docker compose version >/dev/null 2>&1 || curl -SL https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-linux-$(uname -m) -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose

# ------------------------------
# 3. 提示输入 Cloudflare API Token
# ------------------------------
read -p "请输入 Cloudflare API Token（用于自动签发证书）: " CF_API_TOKEN
CF_API_FILE="/home/n8n/certbot/cloudflare.ini"
mkdir -p $(dirname $CF_API_FILE)
cat > $CF_API_FILE <<EOF
dns_cloudflare_api_token = $CF_API_TOKEN
EOF
chmod 600 $CF_API_FILE

# ------------------------------
# 4. 提示用户设置 n8n 登录用户名和密码
# ------------------------------
read -p "请设置 n8n 登录用户名: " N8N_USER
read -s -p "请设置 n8n 登录密码: " N8N_PASSWORD
echo ""

# ------------------------------
# 5. 创建 n8n 数据目录并修复权限
# ------------------------------
N8N_DATA="/home/n8n"
mkdir -p $N8N_DATA
chown -R 1000:1000 $N8N_DATA

# ------------------------------
# 6. 自动识别 ARM 架构
# ------------------------------
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
  N8N_IMAGE="n8nio/n8n:arm64"
else
  N8N_IMAGE="n8nio/n8n"
fi
docker pull $N8N_IMAGE

# ------------------------------
# 7. Docker Compose 文件
# ------------------------------
DOMAIN="n8n.aihelp.work"
mkdir -p certbot/conf certbot/www

cat > docker-compose.yml <<EOF
version: "3"

services:
  n8n:
    image: $N8N_IMAGE
    container_name: n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=$DOMAIN
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=$N8N_USER
      - N8N_BASIC_AUTH_PASSWORD=$N8N_PASSWORD
    volumes:
      - $N8N_DATA:/home/node/.n8n

  nginx:
    image: nginx:stable-alpine
    container_name: nginx_n8n
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
EOF

# ------------------------------
# 8. Nginx 配置文件
# ------------------------------
cat > nginx.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        proxy_pass http://n8n:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_he
