#!/bin/bash
# GMSSH/LEESSH 网址快捷方式扩展 - 远端一键部署脚本
# 用法: bash deploy-gmssh-links.sh [重定向起始端口]
# 默认端口: 9089(管理界面), 9090+(快捷方式)

set -e

BASE_PORT=${1:-9089}
EXT_DIR="/opt/gmssh-links"
DESKTOP_DIR="/.__gmssh/desktop"
SERVICE_FILE="/etc/systemd/system/gmssh-links.service"

echo "=============================================="
echo "  LEESSH/GMSSH 网址快捷方式扩展部署"
echo "=============================================="

# 1. 检查root
if [ "$(id -u)" != "0" ]; then
  echo "错误: 需要root权限，请用 sudo 执行"
  exit 1
fi

# 2. 创建目录
mkdir -p "$EXT_DIR"
echo "[1/6] 目录创建完成: $EXT_DIR"

# 3. 检查是否已有 server.py 和 gmssh-link.py（从本机复制）
if [ ! -f "$EXT_DIR/server.py" ]; then
  echo "错误: 缺少 $EXT_DIR/server.py"
  echo "请先把本机的 server.py 和 gmssh-link.py 上传到 $EXT_DIR/"
  exit 1
fi

# 4. 确保脚本可执行
chmod +x "$EXT_DIR/server.py" "$EXT_DIR/gmssh-link.py" 2>/dev/null || true
echo "[2/6] 脚本就绪"

# 5. 生成 systemd 服务
cat > "$SERVICE_FILE" <<EOF
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
echo "[3/6] systemd 服务已创建"

# 6. 启动服务
systemctl daemon-reload
systemctl enable gmssh-links 2>/dev/null || true
systemctl restart gmssh-links
sleep 1
if systemctl is-active gmssh-links >/dev/null 2>&1; then
  echo "[4/6] gmssh-links 服务已启动"
else
  echo "[!] 服务启动失败，请检查: journalctl -u gmssh-links"
fi

# 7. 检查桌面目录
mkdir -p "$DESKTOP_DIR"
echo "[5/6] 桌面目录就绪: $DESKTOP_DIR"

# 8. 验证
echo "[6/6] 验证服务状态:"
systemctl status gmssh-links --no-pager | head -5
echo ""
echo "=============================================="
echo "  部署完成！"
echo "  管理界面: http://<本机IP>:$BASE_PORT/admin"
echo "  确认服务: systemctl status gmssh-links"
echo "  查看日志: journalctl -u gmssh-links"
echo "=============================================="
