# 02 · SUSFS 配置

SUSFS 是内核侧的隐藏补丁集，做的是**让某些东西在系统调用层面就不存在**。它不是模块，是编进内核的代码，所以没有任何用户态痕迹。

本项目使用 **v2.3.0 Non-GKI 回移版**（4.9 专用）。

---

## 一、开了哪些开关

```c
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
```

| 开关 | 作用 | 为什么需要 |
|---|---|---|
| `SUS_PATH` | 让指定路径对非 root 进程「不存在」 | 藏 `/data/adb/modules` 等 |
| `SUS_MOUNT` | 隐藏模块挂载痕迹 | 防 `/proc/mounts` 比对 |
| `SUS_KSTAT` | 伪造 inode/大小/时间 | 防 stat 对比发现文件被替换 |
| `SPOOF_UNAME` | 伪造 `uname` 的版本串 | 与内核版本伪装呼应 |
| `SPOOF_CMDLINE` | 伪造 `/proc/cmdline` | 防看到 `androidboot.verifiedbootstate=orange` |
| `HIDE_KSU_SUSFS_SYMBOLS` | 隐藏内核符号 | 防扫 `/proc/kallsyms` |
| `OPEN_REDIRECT` | 打开文件时重定向 | 替换文件内容而不改原文件 |
| `SUS_MAP` | **按路径隐藏内存映射** | 藏注入的 so，`/proc/self/maps` 里直接消失 |

`SUS_MAP` 是这套里最有价值的一个：**它是「注入了但目标看不见」的唯一可行路径**。Java 层 hook 藏不住，因为类和方法结构会露；但把 so 的映射从 maps 里抹掉，目标读到的就是干净的地址空间。

---

## 二、开机自动应用

SUSFS 的配置不持久化，重启就没了。用 KernelSU 模块的 `service.sh` 在开机时重新下发。

```bash
#!/system/bin/sh
# /data/adb/modules/<模块名>/service.sh
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 3; done

S=/data/adb/ksu/bin/ksu_susfs

# 隐藏模块目录
$S add_sus_path /data/adb/modules
$S add_sus_path /data/adb/ksu

# 伪造内核版本串
$S set_uname "4.9.186-perf-g3f9c1a7" "#1 SMP PREEMPT Fri Jul 9 22:14:31 CST 2021"

# 伪造 cmdline
$S set_cmdline "androidboot.verifiedbootstate=green androidboot.flash.locked=1"

# 隐藏自身符号
$S hide_sus_mnts_for_non_su_procs 1
```

> 具体参数名以 `ksu_susfs help` 的输出为准，不同版本有差异。**先跑一遍 help 再写脚本**，别照抄。

---

## 三、属性和 bootloader 状态

SUSFS 管不到 `ro.boot.*` 这类属性，需要另外用 `resetprop` 在开机时覆盖：

```bash
R=/data/adb/ksu/bin/resetprop
$R ro.boot.verifiedbootstate green
$R ro.boot.flash.locked 1
$R ro.secureboot.lockstate locked
$R ro.oem_unlock_supported 0
```

脚本见 [`scripts/propspoof.sh`](../scripts/propspoof.sh)。

**注意**：`resetprop` 要在 `service.sh` 阶段跑，太早属性服务还没起来，太晚已经被读过一轮。

---

## 四、版本匹配（血泪教训）

刷完内核后如果出现「模块列表全空、Zygisk 不启动」，几乎一定是 **UAPI 版本不匹配**：

```
kernel UAPI = 6    vs    ksud UAPI = 4
```

内核里的 KernelSU 代码和用户态 `ksud` 必须来自同一个版本。表现是模块明明在 `/data/adb/modules` 里，管理器却一个都不显示。

**解法：内核和管理器 APK 用同一个 release。** 本项目两边都是 `v4.2.0-rc3`。

---

## 五、验证

```bash
# 以 root 执行
ksu_susfs show sus_path
ksu_susfs show uname
```

以及从**非 root 进程**的角度验证（这点很关键，root 进程看到的永远是真实值）：

```bash
adb shell ls /data/adb/modules     # 应当 Permission denied
adb shell uname -a                 # 应当是伪装后的串
```
