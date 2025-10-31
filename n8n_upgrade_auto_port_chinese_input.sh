#!/bin/bash
# n8n 一键升级 + 中文化 + 自动端口 + 动态账号脚本
# 使用前请备份 ~/.n8n 文件夹

N8N_HOME="/root/.n8n"
N8N_DIR="/root/n8n"
START_PORT=5678
MAX_PORT=5699

echo "⬇️ 进入 n8n 目录: $N8N_DIR"
mkdir -p "$N8N_DIR"
cd "$N8N_DIR" || exit

# 输入用户名和密码
read -p "请输入 n8n 登录用户名: " N8N_USER
read -s -p "请输入 n8n 登录密码: " N8N_PASSWORD
echo ""

# 停止旧容器
echo "🛠️ 停止旧容器..."
docker compose down 2>/dev/null

# 修复挂载目录权限
echo "🛠️ 修复挂载目录权限: $N8N_HOME"
mkdir -p "$N8N_HOME"
chown -R 1000:1000 "$N8N_HOME"
chmod -R 700 "$N8N_HOME"

# 检测空闲端口
echo "🔍 检测空闲端口..."
N8N_PORT=""
for ((port=$START_PORT; port<=$MAX_PORT; port++)); do
  if ! lsof -i:"$port" >/dev/null 2>&1; then
    N8N_PORT=$port
    break
  fi
done

if [ -z "$N8N_PORT" ]; then
  echo "❌ 没有找到可用端口，请手动释放 5678-5699 端口"
  exit 1
fi
echo "✅ 使用端口: $N8N_PORT"

# 生成 docker-compose.yml
echo "📝 生成 docker-compose.yml"
cat > "$N8N_DIR/docker-compose.yml" <<EOF
services:
  n8n:
