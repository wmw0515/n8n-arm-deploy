#!/bin/bash
set -e

# ====== 配置 ======
N8N_DIR="$HOME/n8n"          # docker-compose.yml 所在目录
N8N_IMAGE="n8nio/n8n:latest"  # 最新 n8n 镜像
N8N_DATA_DIR="$HOME/.n8n"     # n8n 数据目录
BASE_PORT=5678                 # 默认容器端口映射
MAX_PORT=5689                  # 最大尝试端口

# ====== 进入 n8n 目录 ======
echo "⬇️ 进入 n8n 目录: $N8N_DIR"
cd "$N8N_DIR"

# ====== 修复挂载目录权限 ======
echo "🛠️ 修复挂载目录权限: $N8N_DATA_DIR"
mkdir -p "$N8N_DATA_DIR"
chown -R 1000:1000 "$N8N_DATA_DIR"
chmod 700 "$N8N_DATA_DIR"

# ====== 检测空闲端口 ======
echo "🔍 检测空闲端口..."
N8N_PORT=$BASE_PORT
while lsof -i:$N8N_PORT -sTCP:LISTEN >/dev/null 2>&1; do
    N8N_PORT=$((N8N_PORT+1))
    if [ $N8N_PORT -gt $MAX_PORT ]; then
        echo "❌ 没有可用端口，请释放端口 $BASE_PORT-$MAX_PORT"
        exit 1
    fi
done
echo "✅ 使用端口: $N8N_PORT"

# ====== 拉取最新 n8n 镜像 ======
echo "⬇️ 拉取最新 n8n 镜像: $N8N_IMAGE"
docker pull $N8N_IMAGE

# ====== 更新 docker-compose.yml ======
echo "📝 更新 docker-compose.yml 为最新镜像并启用中文"
# 备份原 docker-compose.yml
cp docker-compose.yml docker-compose.yml.bak.$(date +%Y%m%d%H%M%S)

# 替换 image
sed -i "s#image:.*#image: $N8N_IMAGE#" docker-compose.yml

# 添加或修改中文环境变量
if grep -q "N8N_DEFAULT_LOCALE" docker-compose.yml; then
    sed -i 's#N8N_DEFAULT_LOCALE:.*#      N8N_DEFAULT_LOCALE: zh-CN#' docker-compose.yml
else
    sed -i '/environment:/a \      N8N_DEFAULT_LOCALE: zh-CN' docker-compose.yml
fi

# 替换端口映射
sed -i "s#- .*:5678#- \"$N8N_PORT:5678\"#" docker-compose.yml || echo "端口映射未找到，将自动添加"
if ! grep -q "$N8N_PORT:5678" docker-compose.yml; then
    sed -i '/ports:/a \      - "'"$N8N_PORT"':5678"' docker-compose.yml
fi

# ====== 重建容器 ======
echo "🔄 停止旧容器并强制重建新容器"
docker compose down
docker compose up -d --force-recreate

# ====== 等待容器启动 ======
echo "⏳ 等待容器启动..."
sleep 5

# ====== 显示版本和中文环境变量 ======
echo "✅ 当前 n8n 版本:"
docker compose exec n8n n8n --version || echo "无法获取版本，请检查容器状态"
echo "✅ 中文环境变量:"
docker compose exec n8n printenv | grep N8N_DEFAULT_LOCALE || echo "未生效"

# ====== 输出访问地址 ======
echo "🌐 访问 n8n 界面：http://<你的服务器IP>:$N8N_PORT"
echo "🎉 升级完成，刷新浏览器即可看到中文界面（必要时清理缓存或使用无痕模式）"
