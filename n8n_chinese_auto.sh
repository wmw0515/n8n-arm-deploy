#!/bin/bash
set -e

# === 用户输入部分 ===
read -p "请输入 n8n 登录用户名 (默认 admin): " N8N_USER
N8N_USER=${N8N_USER:-admin}

read -s -p "请输入 n8n 登录密码: " N8N_PASSWORD
echo

# === 配置变量 ===
N8N_DIR="/root/n8n"
DATA_DIR="$HOME/.n8n"
I18N_URL="https://github.com/other-blowsnow/n8n-i18n-chinese/releases/download/n8n%401.117.3/editor-ui.tar.gz"
PORT=5678  # 可以根据需要修改

echo "🛠️ 停止旧容器..."
cd "$N8N_DIR"
docker compose down || true

echo "🛠️ 修复挂载目录权限: $DATA_DIR"
mkdir -p "$DATA_DIR"
chown -R 1000:1000 "$DATA_DIR"
chmod -R 700 "$DATA_DIR"

echo "⬇️ 下载中文汉化包..."
TMP_TAR="/tmp/editor-ui.tar.gz"
curl -L "$I18N_URL" -o "$TMP_TAR"

echo "🔄 解压覆盖到 n8n 数据目录..."
tar -xzf "$TMP_TAR" -C "$DATA_DIR"
rm -f "$TMP_TAR"

echo "📝 生成 docker-compose.yml"
cat > "$N8N_DIR/docker-compose.yml" <<EOF
services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    ports:
      - "${PORT}:5678"
    environment:
      - N8N_DEFAULT_LOCALE=zh-CN
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
    volumes:
      - $DATA_DIR:/home/node/.n8n
    restart: always
EOF

echo "🔄 启动新容器..."
docker compose up -d --force-recreate

echo "⏳ 等待容器启动..."
sleep 5

docker compose ps

echo "🎉 完成！请用浏览器访问：http://<你的服务器IP>:${PORT}，登录用户名: ${N8N_USER}"
echo "🌐 若界面仍为英文，请清除浏览器缓存或使用无痕模式。"
