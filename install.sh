#!/bin/bash
# ==========================================
# N8N ARM 完整部署脚本（最终版）
# 支持 ARM 服务器，Docker 必要组件安装
# N8N 数据卷权限修复 + Nginx 反代 + Cloudflare HTTPS
# 支持输入 N8N 登录用户名和密码
# ==========================================

set -e

# ----------------------------
# 用户交互输入
# ----------------------------
read -p "请输入你的 Cloudflare API Token: " CF_API_TOKEN
read -p "请输入 N8N 登录用户名: " N8N_USER
read -s -p "请输入 N8N 登录密码: " N8N_PASSWORD
echo

# ----------------------------
# 更新系统并安装必要工具
# ----------------------------
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release sudo

# ----------------------------
# 安装 Docker（仅必要组件）
# ----------------------------
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

sudo systemctl enable docker
sudo systemctl start docker

# ----------------------------
# 创建 N8N 数据卷并修复权限
# ----------------------------
sudo mkdir -p /home/node/.n8n
sudo chown -R 1000:1000 /home/node/.n8n

# ----------------------------
# 创建 Docker Compose 文件
# ----------------------------
cat > /home/node/n8n-docker-compose.yml <<EOF
version: "3.8"
services:
  n8n:
    image: n8nio/n8n
    restart: always
    ports:
      - "5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
      - N8N_HOST=n8n.aihelp.work
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - GENERIC_TIMEZONE=Asia/Shanghai
    volumes:
      - /home/node/.n8n:/home/node/.n8n
EOF

# ----------------------------
# 启动 N8N
# ----------------------------
cd /home/node
docker compose -f n8n-docker-compose.yml up -d

# ----------------------------
# 安装 Nginx 并配置反代
# ----------------------------
sudo apt-get install -y nginx
cat > /etc/nginx/sites-available/n8n <<EOF
server {
    listen 80;
    server_name n8n.aihelp.work;

    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# ----------------------------
# 安装 Certbot (Cloudflare DNS)
# ----------------------------
sudo apt-get install -y certbot python3-certbot-dns-cloudflare

# 创建 Cloudflare 配置文件
mkdir -p /home/node/.secrets/certbot
cat > /home/node/.secrets/certbot/cloudflare.ini <<EOF
dns_cloudflare_api_token = ${CF_API_TOKEN}
EOF
chmod 600 /home/node/.secrets/certbot/cloudflare.ini

# ----------------------------
# 获取证书并自动续签
# ----------------------------
certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /home/node/.secrets/certbot/cloudflare.ini \
  -d n8n.aihelp.work \
  --non-interactive \
  --agree-tos \
  --email your-email@example.com

# 配置 Nginx SSL
cat > /etc/nginx/sites-available/n8n_ssl <<EOF
server {
    listen 80;
    server_name n8n.aihelp.work;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name n8n.aihelp.work;

    ssl_certificate /etc/letsencrypt/live/n8n.aihelp.work/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/n8n.aihelp.work/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/n8n_ssl /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# ----------------------------
# 设置 cron 每2天检查一次证书
# ----------------------------
(crontab -l 2>/dev/null; echo "0 3 */2 * * certbot renew --quiet && systemctl reload nginx") | crontab -

echo "部署完成！N8N 用户名和密码已设置，可直接登录 N8N UI。"
