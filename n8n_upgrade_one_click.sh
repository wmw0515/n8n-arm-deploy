#!/bin/bash

# =========================================
# n8n Docker 强制升级脚本
# =========================================

# 可修改参数
N8N_IMAGE="n8nio/n8n:latest"  # 可改为指定版本，如 n8nio/n8n:1.130.0
ENABLE_CHINESE=true            # 是否启用中文界面
BACKUP_DIR="$HOME/n8n_backups" # 备份目录

echo "🚀 开始 n8n 强制升级..."

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
# 2. 检查当前运行版本
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
# 3. 备份数据
# -----------------------------------------
echo "📦 备份 n8n 数据..."
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/n8n_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
tar czvf "$BACKUP_FILE" ~/.n8n
echo "✅ 数据备份完成: $BACKUP_FILE"

# -----------------------------------------
# 4. 停止并删除旧容器
# -----------------------------------------
echo "🛑 停止并删除旧容器..."
docker compose down

# -----------------------------------------
# 5. 拉取最新镜像（或指定版本）
# -----------------------------------------
echo "⬇️ 拉取镜像: $N8N_IMAGE"
docker pull "$N8N_IMAGE"

# -----------------------------------------
# 6. 修改 docker-compose.yml 指向新镜像
# -----------------------------------------
sed -i "s|image:.*|image: $N8N_IMAGE|" docker-compose.yml
echo "✅ docker-compose.yml 已更新为新镜像"

# -----------------------------------------
# 7. 设置中文界面（可选）
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
# 8. 启动新容器
# -----------------------------------------
echo "🔄 启动新容器..."
docker compose up -d

# -----------------------------------------
# 9. 检查升级后版本
# -----------------------------------------
sleep 5
NEW_CONTAINER=$(docker ps --format '{{.Names}}' | grep n8n | head -n 1)
if [ -n "$NEW_CONTAINER" ]; then
  NEW_VERSION=$(docker exec -it "$NEW_CONTAINER" n8n --version)
  echo "✅ 新容器: $NEW_CONTAINER"
  echo "✅ 升级前版本: $CURRENT_VERSION"
  echo "✅ 升级后版本: $NEW_VERSION"
else
  echo "❌ 升级后未检测到 n8n 容器，请手动检查。"
fi

echo "🎉 n8n 强制升级完成！"
