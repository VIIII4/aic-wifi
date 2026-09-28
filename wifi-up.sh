#!/data/data/com.termux/files/usr/bin/bash
# 加载 AIC8800 驱动：固件下载 -> 网卡驱动 -> 起接口 -> 起 wpa_supplicant
set -u
d="$(cd "$(dirname "$0")" && pwd)"
. "$d/env.sh"
require_root "$@"

echo "[*] 关闭 SELinux 强制 (固件在 /data 需 permissive)"
setenforce 0 2>/dev/null || echo "    (setenforce 不可用，忽略)"

echo "[*] 固件搜索路径 -> $FW_DIR"
echo -n "$FW_DIR" > /sys/module/firmware_class/parameters/path

# aic_load_fw 是 aic8800_fdrv 的符号提供者（get_flash_bin_size / aicwf_prealloc_rxbuff_*
# 等），无论芯片是否已是运行态都必须加载，否则 fdrv insmod 会 "Unknown symbol"。
if ! lsmod | grep -q '^aic_load_fw '; then
    echo "[*] insmod $(basename "$LOADFW_KO")（同时为 fdrv 提供符号）"
    insmod "$LOADFW_KO" || { echo "[-] insmod load_fw 失败"; exit 1; }
fi

if chip_is_runtime; then
    echo "[*] 芯片已在运行态 8d81，跳过固件下载"
else
    echo -n "[*] 等待芯片重枚举为 8d81 "
    ok=0
    for i in $(seq 1 20); do
        if chip_is_runtime; then ok=1; break; fi
        echo -n "."; sleep 1
    done
    echo
    [ "$ok" = 1 ] && echo "[+] 芯片运行态 8d81 就绪" || echo "[!] 未检测到 8d81，继续尝试"
fi

if ! lsmod | grep -q '^aic8800_fdrv '; then
    if [ "$(md5sum "$FDRV_KO" 2>/dev/null | cut -d' ' -f1)" != "$FDRV_MD5" ]; then
        echo "[!] 警告: $(basename "$FDRV_KO") 校验和不符(可能被硬复位损坏)"
        echo "    若 insmod 报 Exec format error，请重新 push 模块后 sync"
    fi
    echo "[*] insmod $(basename "$FDRV_KO")"
    insmod "$FDRV_KO" || { echo "[-] insmod fdrv 失败"; exit 1; }
fi

ip link set "$IFACE" up
# USB probe 是异步的：insmod 返回时接口可能还没建出来，等它出现再起 supplicant
echo -n "[*] 等待接口 $IFACE 出现 "
for i in $(seq 1 20); do
    [ -e "/sys/class/net/$IFACE" ] && break
    echo -n "."; sleep 1
done
echo
if [ ! -e "/sys/class/net/$IFACE" ]; then
    echo "[-] 接口 $IFACE 未出现，驱动可能未 probe 成功"; exit 1
fi
ip link set "$IFACE" up
echo "[+] 驱动就绪: $IFACE 已 up"

mkdir -p "$CTRL"; chmod 777 "$CTRL"

if ! wpa_running; then
    echo "[*] 启动 wpa_supplicant"
    [ -s "$CONF" ] || { echo "    (无 $CONF，先创建一个空配置)"; printf 'ctrl_interface=%s\nupdate_config=1\n' "$CTRL" > "$CONF"; }
    # 强制 ctrl_interface 指向当前 MODDIR：迁移目录/换路径后旧配置里的绝对路径会使 supplicant 起不来
    sed -i "s#^ctrl_interface=.*#ctrl_interface=$CTRL#" "$CONF"
    "$WPA_SUPPLICANT" -Dnl80211 -i "$IFACE" -c "$CONF" -P "$PIDF" -B
    sleep 3
fi

"$WPA_CLI" $WPA_OPTS status 2>/dev/null | grep -E 'ssid|wpa_state|address' || true
echo "[+] 完成。连接: $d/wifi-connect.sh <SSID> [密码]"
