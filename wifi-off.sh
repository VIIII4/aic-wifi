#!/data/data/com.termux/files/usr/bin/bash
# 断网但保留驱动：断开连接 + 撤掉 aic0 的地址/路由/策略规则；模块与 supplicant 不卸。
# 与之相对，aicw down 会停 supplicant 并卸载驱动。
set -u
d="$(cd "$(dirname "$0")" && pwd)"; . "$d/env.sh"
require_root "$@"

if wpa_running; then
    wpa disconnect
    echo "[+] 已断开当前连接"
else
    echo "[*] supplicant 未运行（驱动可能也没加载）"
fi

ip rule del priority 30000 2>/dev/null || true
ip addr flush dev "$IFACE" 2>/dev/null || true
echo "[+] 已撤除 $IFACE 的地址/默认路由（驱动仍保留）"
echo "    恢复联网:  aicw reconnect && aicw ip    （或  aicw connect <SSID> [密码]）"
