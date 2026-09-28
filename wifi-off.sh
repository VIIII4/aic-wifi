#!/data/data/com.termux/files/usr/bin/bash
# 断网但保留驱动：断开连接 + 撤掉 aic0 的地址/路由/策略规则；模块与 supplicant 不卸。
# 与之相对，aicw down 会停 supplicant 并卸载驱动。
set -u
d="$(cd "$(dirname "$0")" && pwd)"; . "$d/env.sh"
require_root "$@"

if wpa_running; then
    wpa disconnect
    # 状态脱节兜底: 若 supplicant 认为没连接，上面的 disconnect 是空操作、不会发 deauth，
    # 驱动层可能仍关联。检测到仍 Connected 则: 停属主 -> 内核补 deauth -> 重启 supplicant。
    if [ -e "/sys/class/net/$IFACE" ] && "$IW" dev "$IFACE" link 2>/dev/null | grep -q '^Connected'; then
        echo "[!] supplicant 状态与驱动脱节，强制 deauth 并重启 supplicant"
        "$WPA_CLI" $WPA_OPTS terminate 2>/dev/null || true
        pkill -f "$WPA_SUPPLICANT" 2>/dev/null || true
        sleep 1
        "$IW" dev "$IFACE" disconnect 2>/dev/null || true
        "$WPA_SUPPLICANT" -Dnl80211 -i "$IFACE" -c "$CONF" -P "$PIDF" -B 2>/dev/null
    fi
    echo "[+] 已断开当前连接"
else
    echo "[*] supplicant 未运行（驱动可能也没加载）"
    [ -e "/sys/class/net/$IFACE" ] && "$IW" dev "$IFACE" disconnect 2>/dev/null || true
fi

ip rule del priority 30000 2>/dev/null || true
ip addr flush dev "$IFACE" 2>/dev/null || true
echo "[+] 已撤除 $IFACE 的地址/默认路由（驱动仍保留）"
echo "    恢复联网:  aicw reconnect && aicw ip    （或  aicw connect <SSID> [密码]）"
