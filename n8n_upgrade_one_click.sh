#!/bin/bash

# =========================================
# n8n Docker 自动升级脚本
# =========================================

N8N_IMAGE="n8nio/n8n:latest"  # 可改成固定版本，例如 n8nio/n8n:1.130.0
BACKUP_DIR="$HOME/n8n_backups" # 备份存放目录
ENABLE_CHINESE=true            # 是否启用中文界面

# -----------------------------------------
# 1. 自动查找 docker-compose.yml
# -----------------------------------------
echo "🔍 搜索 n8n docker-compose.yml ..."
N8N_DIR=$(find / -name docker-compose.yml 2>/dev/null | grep n8n | head -n 1)

if [ -z "$N8N_DIR" ]; then
  echo "❌ 未找到 n8n 的 docker-compose.yml，请确认路径或容器名称。"
  exit 1
fi

N8N_DIR=$(dirname "$N8N_DIR")
echo "✅ 找到 docker-compose.yml: $N8N_DIR"
cd "$N8N_DIR" || exit

# -----------------------------------------
# 2. 自动获取容器名
# -----------------------------------------
N8N_CONTAINER_NAME=$(docker ps --format '{{.Names}}' | grep n8n | head -n 1)

if [ -z "$N8N_CONTAINER_NAME" ]; then
  echo "⚠️ 未发现运行中的 n8n 容器，将在启动后检查版本。"
else
  echo "✅ 检测到 n8n 容器: $N8N_CONTAINER_NAME"
fi

# -----------------------------------------
# 3. 创建备份
# -----------------------------------------
echo "📦 备份 n8n 数据..."
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/n8n_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
tar czvf "$BACKUP_FILE" ~/.n8n
echo "✅ 备份完成: $BACKUP_FILE"

# -----------------------------------------
# 4. 停止容器
# -----------------------------------------
echo "🛑 停止 n8n 容器..."
docker compose down

# -----------------------------------------
# 5. 拉取最新镜像
# -----------------------------------------
echo "⬇️ 拉取镜像: $N8N_IMAGE"
docker pull "$N8N_IMAGE"

# -----------------------------------------
# 6. 设置中文界面（可选）
# -----------------------------------------
if [ "$ENABLE_CHINESE" = true ]; then
  echo "🌐 设置中文界面..."
  if ! grep -q "N8N_DEFAULT_LOCALE" docker-compose.yml; then
    sed -i '/environment:/a \      - N8N_DEFAULT_LOCALE=zh-CN' docker-compose.yml
  else
    sed -i 's/.*N8N_DEFAULT_LOCALE=.*/      - N8N_DEFAULT_LOCALE=zh-CN/' docker-compose.yml
  fi
fi

# -----------------------------------------
# 7. 启动容器
# -----------------------------------------
echo "🔄 启动 n8n 容器..."
docker compose up -d

# -----------------------------------------
# 8. 检查版本
# -----------------------------------------
sleep 5
if [ -n "$N8N_CONTAINER_NAME" ]; then
  docker exec -it "$N8N_CONTAINER_NAME" n8n --version
else
  # 尝试自动获取容器名再检查
  NEW_CONTAINER=$(docker ps --format '{{.Names}}' | grep n8n | head -n 1)
  if [ -n "$NEW_CONTAINER" ]; then
    echo "✅ 新容器版本:"
    docker exec -it "$NEW_CONTAINER" n8n --version
  else
    echo "❌ 无法检测 n8n 容器版本，请手动检查。"
  fi
fi

echo "🎉 n8n 升级完成！"
