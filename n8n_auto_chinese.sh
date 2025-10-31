#!/bin/bash

# =========================================
# n8n Docker 自动中文化 + 端口检查脚本
# =========================================

N8N_DIR="/root/n8n"
COMPOSE_FILE="$N8N_DIR/docker-compose.yml"
BACKUP_FILE="$N8N_DIR/docker-compose.yml.bak_$(date +%Y%m%d_%H%M%S)"

echo "🌐 n8n 一键中文化启动..."

# 1️⃣ 检查 docker-compose.yml
if [ ! -f "$COMPOSE_FILE" ]; then
  echo "❌ 未找到 docker-compose.yml，请确认路径 $N8N_DIR"
  exit 1
fi

# 2️⃣ 备份原文件
cp "$COMPOSE_FILE" "$BACKUP_FILE"
echo "📦 docker-compose.yml 已备份：$BACKUP_FILE"

# 3️⃣ 检测端口 5678 是否被占用
PORT=5678
for P in {5678..5689}; do
    if ! lsof -i:$P &>/dev/null; then
        PORT=$P
        break
    fi
done
echo "🔌 n8n 容器将使用端口：$PORT"

# 4️⃣ 替换 docker-compose.yml
cat > "$COMPOSE_FILE" <<EOF
services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    ports:
      - "${PORT}:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin       # 修改为你的用户名
      - N8N_BASIC_AUTH_PASSWORD=yourpassword  # 修改为你的密码
      - N8N_DEFAULT_LOCALE=zh-CN
    volumes:
      - ~/.n8n:/home/node/.n8n
    restart: always
EOF

echo "✅ docker-compose.yml 已更新，中文环境变量已设置"

# 5️⃣ 强制重建容器
cd "$N8N_DIR" || exit
docker compose down
docker compose up -d --force-recreate

# 6️⃣ 检查环境变量是否生效
sleep 5
ENV_VAR=$(docker compose exec n8n printenv | grep N8N_DEFAULT_LOCALE || echo "未生效")
echo "🌐 当前环境变量：$ENV_VAR"

echo "🎉 n8n 已中文化，访问地址： http://<你的服务器IP>:${PORT} "
echo "（必要时清理浏览器缓存或使用无痕模式）"
