#!/bin/bash
# ============================================================
#  N8N 一键部署脚本 for Oracle Cloud ARM (Ubuntu 22.04)
#  支持 Cloudflare DNS-01 自动申请和续签证书
# ============================================================

echo "🚀 欢迎使用 N8N 一键部署脚本（Cloudflare DNS-01 支持）"

# 输入域名
read -p "请输入你的域名（例：www.aihelp.work）： " DOMAIN

# 输入 Cloudflare API Token
read -s -p "请输入 Cloudflare API Token（仅需 Zone.DNS 权限）： " CF_TOKEN
echo

# 输入 N8N 用户名和密码
read -p "请输入 n8n 登录用户名： " USERNAME
read -s -p "请输入 n8n 登录密码： " PASSWORD
echo

# 保存 Cloudflare API Token
mkdir -p ~/.secrets/certbot
CF_CREDENTIALS=~/.secrets/certbot/cloudflare.ini
echo "dns_cloudflare_api_token = $CF_TOKEN" > $CF_CREDENTIALS
chmod 600 $CF_CREDENTIALS

# 系统更新
sudo apt update && sudo apt upgrade -y

# 安装 Docker & Docker Compose
sudo apt install -y ca-certificates curl gnupg lsb-release
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable docker --now

# 安装 Nginx
sudo apt install -y nginx
sudo ufw allow 'Nginx Full'

# 安装 Certbot 和 Cloudflare 插件
sudo apt install -y certbot python3-certbot-dns-cloudflare

# 申请证书
sudo certbot certonly --dns-cloudflare --dns-cloudflare-credentials $CF_CREDENTIALS \
  -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN

# 配置 Nginx
cat <<EOF | sudo tee /etc/nginx/sites-available/n8n
server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        proxy_pass http://localhost:5678/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}

server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
EOF

sudo ln -s /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/ 2>/dev/null
sudo nginx -t && sudo systemctl reload nginx

# 部署 N8N Docker 容器
mkdir -p ~/n8n && cd ~/n8n
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  n8n:
    image: n8nio/n8n
    container_name: n8n
    restart: always
    ports:
      - "5678:5678"
    environment:
      - WEBHOOK_URL=https://$DOMAIN/
      - N8N_HOST=$DOMAIN
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=$USERNAME
      - N8N_BASIC_AUTH_PASSWORD=$PASSWORD
      - GENERIC_TIMEZONE=Asia/Shanghai
    volumes:
      - ./n8n_data:/home/node/.n8n
EOF

sudo docker compose up -d

# 自动续签证书 Cron
(crontab -l 2>/dev/null; echo "0 2 * * * certbot renew --dns-cloudflare --dns-cloudflare-credentials $CF_CREDENTIALS --quiet && systemctl reload nginx") | crontab -

echo "✅ N8N 部署完成！访问：https://$DOMAIN"
