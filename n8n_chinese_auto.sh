#!/bin/bash
# 视频操作一键中文化脚本

# 1. 进入 n8n 目录
cd /root/n8n || exit

# 2. 停止容器
docker compose down

# 3. 下载汉化文件
wget -O editor-ui.tar.gz "https://github.com/other-blowsnow/n8n-i18n-chinese/releases/download/n8n%401.117.3/editor-ui.tar.gz"

# 4. 解压覆盖到 n8n 数据目录
mkdir -p /root/.n8n/editor-ui
tar -xzvf editor-ui.tar.gz -C /root/.n8n/editor-ui --strip-components=1

# 5. 启动容器
docker compose up -d

echo "🎉 n8n 已按视频操作完成中文化，请刷新浏览器访问界面（必要时清理缓存或使用无痕模式）"
