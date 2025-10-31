#!/bin/bash
set -e

# ====== 配置 ======
N8N_DIR="$HOME/n8n"
N8N_DATA_DIR="$HOME/.n8n"
CONTAINER_NAME="n8n"

# ====== 进入 n8n 目录 ======
echo "⬇️ 进入 n8n 目录: $N8N_DIR"
cd "$N8N_DIR"

# ====== 检查容器状态 ======
if ! docker compose ps | grep -q $CONTAINER_NAME; then
    echo "⚠️ n8n 容器未运行，请先启动容器"
    exit 1
fi

# ====== 修改 SQLite 数据库用户语言 ======
DB_FILE="$N8N_DATA_DIR/database.sqlite"

if [ ! -f "$DB_FILE" ]; then
    echo "⚠️ 未找到数据库文件: $DB_FILE"
    exit 1
fi

echo "📝 修改所有用户语言为中文 (zh-CN)"
sudo apt-get update -y
sudo apt-get install -y sqlite3

sqlite3 "$DB_FILE" "UPDATE users SET locale='zh-CN';"
echo "✅ 所有用户语言已修改为 zh-CN"

# ====== 重启容器 ======
echo "🔄 重启 n8n 容器..."
docker compose restart $CONTAINER_NAME

# ====== 输出提示 ======
echo "🌐 请使用浏览器访问 http://<你的服务器IP>:5680 （根据 docker-compose.yml 的端口）"
echo "🎉 所有用户界面已设置为中文，请刷新浏览器或使用无痕模式"
