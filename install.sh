#!/bin/bash
# ==========================================
# N8N ARM 干净部署脚本（端口健康检查 + Cloudflare SSL + 自动重试）
# ==========================================
set -e

# ----------------------------
# 用户输入
# ----------------------------
read -p "请输入你的 Cloudflare API Token（推荐）: " CF_API_TOKEN
read -p "请输入 N8N 登录用户名: " N8N_USER
read -s -p "请输入 N8N 登录密码: " N8N_PASSWORD
echo

# ----------------------------
# 清理旧环境
# ----------------------------
echo "[INFO] 清理旧 Docker 容器和端口占用..."
docker ps -a --filter "ancestor=n8nio/n8n" --format "{{.ID}}" | xargs -r docker stop || true
docker ps -a --filter "ancestor=n8nio/n8n" --format "{{.ID}}" | xargs -r docker rm || true
sudo fuser -k 5678/tcp || true
sudo fuser -k 5679/tcp || true
sudo rm -f /etc/nginx/sites-enabled/n8n /etc/nginx/sites-enabled/n8n_ssl
sudo rm -f /etc/nginx/sites-available/n8n /etc/nginx/sites-available/n8n_ssl
sudo rm -rf /home/node/.n8n
sudo mkdir -p /home/node/.n8n
sudo chown -R 1000:1000 /home/node/.n8n
sudo rm -rf /home/node/n8n-docker-compose.yml
sudo rm -rf /home/node/.secrets/certbot

# ----------------------------
# 系统更新与依赖
# ----------------------------
echo "[INFO] 更新系统和安装依赖..."
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release sudo python3-pip python3-venv lsof build-essential libffi-dev libssl-dev nginx

# ----------------------------
# 安装 Docker
# ----------------------------
echo "[INFO] 安装 Docker..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker

# ----------------------------
# 检查端口
# ----------------------------
N8N_PORT_HOST=5678
if lsof -i:${N8N_PORT_HOST} >/dev/null 2>&1; then
    echo "[WARN] 端口 ${N8N_PORT_HOST} 被占用，使用 5679 端口"
    N8N_PORT_HOST=5679
fi
echo "[INFO] N8N 宿主机端口: ${N8N_PORT_HOST}"

# ----------------------------
# Docker Compose 配置
# ----------------------------
echo "[INFO] 生成 Docker Compose 配置..."
cat > /home/node/n8n-docker-compose.yml <<EOF
services:
  n8n:
    image: n8nio/n8n
    restart: always
    ports:
      - "${N8N_PORT_HOST}:5678"
    environment:
      N8N_BASIC_AUTH_ACTIVE: "true"
      N8N_BASIC_AUTH_USER: "${N8N_USER}"
      N8N_BASIC_AUTH_PASSWORD: "${N8N_PASSWORD}"
      N8N_HOST: "n8n.aihelp.work"
      N8N_PORT: "5678"
      N8N_PROTOCOL: "https"
      NODE_ENV: "production"
      GENERIC_TIMEZONE: "Asia/Shanghai"
    volumes:
      - /home/node/.n8n:/home/node/.n8n
EOF

cd /home/node
docker compose -f n8n-docker-compose.yml up -d

# ----------------------------
# 等待 N8N 容器启动（端口检查 + 自动重试）
# ----------------------------
echo "[INFO] 等待 N8N 容器启动..."
max_retries=30
retry_interval=2
attempt=0

while true; do
    # 检查宿主机端口是否已经监听
    if lsof -i:${N8N_PORT_HOST} >/dev/null 2>&1; then
        echo "[INFO] N8N 容器已启动成功，端口 ${N8N_PORT_HOST} 已监听"
        break
    else
        attempt=$((attempt+1))
        echo "[WARN] N8N 容器还未启动，等待中... (${attempt}/${max_retries})"
        sleep $retry_interval
        if [ $attempt -ge $max_retries ]; then
            echo "[ERROR] N8N 容器启动超时，重启 Docker Compose..."
            docker compose -f /home/node/n8n-docker-compose.yml down
            docker compose -f /home/node/n8n-docker-compose.yml up -d
            attempt=0
            sleep 5
        fi
    fi
done

# ----------------------------
# 安装 Certbot 并配置 Cloudflare
# ----------------------------
echo "[INFO] 安装 Certbot 并配置 Cloudflare..."
python3 -m venv /home/node/n8n-env
source /home/node/n8n-env/bin/activate
pip install --upgrade pip setuptools wheel
pip install certbot certbot-dns-cloudflare pyOpenSSL cryptography cffi
mkdir -p /home/node/.secrets/certbot
cat > /home/node/.secrets/certbot/cloudflare.ini <<EOF
dns_cloudflare_api_token = ${CF_API_TOKEN}
EOF
chmod 600 /home/node/.secrets/certbot/cloudflare.ini

# ----------------------------
# 申请 SSL 证书
# ----------------------------
/home/node/n8n-env/bin/certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /home/node/.secrets/certbot/cloudflare.ini \
  -d n8n.aihelp.work \
  --non-interactive \
  --agree-tos \
  --email your-email@example.com
deactivate

# ----------------------------
# 配置 Nginx SSL
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
        proxy_pass http://127.0.0.1:${N8N_PORT_HOST};
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
# Cron 自动续期证书
# ----------------------------
(crontab -l 2>/dev/null; echo "0 3 */2 * * /home/node/n8n-env/bin/certbot renew --quiet && systemctl reload nginx") | crontab -

echo "[INFO] 部署完成！N8N 用户名和密码已设置，可直接登录 N8N UI。"
echo "[INFO] N8N 宿主机端口: ${N8N_PORT_HOST}"
