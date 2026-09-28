#!/data/data/com.termux/files/usr/bin/bash
# 显示上次扫描结果（不重新扫描）
set -u
d="$(cd "$(dirname "$0")" && pwd)"; . "$d/env.sh"
require_root "$@"

if [ ! -s "$SCAN_LIST" ]; then
    echo "[-] 还没有扫描结果，先 aicw scan"; exit 1
fi
printf '%3s %s\n' "#" "SSID"
awk -F'\t' '{ printf "%3s %s\n", $1, $2 }' "$SCAN_LIST"
echo
echo "连接:  aicw connect <#序号 或 SSID> [密码]"
