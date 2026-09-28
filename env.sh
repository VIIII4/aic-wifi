#!/data/data/com.termux/files/usr/bin/bash
# 公共配置与函数，被其它脚本 source。所有路径写死，避免提权后环境丢失。

PREFIX=/data/data/com.termux/files/usr
export LD_LIBRARY_PATH=$PREFIX/lib

IW=$PREFIX/bin/iw
WPA_SUPPLICANT=$PREFIX/bin/wpa_supplicant
WPA_CLI=$PREFIX/bin/wpa_cli
PYTHON=$PREFIX/bin/python3

MODDIR=/data/local/tmp/aic
FW_DIR=$MODDIR/fw
IFACE=aic0
CTRL=$MODDIR/wpa_ctrl
CONF=$MODDIR/wpa.conf
PIDF=$MODDIR/wpa.pid
LOG=$MODDIR/wpa.log
LOADFW_KO=$MODDIR/aic_load_fw_stub.ko
FDRV_KO=$MODDIR/aic8800_fdrv_fixed.ko
FDRV_MD5=0ab38508b24e2a3b03f36ab7f96ab1b5
SCAN_LIST=$MODDIR/scan_list          # 序号<TAB>SSID
SCAN_RAW=$MODDIR/scan_results

WPA_OPTS="-p $CTRL -i $IFACE"

# 若当前不是 root，用 su 重新执行自己（KernelSU 的 su）。
require_root() {
    [ "$(id -u)" = "0" ] && return 0
    self="$0"
    case "$self" in
        /*) ;;
        *) self="$(cd "$(dirname "$self")" 2>/dev/null && pwd)/$(basename "$self")" ;;
    esac
    echo "[*] 需要 root，正在提权 ..."
    exec su -c "$(printf '%q ' "$self" "$@")"
}

# 芯片是否已进入运行态 (PID 8d81)
chip_is_runtime() {
    grep -lqs '8d81' /sys/bus/usb/devices/*/idProduct 2>/dev/null
}

wpa_running() {
    [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null
}

# wpa_cli 快捷
wpa() { "$WPA_CLI" $WPA_OPTS "$@"; }

# 由 SSID 找已保存的 network id
netid_by_ssid() {
    wpa list_networks 2>/dev/null | awk -F'\t' -v s="$1" '$2==s {print $1; exit}'
}

# 参数可为 network id(数字) 或 SSID；优先按 SSID 精确匹配，避免纯数字 SSID 歧义
netid_by_arg() {
    local id
    id="$(netid_by_ssid "$1")"
    if [ -n "$id" ]; then echo "$id"; return; fi
    case "$1" in
        ''|*[!0-9]*) return ;;
        *) echo "$1" ;;
    esac
}
