#!/bin/bash
# ==============================================
# 增强版一键部署 N8N ARM + Cloudflare DNS HTTPS + 用户认证 + 自动续签
# 域名固定: n8n.aihelp.work
# ==============================================

set -e

echo "开始增强版部署 n8n (ARM) + Nginx + HTTPS + 用户认证 ..."

# ------------------------------
# 1. 安装必要软件
# ------------------------------
apt update
apt install -y curl wget git sudo nginx docker.io docker-compose certbot python3-certbot-dns-cloudflare
systemctl enable docker
systemctl start docker

# ------------------------------
# 2. 提示输入 Cloudflare API Token
# ------------------------------
read -p "请输入 Cloudflare API Token（用于自动签发证书）: " CF_API_TOKEN
CF_API_FILE="/home/n8n/certbot/cloudflare.ini"
mkdir -p $(dirname $CF_API_FILE)
cat > $CF_API_FILE <<EOF
dns_cloudflare_api_token = $CF_API_TOKEN
EOF
chmod 600 $CF_API_FILE

# ------------------------------
# 3. 提示用户设置 n8n 登录用户名和密码
# ------------------------------
read -p "请设置 n8n 登录用户名: " N8N_USER
read -s -p "请设置 n8n 登录密码: " N8N_PASSWORD
echo ""

# ------------------------------
# 4. 创建 n8n 数据目录并修复权限
# ------------------------------
N8N_DATA="/home/n8n"
mkdir -p $N8N_DATA
chown -R 1000:1000 $N8N_DATA

# ------------------------------
# 5. 自动识别 ARM 架构
# ------------------------------
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
  N8N_IMAGE="n8nio/n8n:arm64"
else
  N8N_IMAGE="n8nio/n8n"
fi
docker pull $N8N_IMAGE

# ------------------------------
# 6. Docker Compose 文件
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
# 7. Nginx 配置文件
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
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# ------------------------------
# 8. 启动容器
# ------------------------------
docker-compose up -d

# ------------------------------
# 9. Cloudflare DNS 验证申请 HTTPS
# ------------------------------
echo "申请 HTTPS 证书..."
docker run -it --rm \
  -v $(pwd)/certbot/conf:/etc/letsencrypt \
  -v $(pwd)/certbot/www:/var/www/certbot \
  -v $(pwd)/certbot/cloudflare.ini:/etc/letsencrypt/cloudflare.ini:ro \
  certbot/certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  -d $DOMAIN \
  --agree-tos --email your-email@example.com --non-interactive

docker exec nginx_n8n nginx -s reload

# ------------------------------
# 10. 自动续签脚本
# ------------------------------
cat > /home/n8n/renew_cert.sh <<'EOF'
#!/bin/bash
docker run -it --rm \
  -v /home/n8n/certbot/conf:/etc/letsencrypt \
  -v /home/n8n/certbot/www:/var/www/certbot \
  -v /home/n8n/certbot/cloudflare.ini:/etc/letsencrypt/cloudflare.ini:ro \
  certbot/certbot renew \
  --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  --pre-hook "docker-compose stop nginx" \
  --post-hook "docker-compose start nginx"
EOF
chmod +x /home/n8n/renew_cert.sh

# ------------------------------
# 11. 设置 Cron 每 2 天检查证书
# ------------------------------
(crontab -l 2>/dev/null; echo "0 3 */2 * * /home/n8n/renew_cert.sh >> /home/n8n/renew_cert.log 2>&1") | crontab -

# ------------------------------
# 12. 输出访问与管理指南
# ------------------------------
cat <<EOL

==================== 部署完成 ====================

访问网址: https://$DOMAIN
n8n 登录用户名: $N8N_USER
n8n 登录密码: 你设置的密码

证书自动续签脚本: /home/n8n/renew_cert.sh
Cron 每 2 天自动检查一次证书，续签成功后自动重启 Nginx

管理命令示例:
  查看容器: docker ps
  启动容器: docker-compose up -d
  重启 n8n: docker restart n8n
  手动续签证书: /home/n8n/renew_cert.sh

=================================================

EOL

docker ps
