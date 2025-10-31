#!/bin/bash

# =========================================
# n8n Docker 强制升级脚本（全自动版）
# =========================================

N8N_IMAGE="n8nio/n8n:latest"   # 可改为指定版本
ENABLE_CHINESE=true             # 是否启用中文界面
BACKUP_DIR="$HOME/n8n_backups" # 数据备份目录
DEFAULT_PORT=5678               # 默认 n8n 宿主机端口
MAX_PORT=5700                   # 最大尝试端口号

echo "🚀 开始 n8n 强制升级（全自动版）..."

# -----------------------------------------
# 1. 自动查找 docker-compose.yml
# -----------------------------------------
echo "🔍 搜索 n8n docker-compose.yml ..."
N8N_DIR=$(find / -name docker-compose.yml 2>/dev/null | grep n8n | head -n 1)
if [ -z "$N8N_DIR" ]; then
  echo "❌ 未找到 n8n docker-compose.yml，请确认路径。"
  exit 1
fi
N8N_DIR=$(dirname "$N8N_DIR")
cd "$N8N_DIR" || exit
echo "✅ 找到 docker-compose.yml: $N8N_DIR"

# -----------------------------------------
# 2. 检查当前版本
# -----------------------------------------
CURRENT_CONTAINER=$(docker ps --format '{{.Names}}' | grep n8n | head -n 1)
if [ -n "$CURRENT_CONTAINER" ]; then
  CURRENT_VERSION=$(docker exec -it "$CURRENT_CONTAINER" n8n --version)
  echo "🔹 当前容器: $CURRENT_CONTAINER"
  echo "🔹 当前版本: $CURRENT_VERSION"
else
  echo "⚠️ 未检测到运行中的 n8n 容器"
  CURRENT_VERSION="未运行"
fi

# -----------------------------------------
# 3. 数据备份
# -----------------------------------------
echo "📦 备份 n8n 数据..."
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/n8n_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
tar czvf "$BACKUP_FILE" ~/.n8n
echo "✅ 数据备份完成: $BACKUP_FILE"

# -----------------------------------------
# 4. 停止并删除旧容器
# -----------------------------------------
if [ -n "$CURRENT_CONTAINER" ]; then
  echo "🛑 停止并删除旧容器..."
  docker stop "$CURRENT_CONTAINER"
  docker rm "$CURRENT_CONTAINER"
  echo "✅ 旧容器已删除"
fi

# -----------------------------------------
# 5. 查找可用端口
# -----------------------------------------
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

# -----------------------------------------
# 6. 拉取最新镜像
# -----------------------------------------
echo "⬇️ 拉取镜像: $N8N_IMAGE"
docker pull "$N8N_IMAGE"

# -----------------------------------------
# 7. 更新 docker-compose.yml 镜像
# -----------------------------------------
sed -i "s|image:.*|image: $N8N_IMAGE|" docker-compose.yml
echo "✅ docker-compose.yml 已更新为新镜像"

# -----------------------------------------
# 8. 更新 docker-compose.yml 端口
# -----------------------------------------
sed -i "s|.*:5678|$PORT:5678|" docker-compose.yml
echo "✅ docker-compose.yml 端口已更新为 $PORT"

# -----------------------------------------
# 9. 设置中文界面（可选）
# -----------------------------------------
if [ "$ENABLE_CHINESE" = true ]; then
  if ! grep -q "N8N_DEFAULT_LOCALE" docker-compose.yml; then
    sed -i '/environment:/a \      - N8N_DEFAULT_LOCALE=zh-CN' docker-compose.yml
  else
    sed -i 's/.*N8N_DEFAULT_LOCALE=.*/      - N8N_DEFAULT_LOCALE=zh-CN/' docker-compose.yml
  fi
  echo "🌐 中文界面已启用"
fi

# -----------------------------------------
# 10. 启动新容器
# -----------------------------------------
echo "🔄 启动新容器..."
docker compose up -d

# -----------------------------------------
# 11. 检查升级后版本
# -----------------------------------------
sleep 5
NEW_CONTAINER=$(docker ps --format '{{.Names}}' | grep n8n | head -n 1)
if [ -n "$NEW_CONTAINER" ]; then
  NEW_VERSION=$(docker exec -it "$NEW_CONTAINER" n8n --version)
  echo "✅ 新容器: $NEW_CONTAINER"
  echo "✅ 升级前版本: $CURRENT_VERSION"
  echo "✅ 升级后版本: $NEW_VERSION"
  echo "✅ n8n 访问端口: $PORT"
else
  echo "❌ 升级后未检测到 n8n 容器，请手动检查。"
fi

echo "🎉 n8n 强制升级完成！"
