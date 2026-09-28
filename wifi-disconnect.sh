#!/data/data/com.termux/files/usr/bin/bash
# 断开当前连接（不清除保存的网络）
set -u
d="$(cd "$(dirname "$0")" && pwd)"; . "$d/env.sh"
require_root "$@"
wpa_running || { echo "[-] supplicant 未运行"; exit 1; }
wpa disconnect
echo "[+] 已断开"
