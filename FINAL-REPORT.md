# AIC8800D80 USB WiFi 在联想 TB335FC（Android 15 / GKI）移植 —— 最终完成记录

- 记录日期：2026-09-28（同日从「仍卡住」到「完整跑通」）
- 目标设备：Lenovo TB335FC（MTK MT8755，Android 15，KernelSU root）
- 内核：`5.15.170-android13-8-00003-g9a0b9d56c900-ab13225392`（GKI）
- 网卡：AIC8800D80 USB（`a69c:8d80` bootrom → 固件加载后自复位重枚举为 `8d81`）
- 运行 MAC：`XX:XX:XX:XX:XX:XX`
- 结论：**全流程打通**——驱动加载 → 扫描 → 连接 → DHCP 拿 IP → **通过它上网** → 与内置 WiFi 切换上行。

---

## 0. TL;DR（一句话版）

之前「一注册网卡就整机硬复位」的锅**不是 MTK 私有 cfg80211 的玄学**，而是
`struct cfg80211_ops` **ABI 错位 0x10**（我们少编译了 `CONFIG_NL80211_TESTMODE` 两个字段）。
修好后又有两个新坑：MTK 自带 wlan 驱动**按名字 `wlan*` 抢认**我们的接口导致配 IP 崩、
`aic8800_fdrv` 依赖 `aic_load_fw` 的符号、以及 Android 策略路由。全部解决后即可上网。

| 阶段 | 真因 | 修复 |
|---|---|---|
| 加载即崩（硬复位） | `struct cfg80211_ops` 少 `testmode_cmd/testmode_dump`，回调表整体错位 0x10 | 编译加 `-DCONFIG_NL80211_TESTMODE` |
| 配 IP 崩（NULL+0x18） | MTK wlan 的 inetaddr notifier 用 `strncmp(name,"wlan",4)` 抢认我们的 `wlan1` | 接口改名 `aic%d`（→ `aic0`） |
| insmod `Unknown symbol` | `aic8800_fdrv` 需要 `aic_load_fw` 导出的 `get_flash_bin_size` 等符号 | 先加载 `aic_load_fw`（即使芯片已是 8d81） |
| 能连不能上网 | Android 策略路由把无标记流量丢给 wlan0/不可达 | 加 `default ... onlink` + `ip rule priority 30000 lookup main` |
| 偶发再次崩/文件坏 | 与网卡无关的背景性 MMC/`blocktag` 崩溃；硬复位损坏未落盘文件 | md5 校验 + `sync` |

---

## 1. 目标与背景

- 让外接 AIC8800D80 USB 网卡在这台平板上工作并能上网。
- 平板内置 MTK WiFi（`wlan0`）已连 `HomeWiFi`（本机通过它走无线 adb）。
- 无线 adb：`setprop service.adb.tcp.port 5555; stop adbd; start adbd`，宿主 `adb connect <平板IP>:5555`。
- 承接：`Android平板AIC8800移植-调试验证汇总.md`（记录了前半程「卡在 cfg80211_register_netdevice」）。

---

## 2. 最终成果（实测）

- 两个**独立**网卡同时在线：内置 `wlan0`（连 HomeWiFi）+ USB `aic0`（连 MyHotspot）。
- `aic0` 能扫描 / 关联 / WPA2 四次握手 / 收发数据 / DHCP / 上网：
  ```
  iw dev aic0 link  → SSID: MyHotspot, HE-MCS 11, rx 143.3 Mbit/s, signal -45 dBm
  DHCP              → 192.168.x.x/24  gw/dns 192.168.x.x
  ip route get 8.8.8.8 → via 192.168.x.x dev aic0
  ping 8.8.8.8      → 0% loss
  curl https://www.baidu.com → HTTP 200
  ```
- 提供完整管理器：设备端 `aicw`、宿主端 `awifi`（经 adb）。

---

## 3. 根因与修复（详细）

### 3.1 【真因 A】`struct cfg80211_ops` ABI 错位 0x10 ← 导致所有注册硬复位

**现象**：`cfg80211_register_netdevice(ndev)` 一调用就整机硬复位（`bootreason=kernel_panic`），无 panic 日志。

**定位过程**：
1. 用 kprobe 面包屑模块（`bctrace`，入口 `printk` → `/dev/kmsg` 实时抓）得到调用链：
   `cfg80211_register_netdevice → register_netdevice → cfg80211_netdev_notifier_call(POST_INIT) → netdev_register_kobject → device_add → …queue 注册 → 静默复位`。
2. 关键旁证：驱动明明同时设了 `.remain_on_channel` 和 `.cancel_remain_on_channel`，但 stock cfg80211 的
   `wiphy_new_nm` 仍报 `WARN_ON(ops->remain_on_channel && !ops->cancel_remain_on_channel)`（`core.c:436`）
   → **它读到的不是我们写的字段**。
3. 反汇编设备端 `cfg80211_stock.ko` 的 `wiphy_new_nm`：这些 WARN 检查直接揭示了 stock 的字段偏移：
   `add_key=0x40, del_key=0x50, set_default_key=0x58, start_ap=0x70, stop_ap=0x80, remain_on_channel=0x1f0, cancel=0x1f8, start_p2p_device=0x288 …`
4. 从我们的模块 `rwnx_cfg80211_ops` 的**重定位**提取我们的偏移：
   `remain_on_channel=0x1e0, cancel=0x1e8, start_p2p_device=0x278 …` —— **差 0x10**。
5. 写最小模块 `opstest` 验证：加 `-DCONFIG_NL80211_TESTMODE` 后偏移精确变成 0x1f0/0x1f8/0x288，与 stock 完全一致。

**根因**：设备端 MTK 私有 `cfg80211.ko`（build-id `99235641ffc8f7725defef730d9500f1019b7aff`，
vermagic `…gcdc15e5f4c1c`）编译时开了 `CONFIG_NL80211_TESTMODE=y`，其 `struct cfg80211_ops`
在 `get_tx_power` 之后多 `testmode_cmd`/`testmode_dump` 两个指针（`include/net/cfg80211.h` 里由
`#ifdef CONFIG_NL80211_TESTMODE` 包着）。而我们的 kout 配置是 `# CONFIG_CFG80211 is not set`
→ 宏未定义 → 结构体少 2 个字段 → 其后所有回调偏移整体前移 0x10 → cfg80211 调到错误函数指针 → panic。

**修复**：`aic8800_fdrv/Makefile` 的 `EXTRA_CFLAGS` 加：
```make
EXTRA_CFLAGS += -DCONFIG_NL80211_TESTMODE
```
> 顺带校正旧文档的错误结论：文档把「极简模块 cfgmin 也崩」当决定性证据，其实 `cfgmin_setup()`
> 没设 `dev->netdev_ops`，是 `register_netdevice()`（`net/core/dev.c:10302`）里的 NULL 解引用，
> 与 cfg80211 无关。**别再用 cfgmin 当证据。**

### 3.2 【真因 B】MTK wlan 驱动按名字抢认 → 给 `wlan1` 配 IP 崩

**现象**：驱动能加载、能关联、能收发包；一旦给接口配地址（DHCP 的 `ip addr add`）就硬复位。

**定位过程**（这次的 Oops 被**实时 `/dev/kmsg` 抓到了**，pstore 抓不到）：
```
[wlan][19487]netdev_event:(REQ INFO) netdev_event: set net addr
Unable to handle kernel NULL pointer dereference at virtual address 0000000000000018
```
崩在 MTK 自带 `wlan_drv_gen4m_6835` 的 `netdev_event`（`mtkwlan.ko` 本地符号，偏移 0xff450）。
反汇编它 + 读重定位/rodata：
```c
if (strncmp(dev->name, "p2p", 3) == 0 || strncmp(dev->name, "wlan", 4) == 0) {
        glue = netdev_priv(dev);                    // 把我们的 rwnx_vif 当 MTK GLUE_INFO
        kalSetNetAddressFromInterface(glue, dev, 1); // 结构体不同 → NULL+0x18 崩
}
```
即 MTK 只按**接口名前缀**判断是不是自己的网卡；我们的接口叫 `wlan1`，正好命中 `"wlan"`。

**修复**：源码把初始接口名 `"wlan%d"` 改成 `"aic%d"`（`p2p%d`→`aip%d`），
`rwnx_interface_add(...)` 调用处改（`rwnx_main.c`）。这样 MTK notifier 直接跳过我们的接口。

### 3.3 【真因 C】`aic8800_fdrv` 依赖 `aic_load_fw` 的符号

**现象**：只加载 fdrv（不加载 load_fw）时报 `insmod: No such file or directory`（其实是 `Unknown symbol`）：
```
aic8800_fdrv: Unknown symbol get_flash_bin_size / get_flash_bin_crc / get_adap_test /
              aicwf_prealloc_rxbuff_alloc / aicwf_prealloc_rxbuff_free / aicwf_rxbuff_size_get
```
**修复**：`aic_load_fw` 无论芯片是否已是运行态都必须先加载（它是 fdrv 的符号提供者）。
`wifi-up.sh` 已改为「先确保 load_fw 已加载，再判断 8d80/8d81」。

### 3.4 【真因 D】Android 策略路由 → 能连不能上网

`ip rule` 把**无标记流量**（root/Termux 等）默认送到 `wlan0` 表或 `unreachable`。
**修复**（`wifi-ip.sh` / `dhcp.py` 的 `aicw ip`）：
```sh
ip addr add <ip>/<pref> dev aic0
ip route replace default via <gw> dev aic0 onlink
ip rule del priority 30000; ip rule add priority 30000 lookup main
```
让无标记流量在 Android 的 31000/32000 规则之前先查 `main`（其中默认路由指向 aic0）。
Android 带 fwmark 的 App 流量不受影响。

### 3.5 其它坑（都已在脚本里处理）
- **硬复位损坏未落盘文件**：出现过 `aic8800_fdrv_fixed.ko` 被写坏（`insmod: Exec format error`，md5 不符）。
  脚本对模块做 md5 校验；`install.sh` 推完 `sync`。
- **USB probe 异步**：`insmod` 返回时 `aic0` 可能还没建出来 → supplicant 起早失败。
  `wifi-up.sh` 加了「等待接口出现」。
- **提权丢参**：`require_root "$@"` 若放在解析参数之后，`su` 重执行会丢失已 `shift` 的参数。
  已改为**解析前**先提权。
- **SELinux**：固件在 `/data` 需 permissive（脚本自动 `setenforce 0`）；正式方案应放 `/vendor/firmware`。
- **`rmmod` 后芯片仍在 8d81**：下次 `up` 不要重新走 bootrom 下载（已处理）。
- **背景性硬复位**：平板本身有与网卡无关的 MMC/`blocktag` 崩溃（`getprop ro.boot.bootreason=kernel_panic`），排错时先排除它。

---

## 4. 诊断方法论（有复用价值）

1. **分段模块参数早退**：给驱动加 `aic_probe_stage/aic_if_stage` 等参数，每段早退一次，逐级二分。
2. **kprobe 面包屑 + printk**：写 `bctrace`（对目标函数入口 `printk`），实时 `adb shell cat /dev/kmsg` 抓取，
   静默硬复位前最后一条 printk 就是现场。
3. **直接反汇编设备端 `.ko`**：`llvm-objdump` + `readelf -r`（重定位揭示结构体字段偏移）
   + `readelf -SW` 读 `.rodata` 字符串 —— 无需源码即可还原 ABI 与逻辑。
4. **最小复现模块**：`opstest`（只放一个 `struct cfg80211_ops`）验证编译宏对布局的影响。
5. **BTF 对比**：`bpftool btf dump` 对比设备核心与我们构建的内核，核对 `net_device/wireless_dev` 等偏移。
6. **注意**：本机 `panic_on_oops=0` 也无效（是硬复位）；`pstore` 抓不到我们的崩溃，
   必须靠**实时 `/dev/kmsg`**。

---

## 5. 产物清单与位置

### 设备端 · Termux（日常操作）
- `$PREFIX/bin/aicw`：主命令
- `$PREFIX/bin/ax`：环境归一化助手（给宿主 adb 用）
- `~/aic-wifi/`：`env.sh` `wifi-up.sh` `wifi-off.sh` `wifi-down.sh` `wifi-scan.sh` `wifi-list.sh`
  `wifi-connect.sh` `wifi-disconnect.sh` `wifi-reconnect.sh` `wifi-status.sh` `wifi-signal.sh`
  `wifi-info.sh` `wifi-saved.sh` `wifi-ip.sh` `wifi-use.sh` `dhcp.py` `aicw` `README.md`
- `/data/local/tmp/aic/`：
  - `aic_load_fw_stub.ko`（176056 B, md5 `8988e0bdf29f85ab023166b3c41dc38c`）
  - `aic8800_fdrv_fixed.ko`（1460360 B, md5 `4518fb9592a773215afe3191857809af`）
  - `fw/`（18 个固件文件）
  > 发布的预编译版已剥离 DWARF 调试段（体积 22MB→1.4MB，功能不变，实测加载/联网正常）；
  > 构建原始产出的 md5 分别为 `4711fbc2…`/`0ab38508…`，与上文排错过程中引用的一致。

### 宿主端（PC）
- 套件源码：`~/aic-wifi-adb/`（`awifi` `ax` `install.sh` 及各脚本 + README）
- 宿主命令：`/usr/bin/awifi`
- 驱动源码（含修复）：`~/aic8800-work/aic8800-radxa/`
- 内核构建树：`~/aic8800-work/kout/`（ACK `9a0b9d56c900` + 设备 config）
- 内核源码：`<kernel-src>/kernel-common/`
- 工具链：`PATH=/usr/lib/llvm-19/bin`
- 诊断模块：`~/aic8800-work/bctrace/`、`.../opstest/`

---

## 6. 命令手册（简表）

设备 Termux（宿主对应 `awifi <同名子命令>`）：
```
生命周期:  aicw up | off | down | restart
扫描:      aicw scan | list
连接:      aicw connect <SSID|#序号> [密码] [--hidden] | disconnect | reconnect
状态:      aicw status | signal | info
已保存:    aicw saved [add|forget|autoconnect]
上网/出口: aicw ip | aic | mtk
其它:      aicw sh | help
```
- `up` 加载驱动；`off` 只断网保留驱动；`down` 停 supplicant 并卸载；`restart` 重载（已存网络自动重连）。
- `ip` = DHCP + 默认路由 + 策略规则；`aic`/`mtk` 切换默认上行。
完整说明见 `~/aic-wifi/README.md`。

---

## 7. 复现步骤

### 7.1 构建修复版驱动
```sh
# aic8800_fdrv/Makefile 里确保有:
#   EXTRA_CFLAGS += -DCONFIG_NL80211_TESTMODE
# rwnx_main.c 里初始接口名改为 "aic%d" (p2p 改 "aip%d")
export PATH=/usr/lib/llvm-19/bin:$PATH
make -C <kernel-src>/kernel-common \
     O=~/aic8800-work/kout M=~/aic8800-work/aic8800-radxa \
     ARCH=arm64 LLVM=1 CONFIG_GKI=y \
     USER_EXTRA_CFLAGS="-DANDROID_PLATFORM -Wno-error=misleading-indentation -Wno-error=uninitialized" \
     modules
```
- `-DANDROID_PLATFORM`：走 6.x 回移的 `link_station_parameters` 分支（否则编译不过）。
- `CONFIG_GKI=y`：走 `rwnx_gki` shim，避免直接引用 `skb_append`。
- 两个 `-Wno-error=`: 源码有 `msgbuf 未初始化`、`misleading-indentation` 告警。

### 7.2 部署到设备
```sh
cd ~/aic-wifi-adb
./install.sh                       # 推 ax+脚本到 Termux, 装宿主 awifi
./install.sh --modules <模块目录>   # 推送 aic_load_fw_stub.ko / aic8800_fdrv_fixed.ko / fw/
```
`--modules` 目录需含 `aic_load_fw_stub.ko`、`aic8800_fdrv_fixed.ko`、`fw/`。

### 7.3 使用（设备 Termux）
```sh
aicw up
aicw scan
aicw connect "#1" <密码>
aicw ip
aicw info        # 看到 "当前走: AIC (aic0)"
```

---

## 8. 验证记录（实测数据，2026-09-28）

| 项目 | 结果 |
|---|---|
| `aicw up`（bootrom 8d80） | 固件下载 → 重枚举 8d81 → `aic0` 出现 |
| `aicw scan` | 列 8+ 个 AP（MyHotspot -43dBm / HomeWiFi -50 / …） |
| `aicw connect "MyHotspot" <密码>` | `wpa_state=COMPLETED`，WPA2-PSK CCMP，Wi-Fi 6 |
| `iw dev aic0 link` | rx 143.3 Mbit/s HE-MCS 11，signal -45 dBm |
| `aicw ip` | DHCP `192.168.x.x/24`，gw/DNS `192.168.x.x` |
| `ip route get 8.8.8.8` | `via 192.168.x.x dev aic0` |
| `ping 8.8.8.8` | 0% loss（~100ms） |
| `curl https://www.baidu.com` | HTTP 200 |
| `aicw aic` / `aicw mtk` | 默认上行在 aic0 / wlan0 间切换正常 |
| `aicw restart` | 卸载重载后**自动重连**已保存网络 |
| `aicw off` | 断网但保留驱动（模块在、aic0 在、无 IP/无规则）；`reconnect && ip` 可恢复 |
| `aicw saved add/forget/autoconnect` | 正常 |

---

## 9. 已知限制与后续可做
- 固件在 `/data` 依赖 SELinux permissive → 建议搬到 `/vendor/firmware`（或合适标签目录）。
- DHCP 由自带的 Python 最小实现（`dhcp.py`）完成（系统内无 `dhcptool`/`udhcpc`）。
- `aic0` 在 Android 框架之外，App 不会自动用它（需路由/规则或按 uid 分流）。
- 平板存在与网卡无关的背景性 MMC/`blocktag` 硬复位，排查时先排除。
- 可选增强：`aicw on`（off 的反操作）、多 SSID 快捷别名、把初始接口注册进 Android 连接管理。

---

## 10. 关键事实速查
- 接口名：**`aic0`**（源码 `rwnx_main.c` 初始名 `aic%d`）。
- 模块顺序：先 `aic_load_fw_stub.ko`，后 `aic8800_fdrv_fixed.ko`。
- 固件目录：`/data/local/tmp/aic/fw`，并写 `firmware_class/parameters/path`。
- 上网：`aicw ip`（`onlink` + `ip rule priority 30000 lookup main`）。
- 切换：`aicw aic` / `aicw mtk`。
- 真因一句话：**cfg80211_ops 少 `CONFIG_NL80211_TESTMODE` 两字段（错位 0x10）+ 接口名不能叫 `wlan*`（MTK 抢认）**。
