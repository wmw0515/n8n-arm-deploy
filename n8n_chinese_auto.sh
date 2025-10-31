#!/bin/bash
set -e

# 1️⃣ 输入 n8n 登录用户名和密码
read -p "请输入 n8n 登录用户名: " N8N_USER
read -s -p "请输入 n8n 登录密码: " N8N_PASSWORD
echo ""

# 2️⃣ n8n 工作目录
N8N_DIR="/root/n8n"
N8N_DATA="$HOME/.n8n"
I18N_URL="https://github.com/other-blowsnow/n8n-i18n-chinese/releases/download/n8n%401.117.3/editor-ui.tar.gz"

mkdir -p $N8N_DIR
mkdir -p $N8N_DATA

cd $N8N_DIR

# 3️⃣ 停止并清理旧容器和网络
docker compose down || true
docker rm -f n8n || true
docker network rm n8n_default || true

# 4️⃣ 自动选择空闲端口
PORT=5678
while lsof -i:$PORT &>/dev/null; do
  PORT=$((PORT+1))
done
echo "✅ 使用端口: $PORT"

# 5️⃣ 下载汉化文件并覆盖 editor-ui 目录
echo "⬇️ 下载并覆盖汉化文件到 $N8N_DATA/editor-ui ..."
curl -L $I18N_URL -o editor-ui.tar.gz
mkdir -p $N8N_DATA/editor-ui
tar -xzf editor-ui.tar.gz -C $N8N_DATA/editor-ui --strip-components=1
rm -f editor-ui.tar.gz

# 6️⃣ 修复挂载目录权限
chown -R 1000:1000 $N8N_DATA

# 7️⃣ 生成 docker-compose.yml
cat > $N8N_DIR/docker-compose.yml <<EOF
services:
  n8n:
    container_name: n8n
    image: n8nio/n8n:latest
    restart: always
    ports:
      - "$PORT:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=$N8N_USER
      - N8N_BASIC_AUTH_PASSWORD=$N8N_PASSWORD
      - N8N_DEFAULT_LOCALE=zh-CN
    volumes:
      - $N8N_DATA:/home/node/.n8n
EOF

# 8️⃣ 清理旧缓存确保中文生效
echo "🧹 清理缓存..."
rm -rf $N8N_DATA/editor-ui/.cache

# 9️⃣ 启动容器
docker compose up -d --force-recreate

# 10️⃣ 提示信息
echo "🎉 n8n 已启动!"
echo "🌐 访问地址: http://<你的服务器IP>:$PORT"
echo "💡 用户名: $N8N_USER"
echo "💡 密码: $N8N_PASSWORD"
echo "✅ 中文界面已覆盖，首次访问可能稍慢，请刷新或使用无痕模式。"
