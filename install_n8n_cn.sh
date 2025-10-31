#!/bin/bash
set -e

# 配置
N8N_PORT=5679
I18N_DIR="/root/n8n/i18n"
I18N_URL="https://github.com/other-blowsnow/n8n-i18n-chinese/releases/download/n8n%401.117.3/editor-ui.tar.gz"

echo "🛠️ 停止并删除旧容器..."
docker rm -f n8n 2>/dev/null || true

echo "🛠️ 创建汉化目录: $I18N_DIR"
mkdir -p "$I18N_DIR"

echo "⬇️ 下载汉化文件..."
curl -L "$I18N_URL" -o "$I18N_DIR/editor-ui.tar.gz"

echo "🧹 解压汉化文件..."
tar -xzf "$I18N_DIR/editor-ui.tar.gz" -C "$I18N_DIR"
rm -f "$I18N_DIR/editor-ui.tar.gz"

echo "🌐 启动 N8N 中文版..."
docker run -it -d --name n8n \
  -p $N8N_PORT:5678 \
  -v "$I18N_DIR":/usr/local/lib/node_modules/n8n/node_modules/n8n-editor-ui/dist \
  -v ~/.n8n:/home/node/.n8n \
  -e N8N_DEFAULT_LOCALE=zh-CN \
  -e N8N_SECURE_COOKIE=false \
  n8nio/n8n

echo "🎉 N8N 已启动！"
echo "💻 访问地址: http://<你的服务器IP>:$N8N_PORT"
echo "✅ 中文界面已启用"
