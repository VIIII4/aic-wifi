#!/data/data/com.termux/files/usr/bin/bash
# 状态总览
set -u
d="$(cd "$(dirname "$0")" && pwd)"; . "$d/env.sh"
require_root "$@"
echo "===== wpa_supplicant ====="
wpa status 2>&1 || echo "(supplicant 未运行)"
echo "===== 链路 ====="
"$IW" dev "$IFACE" link 2>&1
echo "===== 地址 ====="
ip -4 -br addr show "$IFACE" 2>/dev/null || echo "(无)"
