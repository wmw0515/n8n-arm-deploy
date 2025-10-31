#!/bin/bash

# =========================================
# n8n Docker 升级脚本（自动中文界面）
# =========================================

N8N_IMAGE="n8nio/n8n:latest"   # 可改为指定版本
BACKUP_DIR="$HOME/n8n_backups" # 数据备份目录
DEFAULT_PORT=5678               # 默认 n8n 宿主机端口
MAX_PORT=5700                   # 最大尝试端口号

echo "🚀 开始 n8n 升级（自动中文界面）..."

# 1️⃣ 查找 docker-compose.yml
echo "🔍 搜索 n8n docker-compose.yml ..."
N8N_DIR=$(find / -name docker-compose.yml 2>/dev/null | grep n8n | head -n 1)
if [ -z "$N8N_DIR" ]; then
  echo "❌ 未找到 docker-compose.yml，请确认路径。"
  exit 1
fi
N8N_DIR=$(dirname "$N8N_DIR")
cd "$N8N_DIR" || exit
echo "✅ 找到 docker-compose.yml: $N8N_DIR"

# 2️⃣ 当前版本
CURRENT_CONTAINER=$(docker ps --format '{{.Names}}' | grep n8n | head -n 1)
if [ -n "$CURRENT_CONTAINER" ]; then
  CURRENT_VERSION=$(docker exec -it "$CURRENT_CONTAINER" n8n --version)
  echo "🔹 当前容器: $CURRENT_CONTAINER"
  echo "🔹 当前版本: $CURRENT_VERSION"
else
  CURRENT_VERSION="未运行"
fi

# 3️⃣ 数据备份
echo "📦 备份 n8n 数据..."
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/n8n_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
tar czvf "$BACKUP_FILE" ~/.n8n
echo "✅ 数据备份完成: $BACKUP_FILE"

# 4️⃣ 停止旧容器
if [ -n "$CURRENT_CONTAINER" ]; then
  echo "🛑 停止并删除旧容器..."
  docker stop "$CURRENT_CONTAINER"
  docker rm "$CURRENT_CONTAINER"
  echo "✅ 旧容器已删除"
fi

# 5️⃣ 自动检测可用端口
PORT=$DEFAULT_PORT
while lsof -i :$PORT -t >/dev/null 2>&1; do
  echo "⚠️ 端口 $PORT 被占用，尝试下一个端口..."
  PORT=$((PORT+1))
  if [ $PORT -gt $MAX_PORT ]; then
    echo "❌ 无可用端口，请手动释放端口 $DEFAULT_PORT-$MAX_PORT"
    exit 1
  fi
done
echo "✅ 使用端口 $PORT 启动 n8n"

# 6️⃣ 拉取镜像
echo "⬇️ 拉取镜像: $N8N_IMAGE"
docker pull "$N8N_IMAGE"

# 7️⃣ 更新 docker-compose.yml 镜像
sed -i "s|image:.*|image: $N8N_IMAGE|" docker-compose.yml
echo "✅ docker-compose.yml 已更新为新镜像"

# 8️⃣ 更新端口
sed -i "s|.*:5678|$PORT:5678|" docker-compose.yml
echo "✅ docker-compose.yml 端口已更新为 $PORT"

# 9️⃣ 设置中文界面
if grep -q "environment:" docker-compose.yml; then
  if ! grep -q "N8N_DEFAULT_LOCALE" docker-compose.yml; then
    sed -i '/environment:/a \      - N8N_DEFAULT_LOCALE=zh-CN' docker-compose.yml
  else
    sed -i 's/.*N8N_DEFAULT_LOCALE=.*/      - N8N_DEFAULT_LOCALE=zh-CN/' docker-compose.yml
  fi
else
  # 如果没有 environment 节点
  sed -i '/image:/a \    environment:\n      - N8N_DEFAULT_LOCALE=zh-CN' docker-compose.yml
fi
echo "🌐 中文界面已启用"

# 10️⃣ 启动新容器
echo "🔄 启动 n8n..."
docker compose up -d

# 11️⃣ 检查版本
sleep 5
NEW_CONTAINER=$(docker ps --format '{{.Names}}' | grep n8n | head -n 1)
if [ -n "$NEW_CONTAINER" ]; then
  NEW_VERSION=$(docker exec -it "$NEW_CONTAINER" n8n --version)
  echo "✅ 新容器: $NEW_CONTAINER"
  echo "✅ 升级前版本: $CURRENT_VERSION"
  echo "✅ 升级后版本: $NEW_VERSION"
  echo "✅ n8n 访问端口: $PORT"
else
  echo "❌ 新容器启动失败，请手动检查。"
fi

echo "🎉 n8n 升级完成，界面已中文化！"
