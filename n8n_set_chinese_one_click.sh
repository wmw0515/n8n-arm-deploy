#!/bin/bash

# =========================================
# n8n Docker 界面一键中文化脚本
# =========================================

N8N_DIR="/root/n8n"
BACKUP_FILE="$N8N_DIR/docker-compose.yml.bak_$(date +%Y%m%d_%H%M%S)"

echo "🌐 一键中文化 n8n 界面脚本启动..."

# 1️⃣ 检查目录
if [ ! -f "$N8N_DIR/docker-compose.yml" ]; then
  echo "❌ 未找到 docker-compose.yml，请确认路径 $N8N_DIR"
  exit 1
fi

# 2️⃣ 备份原文件
cp "$N8N_DIR/docker-compose.yml" "$BACKUP_FILE"
echo "📦 原 docker-compose.yml 已备份：$BACKUP_FILE"

# 3️⃣ 替换为修正的中文化 docker-compose.yml
cat > "$N8N_DIR/docker-compose.yml" <<'EOF'
version: "3"

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    ports:
      - "5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin       # 请修改为你的用户名
      - N8N_BASIC_AUTH_PASSWORD=yourpassword  # 请修改为你的密码
      - N8N_DEFAULT_LOCALE=zh-CN
    volumes:
      - ~/.n8n:/home/node/.n8n
    restart: always
EOF

echo "✅ docker-compose.yml 已替换为中文化版本"

# 4️⃣ 重建容器
cd "$N8N_DIR" || exit
echo "🔄 停止旧容器并重建..."
docker compose down
docker compose up -d --force-recreate

# 5️⃣ 验证环境变量
sleep 5
ENV_VAR=$(docker compose exec n8n printenv | grep N8N_DEFAULT_LOCALE || echo "未生效")
echo "🌐 当前环境变量：$ENV_VAR"

echo "🎉 n8n 已中文化，请刷新浏览器访问界面 (必要时清理缓存或使用无痕模式)"
