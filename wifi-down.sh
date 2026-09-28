#!/data/data/com.termux/files/usr/bin/bash
# 停止 wpa_supplicant 并卸载驱动
set -u
d="$(cd "$(dirname "$0")" && pwd)"
. "$d/env.sh"
require_root "$@"

# 停 supplicant（wdev 的 MLME 命令只允许属主发，属主退出后外部才能接管）
"$WPA_CLI" $WPA_OPTS terminate 2>/dev/null || true
if [ -f "$PIDF" ]; then kill "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null || true; rm -f "$PIDF"; fi
pkill -f "$WPA_SUPPLICANT" 2>/dev/null || true
sleep 1
# 兜底: supplicant 异常退出/状态脱节时不会发 deauth，驱动层可能仍关联着 AP。
# 此时属主已退出，由内核直接补一发 deauth（否则固件里的僵尸关联会一直拒绝新 MLME 命令）。
[ -e "/sys/class/net/$IFACE" ] && "$IW" dev "$IFACE" disconnect 2>/dev/null || true
# 撤掉 wifi-ip.sh 加的默认路由与策略路由规则
ip rule del priority 30000 2>/dev/null || true
ip route flush dev "$IFACE" 2>/dev/null || true
ip link set "$IFACE" down 2>/dev/null || true
rmmod aic8800_fdrv 2>/dev/null || true
rmmod aic_load_fw 2>/dev/null || true
echo "[+] 已停止 supplicant 并卸载驱动"
