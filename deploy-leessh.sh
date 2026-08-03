#!/bin/bash
# LEESSH 一键部署脚本
# 用法: bash deploy-leessh.sh [端口]  (默认端口 8091)
# 功能: 部署主程序 + 生成uuid + 部署网址快捷方式扩展 + systemd服务

set -e
PORT=${1:-8091}
INSTALL_DIR="/opt/gmssh"
EXT_DIR="/opt/gmssh-links"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=============================================="
echo "  LEESSH 一键部署"
echo "=============================================="

# 1. root检查
if [ "$(id -u)" != "0" ]; then
  echo "错误: 需要root权限"
  exit 1
fi

# 2. 部署主程序
echo "[1/6] 部署 GMSSH 主程序..."
mkdir -p "$INSTALL_DIR"
cp -r "$SCRIPT_DIR"/bin "$SCRIPT_DIR"/config "$SCRIPT_DIR"/new_www \
      "$SCRIPT_DIR"/www "$SCRIPT_DIR"/resources "$SCRIPT_DIR"/ga \
      "$SCRIPT_DIR"/deploy.sh "$INSTALL_DIR"/ 2>/dev/null || true
chmod +x "$INSTALL_DIR/bin/gs_main" "$INSTALL_DIR/deploy.sh" 2>/dev/null || true

# 3. 配置端口
echo "[2/6] 配置端口 $PORT..."
if [ -f "$INSTALL_DIR/config/config.json" ]; then
  sed -i "s/\"http_port\": \"[0-9]*\"/\"http_port\": \"$PORT\"/" "$INSTALL_DIR/config/config.json"
fi

# 4. 生成 uuid（关键！缺失会导致 read version file fail）
echo "[3/6] 生成设备 uuid..."
NEW_UUID=$(cat /proc/sys/kernel/random/uuid)
cat > "$INSTALL_DIR/bin/.uuid.json" <<EOF
{
  "arch": "$(uname -m)",
  "dti": 2,
  "uuid": "$NEW_UUID",
  "status": "active"
}
EOF
echo "     uuid: $NEW_UUID"

# 5. 注册 GMSSH 主服务
echo "[4/6] 注册 systemd 服务..."
cat > /etc/systemd/system/gmssh.service <<EOF
[Unit]
Description=GMSSH - AI Ops Terminal Service
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/bin/gs_main http -c $INSTALL_DIR/config/config.json
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 6. 部署网址快捷方式扩展
echo "[5/6] 部署网址快捷方式扩展..."
if [ -d "$SCRIPT_DIR/extensions" ]; then
  mkdir -p "$EXT_DIR"
  cp "$SCRIPT_DIR"/extensions/server.py "$SCRIPT_DIR"/extensions/gmssh-link.py "$EXT_DIR"/ 2>/dev/null || true
  chmod +x "$EXT_DIR/server.py" "$EXT_DIR/gmssh-link.py" 2>/dev/null || true
  cat > /etc/systemd/system/gmssh-links.service <<EOF
[Unit]
Description=GMSSH URL link server
After=network.target gmssh.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 $EXT_DIR/server.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
fi

# 启动
echo "[6/6] 启动服务..."
systemctl daemon-reload
systemctl enable gmssh 2>/dev/null || true
systemctl enable gmssh-links 2>/dev/null || true
systemctl restart gmssh
sleep 2
systemctl restart gmssh-links 2>/dev/null || true
sleep 1

echo ""
echo "=============================================="
echo "  部署完成！"
echo "  访问: http://<服务器IP>:$PORT/newweb/"
echo "  管理界面: http://<服务器IP>:9089/admin"
echo "  服务状态: systemctl status gmssh gmssh-links"
echo "=============================================="
