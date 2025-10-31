#!/bin/bash

# =========================================
# n8n Docker 界面语言修改为中文脚本
# =========================================

echo "🌐 将 n8n 界面语言修改为中文..."

# 查找 docker-compose.yml
N8N_DIR=$(find / -name docker-compose.yml 2>/dev/null | grep n8n | head -n 1)
if [ -z "$N8N_DIR" ]; then
  echo "❌ 未找到 n8n docker-compose.yml，请确认路径。"
  exit 1
fi
N8N_DIR=$(dirname "$N8N_DIR")
cd "$N8N_DIR" || exit
echo "✅ 找到 docker-compose.yml: $N8N_DIR"

# 检查 environment 节点是否存在
if grep -q "environment:" docker-compose.yml; then
    if grep -q "N8N_DEFAULT_LOCALE" docker-compose.yml; then
        # 已存在则替换
        sed -i 's/.*N8N_DEFAULT_LOCALE=.*/      - N8N_DEFAULT_LOCALE=zh-CN/' docker-compose.yml
    else
        # 不存在则添加
        sed -i '/environment:/a \      - N8N_DEFAULT_LOCALE=zh-CN' docker-compose.yml
    fi
else
    # 没有 environment 节点，则添加完整环境节点
    sed -i '/image:/a \    environment:\n      - N8N_DEFAULT_LOCALE=zh-CN' docker-compose.yml
fi

echo "✅ docker-compose.yml 已修改为中文界面"

# 重启容器生效
echo "🔄 重启 n8n 容器..."
docker compose down
docker compose up -d

# 检查容器是否启动
CONTAINER=$(docker ps --format '{{.Names}}' | grep n8n | head -n 1)
if [ -n "$CONTAINER" ]; then
    echo "✅ n8n 容器已重启：$CONTAINER"
    echo "🎉 界面语言已修改为中文，请刷新浏览器访问。"
else
    echo "❌ 容器启动失败，请手动检查。"
fi
