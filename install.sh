#!/bin/bash
# ==========================================
# N8N ARM 完整部署脚本（最终稳定版）
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
# 系统更新与依赖
# ----------------------------
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release sudo python3-pip python3-venv lsof build-essential libffi-dev libssl-dev

# 卸载系统旧版 pyOpenSSL 避免冲突
sudo python3 -m pip uninstall -y pyOpenSSL cryptography cffi || true

# ----------------------------
# 安装 Docker
# ----------------------------
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker

# ----------------------------
# 检查端口 5678 是否被占用
# ----------------------------
N8N_PORT_HOST=5678
if lsof -i:${N8N_PORT_HOST} >/dev/null 2>&1; then
    echo "[WARN] 端口 ${N8N_PORT_HOST} 被占用，尝试清理 Docker 容器和进程..."
    containers=$(docker ps -a --filter "publish=${N8N_PORT_HOST}" --format "{{.ID}}")
    if [ -n "$containers" ]; then
        echo "[INFO] 停止并删除占用端口的容器: $containers"
        docker stop $containers || true
        docker rm $containers || true
    fi
    sudo fuser -k ${N8N_PORT_HOST}/tcp || true
    sleep 1
    if lsof -i:${N8N_PORT_HOST} >/dev/null 2>&1; then
        echo "[INFO] 端口 5678 不可用，使用 5679 端口"
        N8N_PORT_HOST=5679
        lsof -i:${N8N_PORT_HOST} >/dev/null 2>&1 && { echo "[ERROR] 端口 5679 也被占用，无法安装 N8N"; exit 1; }
    fi
fi
echo "[INFO] N8N 宿主机端口: ${N8N_PORT_HOST}"

# ----------------------------
# N8N 数据卷
# ----------------------------
sudo mkdir -p /home/node/.n8n
sudo chown -R 1000:1000 /home/node/.n8n

# ----------------------------
# Docker Compose 配置（修正 YAML 语法）
# ----------------------------
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
# 安装 Nginx 反代
# ----------------------------
sudo apt-get install -y nginx
cat > /etc/nginx/sites-available/n8n <<EOF
server {
    listen 80;
    server_name n8n.aihelp.work;

    location / {
        proxy_pass http://127.0.0.1:${N8N_PORT_HOST};
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
# Certbot 虚拟环境
# ----------------------------
python3 -m venv /home/node/n8n-env
source /home/node/n8n-env/bin/activate
pip install --upgrade pip setuptools wheel
pip install certbot certbot-dns-cloudflare pyOpenSSL cryptography cffi

mkdir -p /home/node/.secrets/certbot

# ----------------------------
# 配置 Cloudflare
# ----------------------------
API_TOKEN_SUPPORTED=false
python3 - <<EOF
import warnings
warnings.filterwarnings("ignore", category=DeprecationWarning)
try:
    import certbot_dns_cloudflare
    import pkg_resources
    try:
        v = pkg_resources.get_distribution('certbot-dns-cloudflare').version
        major = int(v.split('.')[0])
        if major >= 1:
            exit(0)
        else:
            exit(0)  # 避免警告导致退出
    except Exception:
        exit(0)
except Exception:
    exit(1)
EOF

if [ $? -eq 0 ]; then
    API_TOKEN_SUPPORTED=true
fi

if [ "$API_TOKEN_SUPPORTED" = true ]; then
    echo "使用 API Token 配置 Cloudflare 证书"
    cat > /home/node/.secrets/certbot/cloudflare.ini <<EOF
dns_cloudflare_api_token = ${CF_API_TOKEN}
EOF
else
    echo "当前系统或插件版本不支持 API Token"
    read -p "请输入你的 Cloudflare 账户邮箱: " CF_EMAIL
    read -p "请输入你的 Cloudflare Global API Key: " CF_GLOBAL_KEY
    cat > /home/node/.secrets/certbot/cloudflare.ini <<EOF
dns_cloudflare_email = ${CF_EMAIL}
dns_cloudflare_api_key = ${CF_GLOBAL_KEY}
EOF
fi
chmod 600 /home/node/.secrets/certbot/cloudflare.ini

# ----------------------------
# 申请证书（虚拟环境 Certbot）
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
# Cron 每2天检查证书
# ----------------------------
(crontab -l 2>/dev/null; echo "0 3 */2 * * /home/node/n8n-env/bin/certbot renew --quiet && systemctl reload nginx") | crontab -

echo "部署完成！N8N 用户名和密码已设置，可直接登录 N8N UI。"
echo "N8N 宿主机端口: ${N8N_PORT_HOST}"
