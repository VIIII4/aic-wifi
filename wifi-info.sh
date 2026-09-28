#!/data/data/com.termux/files/usr/bin/bash
# 网络层信息：地址/网关/DNS/路由/当前默认上行
set -u
d="$(cd "$(dirname "$0")" && pwd)"; . "$d/env.sh"
require_root "$@"
echo "== 接口 =="; ip -br addr show "$IFACE" 2>/dev/null || echo "  $IFACE 不存在"
echo "== 网关/路由 (table main) =="; ip route show dev "$IFACE" 2>/dev/null
echo "== DNS =="
[ -f "$MODDIR/resolv.conf" ] && cat "$MODDIR/resolv.conf" || echo "  (未获取)"
echo "== 默认上行测试 =="
r=$(ip route get 8.8.8.8 2>/dev/null | head -1)
echo "  8.8.8.8 -> $r"
case "$r" in
    *"dev $IFACE"*) echo "  当前走: AIC ($IFACE)";;
    *) echo "  当前走: 其它 (内置 WiFi/移动数据)";;
esac
