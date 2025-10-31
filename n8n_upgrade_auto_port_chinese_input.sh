#!/bin/bash
set -e

N8N_DIR="/root/n8n"
N8N_HOME="/root/.n8n"

# 输入用户名和密码
read -p "请输入 n8n 登录用户名: " N8N_USER
read -sp "请输入 n8n 登录密码: " N8N_PASSWORD
echo ""

# 创建目录和修复权限
mkdir -p "$N8N_HOME"
chmod 700 "$N8N_HOME"

# 停止旧容器
if [ -f "$N8N_DIR/docker-compose.yml" ]; then
  echo "🛠️ 停止旧容器..."
  docker compose -f "$N8N_DIR/docker-compose.yml" down || true
fi

# 检测可用端口
START_PORT=5678
while lsof -i:$START_PORT >/dev/null 2>&1; do
  ((START_PORT++))
done
N8N_PORT=$START_PORT
echo "✅ 使用端口: $N8N_PORT"

# 拉取最新镜像
echo "⬇️ 拉取最新 n8n 镜像: n8nio/n8n:latest"
docker pull n8nio/n8n:latest

# 生成 docker-compose.yml
echo "📝 生成 docker-compose.yml"
mkdir -p "$N8N_DIR"
# 这里 EOF 必须左对齐
cat > "$N8N_DIR/docker-compose.yml" <<EOF
services:
  n8n:
    container_name: n8n
    image: n8nio/n8n:latest
    restart: always
    environment:
      - N8N_DEFAULT_LOCALE=zh-CN
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=$N8N_USER
      - N8N_BASIC_AUTH_PASSWORD=$N8N_PASSWORD
    ports:
      - "$N8N_PORT:5678"
    volumes:
      - $N8N_HOME:/home/node/.n8n
EOF

# 启动新容器
echo "🔄 启动新容器..."
docker compose -f "$N8N_DIR/docker-compose.yml" up -d --force-recreate

# 等待容器启动
echo "⏳ 等待容器启动..."
sleep 5

# 显示状态和访问信息
docker compose -f "$N8N_DIR/docker-compose.yml" ps
echo "✅ 中文环境变量:"
docker compose -f "$N8N_DIR/docker-compose.yml" exec n8n printenv | grep N8N_DEFAULT_LOCALE || echo "未生效"
echo "🌐 访问 n8n 界面: http://<你的服务器IP>:$N8N_PORT"
echo "🎉 中文化完成，请使用你输入的账号密码登录"
