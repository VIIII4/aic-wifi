#!/data/data/com.termux/files/usr/bin/bash
# 停止 wpa_supplicant 并卸载驱动
set -u
d="$(cd "$(dirname "$0")" && pwd)"
. "$d/env.sh"
require_root "$@"

"$WPA_CLI" $WPA_OPTS terminate 2>/dev/null || true
if [ -f "$PIDF" ]; then kill "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null || true; rm -f "$PIDF"; fi
# 撤掉 wifi-ip.sh 加的默认路由与策略路由规则
ip rule del priority 30000 2>/dev/null || true
ip route flush dev "$IFACE" 2>/dev/null || true
ip link set "$IFACE" down 2>/dev/null || true
rmmod aic8800_fdrv 2>/dev/null || true
rmmod aic_load_fw 2>/dev/null || true
echo "[+] 已停止 supplicant 并卸载驱动"
