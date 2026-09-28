#!/data/data/com.termux/files/usr/bin/bash
# 扫描并列出周围 WiFi（按信号从强到弱），并记录序号供 connect/list 使用
set -u
d="$(cd "$(dirname "$0")" && pwd)"; . "$d/env.sh"
require_root "$@"

[ -e "/sys/class/net/$IFACE" ] || { echo "[-] 接口 $IFACE 不存在，先 aicw up"; exit 1; }
wpa_running || { echo "[-] supplicant 未运行，先 aicw up"; exit 1; }

echo "[*] 扫描中（约 6s）..."
wpa scan >/dev/null 2>&1
sleep 6
RAW="$(wpa scan_results 2>/dev/null)"
printf '%s\n' "$RAW" > "$SCAN_RAW"
: > "$SCAN_LIST"

printf '%3s %6s %6s  %-5s %s\n' "#" "SIG" "FREQ" "SEC" "SSID"
printf '%s\n' "$RAW" | awk -F'\t' '
    NF>=5 && $1 !~ /^bssid/ {
        sec="OPEN";
        if ($4 ~ /WPA3/) sec="WPA3";
        else if ($4 ~ /WPA2/) sec="WPA2";
        else if ($4 ~ /WPA/) sec="WPA";
        else if ($4 ~ /WEP/) sec="WEP";
        printf "%s\t%s\t%s\t%s\n", $3, $2, sec, $5;
    }' | sort -k1,1 -n -r | awk -F'\t' -v list="$SCAN_LIST" '
    { n++; printf "%3d %6s %6s  %-5s %s\n", n, $1, $2, $3, $4;
      printf "%d\t%s\n", n, $4 >> list }'

echo
echo "连接:  aicw connect <#序号 或 SSID> [密码]"
