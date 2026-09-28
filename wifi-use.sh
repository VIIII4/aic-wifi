#!/data/data/com.termux/files/usr/bin/bash
# wifi-use.sh aic|mtk  —— 切换默认上行
#   aic : 让无标记流量(root/Termux 等)走 AIC 网卡(aic0)
#   mtk : 撤掉，恢复 Android 默认上行(内置 wlan0 / 移动数据)
# 说明: Android 自家 App 的流量带 fwmark，一直走它自己的网络，不受这里影响。
set -u
d="$(cd "$(dirname "$0")" && pwd)"
. "$d/env.sh"
MODE="${1:-}"
if [ -z "$MODE" ]; then echo "用法: $0 aic|mtk"; exit 1; fi
require_root "$@"

lease_gw() {
    [ -f "$MODDIR/lease" ] && awk -F= '/^gw=/{print $2}' "$MODDIR/lease"
}

case "$MODE" in
aic)
    if [ ! -e "/sys/class/net/$IFACE" ]; then
        echo "[-] 接口 $IFACE 不存在, 请先:  aicw up"; exit 1
    fi
    ip link set "$IFACE" up 2>/dev/null || true
    if ! ip -4 addr show "$IFACE" 2>/dev/null | grep -q 'inet '; then
        echo "[*] $IFACE 还没有 IP, 先跑一次 DHCP ..."
        "$d/wifi-ip.sh"
    fi
    GW="$(ip route show default dev "$IFACE" 2>/dev/null | awk '{print $3; exit}')"
    [ -n "$GW" ] || GW="$(lease_gw)"
    if [ -z "$GW" ]; then
        echo "[-] 不知道网关; 请先  aicw ip"; exit 1
    fi
    ip route replace default via "$GW" dev "$IFACE" onlink
    ip rule del priority 30000 2>/dev/null || true
    ip rule add priority 30000 lookup main
    echo "[+] 默认上行 -> $IFACE  (gw $GW)"
    echo -n "    验证: "; ip route get 8.8.8.8 2>/dev/null | head -1
    ;;
mtk)
    ip rule del priority 30000 2>/dev/null || true
    echo "[+] 已恢复 Android 默认上行 (wlan0/移动数据); $IFACE 仍保持连接"
    echo -n "    现在 8.8.8.8 走: "; ip route get 8.8.8.8 2>/dev/null | head -1
    ;;
*)
    echo "用法: $0 aic|mtk"; exit 1 ;;
esac
