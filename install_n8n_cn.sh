#!/bin/bash
# ===================================================
# n8n 中文汉化一键安装脚本 (仅汉化，无其他多余操作)
# 版本: 1.117.3
# 作者: ChatGPT 定制
# ===================================================

# 1. 创建工作目录
mkdir -p /root/n8n-i18n
cd /root/n8n-i18n

# 2. 下载汉化编辑器UI文件
echo "🔽 正在下载 n8n 中文汉化文件..."
wget -O editor-ui.tar.gz "https://github.com/other-blowsnow/n8n-i18n-chinese/releases/download/n8n%401.117.3/editor-ui.tar.gz"

# 3. 解压汉化文件
echo "📦 正在解压..."
mkdir -p /root/n8n-i18n/editor-ui
tar -xzvf editor-ui.tar.gz -C /root/n8n-i18n/editor-ui --strip-components=1

# 4. 启动 n8n（端口15678，对应网页 http://服务器IP:15678）
echo "🚀 正在启动 n8n（中文汉化版）..."
docker run -d --name n8n \
  -p 15678:5678 \
  -v /root/n8n-i18n/editor-ui:/usr/local/lib/node_modules/n8n/node_modules/n8n-editor-ui/dist \
  -v ~/.n8n:/home/node/.n8n \
  -e N8N_DEFAULT_LOCALE=zh-CN \
  -e N8N_SECURE_COOKIE=false \
  n8nio/n8n:1.117.3

echo ""
echo "✅ n8n 汉化版启动完成！"
echo "🌐 请在浏览器中访问: http://你的服务器IP:15678"
echo "⚠️ 若界面仍为英文，请清空浏览器缓存或使用无痕模式访问。"
