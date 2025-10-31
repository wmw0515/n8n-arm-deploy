#!/bin/bash
# ==========================================
# N8N ARM 完整部署脚本（智能 Cloudflare 证书 + Python 虚拟环境 + systemd 开机自启）
# ==========================================
set -e

# ----------------------------
# 用户交互输入
# ----------------------------
read -p "请输入你的 Cloudflare API Token（推荐）: " CF_API_TOKEN
read -p "请输入 N8N 登录用户名: " N8N_USER
read -s -p "请输入 N8N 登录密码: " N8N_PASSWORD
echo

# ----------------------------
# 系统更新与依赖安装
# ----------------------------
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release sudo python3-pip python3-venv unzip

# ----------------------------
# 安装 Docker 必要组件
# ----------------------------
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker

# ----------------------------
# N8N 数据卷
# ----------------------------
sudo mkdir -p /home/node/.n8n
sudo chown -R 1000:1000 /home/node/.n8n

# ----------------------------
# Python 虚拟环境安装 Certbot
# ----------------------------
ENV_DIR="$HOME/n8n-env"
if [ ! -d "$ENV_DIR" ]; then
    python3 -m venv "$ENV_DIR"
    echo "虚拟环境已创建: $ENV_DIR"
fi
source "$ENV_DIR/bin/activate"
pip install --upgrade pip
pip install --upgrade certbot certbot-dns-cloudflare

# ----------------------------
# Docker Compose 配置
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

cd /home/node
docker compose -f n8n-docker-compose.yml up -d

# ----------------------------
# 安装 Nginx 反代
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
# Cloudflare API Token 配置
# ----------------------------
mkdir -p /home/node/.secrets/certbot
API_TOKEN_SUPPORTED=false
python3 - <<EOF
try:
    import certbot_dns_cloudflare
    import pkg_resources
    v = pkg_resources.get_distribution('certbot-dns-cloudflare').version
    major = int(v.split('.')[0])
    if major >= 1:
        exit(0)
    else:
        exit(1)
except:
    exit(1)
EOF
if [ $? -eq 0 ]; then
    API_TOKEN_SUPPORTED=true
fi

if [ "$API_TOKEN_SUPPORTED" = true ]; then
    echo "使用 API Token 配置 Cloudflare 证书"
    cat > /home/node/.secrets/certbot/cloudflare.ini <<EOF
dns_cloudflare_api_token=${CF_API_TOKEN}
EOF
else
    echo "当前系统或插件版本不支持 API Token"
    read -p "请输入你的 Cloudflare 账户邮箱: " CF_EMAIL
    read -p "请输入你的 Cloudflare Global API Key: " CF_GLOBAL_KEY
    cat > /home/node/.secrets/certbot/cloudflare.ini <<EOF
dns_cloudflare_email=${CF_EMAIL}
dns_cloudflare_api_key=${CF_GLOBAL_KEY}
EOF
fi
chmod 600 /home/node/.secrets/certbot/cloudflare.ini

# ----------------------------
# 申请证书（虚拟环境内执行）
# ----------------------------
source "$ENV_DIR/bin/activate"
certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /home/node/.secrets/certbot/cloudflare.ini \
  -d n8n.aihelp.work \
  --non-interactive \
  --agree-tos \
  --email your-email@example.com

# ----------------------------
# 配置 Nginx SSL
# ----------------------------
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
# Cron 每2天检查证书
# ----------------------------
(crontab -l 2>/dev/null; echo "0 3 */2 * * source $ENV_DIR/bin/activate && certbot renew --quiet && systemctl reload nginx") | crontab -

# ----------------------------
# 创建 systemd 服务，实现开机自启
# ----------------------------
SERVICE_FILE="/etc/systemd/system/n8n.service"
sudo tee $SERVICE_FILE > /dev/null <<EOF
[Unit]
Description=N8N Workflow Automation
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=$USER
WorkingDirectory=/home/node
ExecStart=/bin/bash -c 'source $ENV_DIR/bin/activate && docker compose -f /home/node/n8n-docker-compose.yml up'
ExecStop=/bin/bash -c 'docker compose -f /home/node/n8n-docker-compose.yml down'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable n8n.service
sudo systemctl start n8n.service

echo "部署完成！虚拟环境路径: $ENV_DIR"
echo "N8N 用户名和密码已设置，可直接登录 N8N UI。"
echo "N8N 已配置为 systemd 服务开机自启：sudo systemctl status n8n.service 查看状态"
