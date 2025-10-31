#!/bin/bash
set -e

# 进入 n8n 目录
N8N_DIR="/root/n8n"
mkdir -p "$N8N_DIR"
cd "$N8N_DIR"

# 修复挂载目录权限
echo "🛠️ 修复挂载目录权限: ~/.n8n"
mkdir -p ~/.n8n
chown -R $(whoami):$(whoami) ~/.n8n

# 检测空闲端口
PORT=5678
while lsof -i:$PORT &>/dev/null; do
  PORT=$((PORT+1))
done
echo "✅ 使用端口: $PORT"

# 停止旧容器
echo "🛠️ 停止旧容器..."
docker compose down || true

# 下载并解压汉化包
echo "⬇️ 下载汉化包..."
curl -L -o editor-ui.tar.gz "https://github.com/other-blowsnow/n8n-i18n-chinese/releases/download/n8n%401.117.3/editor-ui.tar.gz"
echo "⬇️ 解压覆盖到 ~/.n8n"
tar -xzf editor-ui.tar.gz -C ~/.n8n --strip-components=1
rm editor-ui.tar.gz

# 提示用户输入 n8n 登录用户名和密码
read -p "请输入 n8n 登录用户名: " N8N_USER
read -s -p "请输入 n8n 登录密码: " N8N_PASS
echo ""

# 生成 docker-compose.yml
cat > docker-compose.yml <<EOF
services:
  n8n:
    container_name: n8n
    image: n8nio/n8n:latest
    restart: always
    environment:
      - N8N_DEFAULT_LOCALE=zh-CN
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=$N8N_USER
      - N8N_BASIC_AUTH_PASSWORD=$N8N_PASS
    ports:
      - "$PORT:5678"
    volumes:
      - ~/.n8n:/home/node/.n8n
networks:
  default:
    name: n8n_default
EOF

# 启动新容器
echo "🔄 启动 n8n 容器..."
docker compose up -d --force-recreate

# 输出信息
echo "🌐 n8n 已启动，访问地址: http://<你的服务器IP>:$PORT"
echo "用户名: $N8N_USER"
echo "密码: (你输入的密码)"
echo "🎉 n8n 已汉化完成，请刷新浏览器（必要时使用无痕模式）"
