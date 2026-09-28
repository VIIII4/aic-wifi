#!/data/data/com.termux/files/usr/bin/bash
# 信号 / 速率
set -u
d="$(cd "$(dirname "$0")" && pwd)"; . "$d/env.sh"
require_root "$@"
wpa signal_poll 2>/dev/null
echo "----"
"$IW" dev "$IFACE" link 2>/dev/null | grep -E 'SSID|freq|signal|bitrate'
