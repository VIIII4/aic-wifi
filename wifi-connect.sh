#!/data/data/com.termux/files/usr/bin/bash
# 连接 WiFi:  aicw connect <SSID|#序号> [密码] [--hidden]
#   无密码 = 开放网络;  --hidden = 隐藏 SSID
set -u
d="$(cd "$(dirname "$0")" && pwd)"; . "$d/env.sh"
require_root "$@"

SSIDARG="${1:-}"; shift 2>/dev/null || true
PASS=""; HIDDEN=0
for a in "$@"; do
    case "$a" in
        --hidden) HIDDEN=1 ;;
        *) [ -z "$PASS" ] && PASS="$a" ;;
    esac
done

if [ -z "$SSIDARG" ]; then echo "用法: aicw connect <SSID|#序号> [密码] [--hidden]"; exit 1; fi

# 解析 #序号
case "$SSIDARG" in
    \#*)
        idx=${SSIDARG#\#}
        SSID="$(awk -F'\t' -v n="$idx" '$1==n{print $2; exit}' "$SCAN_LIST" 2>/dev/null)"
        [ -n "$SSID" ] || { echo "[-] 无效序号 $idx（先 aicw scan）"; exit 1; }
        ;;
    *) SSID="$SSIDARG" ;;
esac

[ -e "/sys/class/net/$IFACE" ] || { echo "[-] 接口 $IFACE 不存在，先 aicw up"; exit 1; }
wpa_running || "$d/wifi-up.sh" >/dev/null 2>&1
wpa_running || { echo "[-] supplicant 起不来，先 aicw up"; exit 1; }

wpa disconnect >/dev/null 2>&1 || true
ID="$(netid_by_ssid "$SSID")"
[ -n "$ID" ] || ID="$(wpa add_network 2>/dev/null | tail -1)"
[ -n "$ID" ] || { echo "[-] add_network 失败"; exit 1; }

wpa set_network "$ID" ssid "\"$SSID\"" >/dev/null
if [ -n "$PASS" ]; then
    wpa set_network "$ID" psk "\"$PASS\"" >/dev/null
else
    wpa set_network "$ID" key_mgmt NONE >/dev/null
fi
[ "$HIDDEN" = 1 ] && wpa set_network "$ID" scan_ssid 1 >/dev/null
wpa enable_network "$ID" >/dev/null 2>&1 || true
wpa select_network "$ID" >/dev/null

echo "[*] 正在连接 \"$SSID\" ..."
st=""
for i in $(seq 1 25); do
    st="$(wpa status 2>/dev/null | awk -F= '/wpa_state/{print $2}')"
    [ "$st" = "COMPLETED" ] && break
    [ "$st" = "4WAY_HANDSHAKE" ] && echo "    4-way handshake ..."
    sleep 1
done

wpa save_config >/dev/null 2>&1 || true

if [ "$st" = "COMPLETED" ]; then
    wpa status 2>/dev/null | grep -E 'ssid|bssid|wpa_state|key_mgmt|address'
    "$IW" dev "$IFACE" link 2>/dev/null | grep -E 'SSID|signal|bitrate'
    echo "[+] 已连上 \"$SSID\"。取 IP:  aicw ip"
else
    echo "[-] 未完成连接 (state=$st)"
    echo "    再试: aicw reconnect   /   看: aicw status"
    exit 1
fi
