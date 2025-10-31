#!/bin/bash
set -e

# 默认 N8N 目录
N8N_DIR="/root/n8n"
I18N_DIR="$N8N_DIR/i18n"
EDITOR_UI_URL="https://github.com/other-blowsnow/n8n-i18n-chinese/releases/download/n8n%401.117.3/editor-ui.tar.gz"
CONTAINER_NAME="n8n_cn"
PORT=5678

echo "🚀 一键部署 N8N 中文化..."

# 停止占用端口的容器
OCCUPIED_CONTAINER=$(docker ps -q --filter "publish=$PORT")
if [ -n "$OCCUPIED_CONTAINER" ]; then
    echo "🛑 停止并删除已占用 $PORT 端口的容器..."
    docker stop $OCCUPIED_CONTAINER
    docker rm $OCCUPIED_CONTAINER
fi

# 创建目录
mkdir -p $I18N_DIR

# 下载汉化文件
echo "⬇️ 下载 N8N 汉化文件..."
curl -L $EDITOR_UI_URL -o $I18N_DIR/editor-ui.tar.gz

# 解压覆盖
echo "🔄 解压汉化文件到 $I18N_DIR ..."
tar -xzf $I18N_DIR/editor-ui.tar.gz -C $I18N_DIR
rm -f $I18N_DIR/editor-ui.tar.gz

# 启动容器
echo "🚀 启动 N8N 中文化容器..."
docker run -d --name $CONTAINER_NAME \
  -p $PORT:5678 \
  -v $I18N_DIR:/usr/local/lib/node_modules/n8n/node_modules/n8n-editor-ui/dist \
  -v ~/.n8n:/home/node/.n8n \
  -e N8N_DEFAULT_LOCALE=zh-CN \
  -e N8N_SECURE_COOKIE=false \
  n8nio/n8n

echo "🎉 N8N 中文化已启动!"
echo "🌐 访问地址: http://<你的服务器IP>:$PORT"
