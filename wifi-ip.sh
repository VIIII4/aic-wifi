#!/data/data/com.termux/files/usr/bin/bash
# 通过内置 Python DHCP 客户端给 wlan1 拿 IP 并配路由
set -u
d="$(cd "$(dirname "$0")" && pwd)"
. "$d/env.sh"
require_root "$@"
ip link set "$IFACE" up 2>/dev/null || true
"$PYTHON" "$d/dhcp.py" "$IFACE"
echo "===== 地址/路由 ====="
ip -4 addr show "$IFACE" | grep inet || true
ip route | grep "$IFACE" || true
