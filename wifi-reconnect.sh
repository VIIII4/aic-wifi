#!/data/data/com.termux/files/usr/bin/bash
# 重新连接
set -u
d="$(cd "$(dirname "$0")" && pwd)"; . "$d/env.sh"
require_root "$@"
wpa_running || { echo "[-] supplicant 未运行，先 aicw up"; exit 1; }
wpa reconnect
echo -n "[*] 等待 "
st=""
for i in $(seq 1 20); do
    st="$(wpa status 2>/dev/null | awk -F= '/wpa_state/{print $2}')"
    [ "$st" = "COMPLETED" ] && break
    echo -n "."; sleep 1
done
echo
if [ "$st" = "COMPLETED" ]; then
    wpa status 2>/dev/null | grep -E 'ssid|bssid|wpa_state|address'
else
    echo "[-] state=$st"
fi
