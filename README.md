# AIC8800D80 USB 网卡 —— 使用手册（联想 TB335FC / Termux 为主）

外接 AIC8800D80 USB WiFi 网卡在联想 TB335FC 平板(Android 15 / KernelSU root)上的驱动与工具。
已实现：加载驱动 → 扫描 → 连接 → DHCP 拿 IP → **通过它上网** → 与内置 WiFi 切换上行。
命令是一个完整的 WiFi 管理器：`aicw`（设备 Termux）/ `awifi`（宿主 PC，经 adb）。

---

## 一、东西都在哪里

### 设备端 · Termux（日常操作处）
| 路径 | 说明 |
|---|---|
| **`aicw`**（`$PREFIX/bin/aicw`） | **主命令入口**，任意目录直接敲 `aicw ...` |
| `~/aic-wifi/` | 脚本目录：`env.sh`、`wifi-*.sh`、`dhcp.py`、`aicw`、`README.md` |
| `/data/local/tmp/aic/` | 内核模块 + 固件（DE 存储，锁屏/重启也在） |
| `/data/local/tmp/aic/aic_load_fw_stub.ko` | 固件下载器（先加载；也是 fdrv 的符号提供者） |
| `/data/local/tmp/aic/aic8800_fdrv_fixed.ko` | 网卡驱动（已修复版） |
| `/data/local/tmp/aic/fw/` | 18 个固件文件 |
| `/data/local/tmp/aic/{wpa_ctrl,wpa.conf,scan_list,lease,resolv.conf}` | 运行时文件（脚本内部用） |

### 宿主端（PC，可选）
`~/.../aic-wifi-adb/`（源码，`install.sh` 负责部署）；宿主命令 **`awifi`**（装在 PATH，如 `/usr/bin/awifi`）。

> 接口名固定 **`aic0`**（不是 wlan0/wlan1），原因见文末排错。

---

## 二、依赖
```sh
pkg install iw wpa_supplicant python      # Termux 里
```
脚本需要 root：命令会自动用 `su` 提权（首次 KernelSU 弹窗，允许即可）。

---

## 三、命令大全

### `aicw`（Termux 内）
| 命令 | 作用 |
|---|---|
| `aicw up` | 加载驱动 + 起 `aic0` + 起 wpa_supplicant |
| `aicw off` | **断网但保留驱动**（撤 IP/路由/规则） |
| `aicw down` | 停 supplicant + 撤路由 + 卸载驱动 |
| `aicw restart` | 重载（已保存网络会自动重连） |
| `aicw scan` | 扫描并列网（按信号排序，带序号/加密方式） |
| `aicw list` | 看上次扫描结果（不重扫） |
| `aicw connect <SSID\|#序号> [密码] [--hidden]` | 连接（无密码=开放；`--hidden`=隐藏SSID） |
| `aicw disconnect` | 断开（保留已保存网络） |
| `aicw reconnect` | 重连 |
| `aicw status` | 关联状态 / 链路速率 / 地址 |
| `aicw signal` | 信号 / 速率 |
| `aicw info` | 地址 / 网关 / DNS / 当前默认上行 |
| `aicw saved` | 列出已保存网络 |
| `aicw saved add <SSID> [密码] [--hidden]` | 保存网络（不立即连） |
| `aicw forget <SSID\|id>` | 删除保存的网络 |
| `aicw autoconnect <SSID\|id> on\|off` | 开关该网络自动连接 |
| `aicw ip` | DHCP 取 IP + 配默认路由（→ 能上网） |
| `aicw aic` | 默认上行切到 AIC 网卡 |
| `aicw mtk` | 默认上行切回内置 WiFi/移动数据 |
| `aicw sh` | 交互 shell |
| `aicw help` | 帮助 |

### `awifi`（宿主 PC，经 adb 控制设备；子命令与 `aicw` 一一对应）
```sh
awifi up | off | down | restart
awifi scan | list
awifi connect "<SSID|#序号>" [密码] [--hidden] | disconnect | reconnect
awifi status | signal | info
awifi saved [add|forget|autoconnect]
awifi ip | aic | mtk
awifi sh                 # 进入设备端归一化 Termux
# 多设备: ANDROID_SERIAL=xxx awifi ...
```

---

## 四、典型用法（Termux 内）
```sh
# 首次 / 每次重启后
aicw up
aicw scan
aicw connect "#1" <密码>            # 用扫描序号，或直接写 SSID
aicw ip                           # 拿 IP + 配路由 → 能上网
aicw info                         # 确认 "当前走: AIC (aic0)"

# 以后只要
aicw up                           # 已保存网络会自动连上
aicw ip

# 切换上网出口
aicw aic                          # 走 AIC
aicw mtk                          # 走内置 WiFi/移动数据

# 管理
aicw saved                        # 看都存了哪些
aicw autoconnect "MyHotspot" off
aicw forget "MyHotspot"
```

验证上网：
```sh
ip route get 8.8.8.8        # -> via <网关> dev aic0
ping -c3 8.8.8.8
curl -sS -o /dev/null -w '%{http_code}\n' https://www.baidu.com
```

---

## 五、上网与"双 WiFi"说明
- 本机有两个**独立网卡**：内置 MTK(`wlan0`) 和 AIC USB(`aic0`)，可**同时各连一个 AP**。
- 安卓 WiFi 框架**只管 `wlan0`**；`aic0` 在框架外，由 `wpa_supplicant`+`ip` 手动管，安卓 App 默认走 `wlan0`。
- `aicw aic`：给 `aic0` 配 IP（无则先 DHCP）→ `default via <gw> dev aic0 onlink`
  → `ip rule priority 30000 lookup main`，让**无标记流量**（root/Termux 等）走 AIC；
  Android 带 fwmark 的 App 流量不受影响。`aicw mtk` 撤销。
- 只让某 uid 走 AIC（进阶）：
  ```sh
  su -c 'ip rule add priority 30000 uidrange <uid>-<uid> lookup main'
  su -c 'ip rule del priority 30000 uidrange <uid>-<uid>'
  ```

---

## 六、重装 / 恢复
- Termux 数据被清或脚本丢了：宿主上重新 `./install.sh`。
- 模块被硬复位损坏（`insmod: Exec format error`）：
  `./install.sh --modules <含 aic_load_fw_stub.ko / aic8800_fdrv_fixed.ko / fw 的目录>`。
  脚本对 `aic8800_fdrv_fixed.ko` 有 md5 校验，不一致会警告。

---

## 七、排错
- **`insmod: No such file or directory` 但文件在**：多半是 `Unknown symbol`；
  确认 `aic_load_fw` 已加载（fdrv 的符号来源），`aicw up` 会自动先加载。
- **`Exec format error`**：模块被硬复位损坏，重推（见六）。
- **`aic0` 不存在**：USB probe 异步，等 1~2s；`aicw up` 已内置等待。
- **DHCP 拿不到**：先确认 `aicw status` 里 `wpa_state=COMPLETED`。
- **能连不能上网**：`aicw ip`，再 `aicw info` 看是否走 `aic0`。
- **为什么叫 `aic0`**：MTK 自带 wlan 驱动的 inetaddr notifier 用
  `strncmp(dev->name,"wlan",4)`/`"p2p"` 认自己的网卡；我们的接口若叫 `wlan1` 就会被它
  当成 MTK 结构体，一配 IP 就 NULL 崩。改名 `aic*` 即绕开（已固化进驱动）。
- **背景性硬复位**：本机有与网卡无关的 MMC/`blocktag` 崩溃
  (`getprop ro.boot.bootreason` 为 `kernel_panic`)，莫名重启先怀疑它。

---

## 八、驱动修复要点（备查）
1. 设备端 MTK `cfg80211.ko` 开了 `CONFIG_NL80211_TESTMODE=y`，其 `struct cfg80211_ops`
   比我们多 `testmode_cmd/testmode_dump` 两指针；模块不带此宏 → 回调表错位 0x10 → 注册即 panic。
   修复：`aic8800_fdrv/Makefile` 加 `EXTRA_CFLAGS += -DCONFIG_NL80211_TESTMODE`。
2. 初始接口名 `"wlan%d"` 改 `"aic%d"`（规避 MTK notifier）。
构建：
```sh
export PATH=/usr/lib/llvm-19/bin:$PATH
make -C <kernel-src> O=<kout> M=<aic8800-radxa> ARCH=arm64 LLVM=1 CONFIG_GKI=y \
     USER_EXTRA_CFLAGS="-DANDROID_PLATFORM -Wno-error=misleading-indentation -Wno-error=uninitialized" modules
```
