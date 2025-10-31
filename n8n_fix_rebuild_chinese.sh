#!/bin/bash
set -e

# ====== 配置 ======
N8N_DIR="$HOME/n8n"
N8N_IMAGE="n8nio/n8n:latest"
N8N_DATA_DIR="$HOME/.n8n"
N8N_PORT=5680  # 访问端口，可修改
N8N_USER="admin"
N8N_PASSWORD="yourpassword"  # 请自行修改为你的密码

# ====== 进入 n8n 目录 ======
echo "⬇️ 进入 n8n 目录: $N8N_DIR"
mkdir -p "$N8N_DIR"
cd "$N8N_DIR"

# ====== 备份旧文件 ======
if [ -f docker-compose.yml ]; then
    echo "💾 备份旧 docker-compose.yml"
    cp docker-compose.yml docker-compose.yml.bak.$(date +%Y%m%d%H%M%S)
fi

# ====== 修复数据目录权限 ======
echo "🛠️ 修复数据目录权限: $N8N_DATA_DIR"
mkdir -p "$N8N_DATA_DIR"
sudo chown -R 1000:1000 "$N8N_DATA_DIR"
sudo chmod -R 700 "$N8N_DATA_DIR"

# ====== 生成新的 docker-compose.yml ======
echo "📝 生成新的 docker-compose.yml"
cat > docker-compose.yml <<EOF
version: '3'

services:
  n8n:
    image: $N8N_IMAGE
    container_name: n8n
    restart: always
    ports:
      - "$N8N_PORT:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=$N8N_USER
      - N8N_BASIC_AUTH_PASSWORD=$N8N_PASSWORD
      - N8N_DEFAULT_LOCALE=zh-CN
    volumes:
      - $N8N_DATA_DIR:/home/node/.n8n
EOF

# ====== 拉取最新镜像 ======
echo "⬇️ 拉取最新 n8n 镜像: $N8N_IMAGE"
docker pull $N8N_IMAGE

# ====== 停止旧容器并启动新容器 ======
echo "🔄 停止旧容器并启动新容器"
docker compose down || true
docker compose up -d --force-recreate

# ====== 等待容器启动 ======
echo "⏳ 等待容器启动..."
sleep 5

# ====== 显示状态 ======
echo "✅ 当前 n8n 容器状态:"
docker compose ps

echo "✅ 中文环境变量:"
docker compose exec n8n printenv | grep N8N_DEFAULT_LOCALE || echo "未生效"

echo "🌐 访问 n8n 界面: http://<你的服务器IP>:$N8N_PORT"
echo "🎉 修复完成，刷新浏览器即可看到中文界面（必要时清理缓存或使用无痕模式）"
