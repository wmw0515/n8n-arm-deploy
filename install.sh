#!/bin/bash
# ==========================================
# N8N ARM 完整部署脚本（无人值守）
# ==========================================
set -e

# ----------------------------
# 环境变量检查
# ----------------------------
: "${N8N_USER:?请先设置环境变量 N8N_USER}"
: "${N8N_PASSWORD:?请先设置环境变量 N8N_PASSWORD}"
: "${CF_API_TOKEN:?请先设置环境变量 CF_API_TOKEN}"

echo "==== 开始部署 N8N ===="

# ----------------------------
# 定义路径
# ----------------------------
N8N_DIR="$HOME/n8n"
SECRETS_DIR="$N8N_DIR/.secrets/certbot"
ENV_DIR="$HOME/n8n-env"

mkdir -p "$N8N_DIR/.n8n" "$SECRETS_DIR"
echo "[INFO] 创建数据卷和证书目录"

# ----------------------------
# 系统更新与依赖
# ----------------------------
echo "[INFO] 更新系统和安装依赖..."
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release sudo python3-pip python3-venv unzip nginx

# ----------------------------
# 安装 Docker
# ----------------------------
echo "[INFO] 安装 Docker..."
sudo mkdir -p /etc/apt/keyrings
sudo rm -f /etc/apt/keyrings/docker.gpg
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker
echo "[INFO] Docker 安装完成"

# ----------------------------
# Python 虚拟环境安装 Certbot
# ----------------------------
echo "[INFO] 创建 Python 虚拟环境并安装 Certbot..."
python3 -m venv "$ENV_DIR"
source "$ENV_DIR/bin/activate"
pip install --upgrade pip
pip install --upgrade certbot certbot-dns-cloudflare
echo "[INFO] Certbot 安装完成"

# ----------------------------
# Docker Compose 配置
# ----------------------------
echo "[INFO] 生成 Docker Compose 配置..."
cat > "$N8N_DIR/n8n-docker-compose.yml" <<EOF
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
      - $N8N_DIR/.n8n:/home/node/.n8n
EOF

# ----------------------------
# 启动 N8N Docker
# ----------------------------
echo "[INFO] 启动 N8N Docker 服务..."
cd "$N8N_DIR"
docker compose -f n8n-docker-compose.yml up -d
echo "[INFO] N8N Docker 服务已启动"

# ----------------------------
# Nginx 反代配置
# ----------------------------
echo "[INFO] 配置 Nginx 反代..."
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
echo "[INFO] Nginx 配置完成"

# ----------------------------
# Cloudflare API Token 配置
# ----------------------------
echo "[INFO] 写入 Cloudflare API Token..."
cat > "$SECRETS_DIR/cloudflare.ini" <<EOF
dns_cloudflare_api_token=${CF_API_TOKEN}
EOF
chmod 600 "$SECRETS_DIR/cloudflare.ini"

# ----------------------------
# 申请证书
# ----------------------------
echo "[INFO] 申请 SSL 证书..."
certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials "$SECRETS_DIR/cloudflare.ini" \
  -d n8n.aihelp.work \
  --non-interactive \
  --agree-tos \
  --email your-email@example.com || echo "[WARN] 证书申请失败，继续执行"
echo "[INFO] SSL 证书申请完成"

# ----------------------------
# Nginx SSL 配置
# ----------------------------
echo "[INFO] 配置 Nginx SSL..."
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
echo "[INFO] Nginx SSL 配置完成"

# ----------------------------
# Cron 自动续签
# ----------------------------
(crontab -l 2>/dev/null; echo "0 3 */2 * * source $ENV_DIR/bin/activate && certbot renew --quiet && systemctl reload nginx") | crontab -
echo "[INFO] Cron 自动续签任务已设置"

# ----------------------------
# systemd 服务
# ----------------------------
echo "[INFO] 创建 systemd 服务..."
SERVICE_FILE="/etc/systemd/system/n8n.service"
sudo tee $SERVICE_FILE >/dev/null <<EOF
[Unit]
Description=N8N Workflow Automation
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$N8N_DIR
ExecStart=/bin/bash -c 'source $ENV_DIR/bin/activate && docker compose -f $N8N_DIR/n8n-docker-compose.yml up'
ExecStop=/bin/bash -c 'docker compose -f $N8N_DIR/n8n-docker-compose.yml down'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable n8n.service
sudo systemctl start n8n.service
echo "[INFO] systemd 服务已创建并启动"

echo "==== N8N 部署完成 ===="
echo "虚拟环境路径: $ENV_DIR"
echo "N8N 用户名/密码已设置，可直接登录 N8N UI"
echo "查看服务状态: sudo systemctl status n8n.service"
