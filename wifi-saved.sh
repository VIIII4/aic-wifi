#!/data/data/com.termux/files/usr/bin/bash
# 已保存网络管理:
#   aicw saved                        列出
#   aicw saved add <SSID> [密码] [--hidden]
#   aicw saved forget <SSID|id>       删除
#   aicw saved autoconnect <SSID|id> on|off
set -u
d="$(cd "$(dirname "$0")" && pwd)"; . "$d/env.sh"
require_root "$@"
SUB="${1:-}"; shift 2>/dev/null || true
wpa_running || { echo "[-] supplicant 未运行，先 aicw up"; exit 1; }

case "$SUB" in
    "")
        echo "已保存的网络 (id<TAB>ssid<TAB>flags):"
        wpa list_networks 2>/dev/null
        ;;
    add)
        SSID="${1:-}"; shift 2>/dev/null || true
        PASS=""; HIDDEN=0
        for a in "$@"; do case "$a" in --hidden) HIDDEN=1;; *) [ -z "$PASS" ] && PASS="$a";; esac; done
        [ -n "$SSID" ] || { echo "用法: aicw saved add <SSID> [密码] [--hidden]"; exit 1; }
        ID="$(netid_by_ssid "$SSID")"; [ -n "$ID" ] || ID="$(wpa add_network | tail -1)"
        wpa set_network "$ID" ssid "\"$SSID\"" >/dev/null
        if [ -n "$PASS" ]; then wpa set_network "$ID" psk "\"$PASS\"" >/dev/null; else wpa set_network "$ID" key_mgmt NONE >/dev/null; fi
        [ "$HIDDEN" = 1 ] && wpa set_network "$ID" scan_ssid 1 >/dev/null
        wpa disable_network "$ID" >/dev/null 2>&1 || true
        wpa save_config >/dev/null 2>&1 || true
        echo "[+] 已保存 \"$SSID\" (id=$ID)"
        ;;
    forget)
        ARG="${1:-}"; [ -n "$ARG" ] || { echo "用法: aicw saved forget <SSID|id>"; exit 1; }
        ID="$(netid_by_arg "$ARG")"; [ -n "$ID" ] || { echo "[-] 找不到 $ARG"; exit 1; }
        wpa remove_network "$ID" >/dev/null
        wpa save_config >/dev/null 2>&1 || true
        echo "[+] 已删除网络 id=$ID"
        ;;
    autoconnect)
        ARG="${1:-}"; STATE="${2:-}"
        [ -n "$ARG" ] && [ -n "$STATE" ] || { echo "用法: aicw saved autoconnect <SSID|id> on|off"; exit 1; }
        ID="$(netid_by_arg "$ARG")"; [ -n "$ID" ] || { echo "[-] 找不到 $ARG"; exit 1; }
        case "$STATE" in
            on)  wpa enable_network "$ID" >/dev/null; echo "[+] 已开启自动连接 id=$ID";;
            off) wpa disable_network "$ID" >/dev/null; echo "[+] 已关闭自动连接 id=$ID";;
            *) echo "用法: aicw saved autoconnect <SSID|id> on|off"; exit 1;;
        esac
        wpa save_config >/dev/null 2>&1 || true
        ;;
    *)
        echo "用法: aicw saved [add|forget|autoconnect]"; exit 1 ;;
esac
