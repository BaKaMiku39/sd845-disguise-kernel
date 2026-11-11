# sd845-disguise-kernel

> 给骁龙 845（小米 8 / dipper）用的「伪装内核 + 反检测」组合：内核版本串、bootloader 状态、root 痕迹全部在内核层处理，**不在检测器自己的进程里注入任何代码**。

[![Device](https://img.shields.io/badge/device-dipper%20%2F%20MI%208-555)](#适用范围)
[![Android](https://img.shields.io/badge/android-10-3ddc84)](#适用范围)
[![Kernel](https://img.shields.io/badge/kernel-4.9.186--perf-blue)](#适用范围)
[![License](https://img.shields.io/badge/license-GPL--2.0-red)](LICENSE)

---

## 实测结果

**日常状态下（USB 调试关闭），Momo 4.4.1 全项通过**：无 root 痕迹、无 Magisk 模块痕迹、无 Zygisk 注入痕迹、bootloader 状态正常、无可疑痕迹。

需要 adb 时把 USB 调试打开，会多出「已开启调试模式」一条。这是**已知取舍**，不是没做完——想同时满足「adb 可用」和「这一项也干净」，试过三版方案，代价都是失去 adb 本身，详见 [docs/04-antidetect.md](docs/04-antidetect.md)。

一句话：**开调试是为了让电脑能连手机，而这件事本来就该是临时的。**

---

## 适用范围

| 项目 | 值 |
|---|---|
| 机型 | 小米 8（dipper），骁龙 845 |
| 系统 | MIUI 12.5 / Android 10 |
| 内核 | 4.9.186-perf-g3f9c1a7 |
| Root | BakaSU（原 ReSukiSU）v4.2.0-rc3，内核内嵌 |
| 隐藏 | SUSFS v2.3.0（Non-GKI 回移） |

其他 845 机型（mix2s、poco f1 等）可参考思路，但 defconfig 与内核树需自行适配。

---

## 三层模型

反检测的胜负不在「谁的 hook 更隐蔽」，而在**你把伪造点放在哪一层**。

| 层 | 做什么 | 能骗过 | 代价 |
|---|---|---|---|
| 内核层 | SUSFS 隐藏模块目录、伪造 uname / cmdline、隐藏映射 | 查 root、查模块、查内核串 | 需要重编内核 |
| 框架层 | Zygisk Next + LSPosed 提供注入能力 | 需要改 App 行为的场景 | 注入痕迹可被目标进程读到 |
| 数据源层 | 在系统服务里伪造返回值 | 读设置的检测（**本项目未采用，见下**） | 可能与系统自身逻辑冲突 |

**关键结论一：进程内注入无法对目标隐身。** 检测代码和你的 hook 在同一个地址空间，谁先跑谁赢，而检测通常先跑。

**关键结论二：改数据源听起来很美，但要看这个数据源是不是「系统自己也在用」。** `adb_enabled` 就属于这种——检测器读它，`UsbDeviceManager` 也读它。你把它改成 0，检测器满意了，系统却以为调试关着，adbd 直接不启动。这个坑踩了三次，最终放弃。

---

## 仓库结构

```
.
├── .github/workflows/build-kernel.yml   内核构建流水线（补丁全部内联）
├── kernel/defconfig.susfs               SUSFS 相关 config 片段
├── scripts/                             设备侧脚本
├── docs/                                原理与流程文档
└── CREDITS.md                           致谢与依赖清单
```

---

## 快速开始

### 1. 前置

- Bootloader 已解锁，已刷入 TWRP
- 本文机型实测 **fastboot 无法枚举**（笔记本 USB 控制器兼容问题），全程走 TWRP `install` 刷 zip

### 2. 构建内核

Fork 本仓库 → Actions → `Build dipper kernel` → Run workflow → 下载 `sd845-kernel-<日期>.zip`。

流水线做的事：拉取小米开源内核树 → 集成 BakaSU v4.2.0-rc3 → 剥离树里遗留的旧 KSU 钩子 → 打 SUSFS 4.9 补丁 → 伪造版本串 → 编译 → 打包 AnyKernel3。

### 3. 刷入

```bash
adb reboot recovery          # 或音量上 + 电源
# TWRP → Install → 选择 sd845-kernel-*.zip → 滑动刷入 → 重启
```

### 4. 装框架

按顺序安装，每步重启验证：

1. BakaSU 管理器 APK（内核已内嵌，管理器只做授权）
2. Zygisk Next（Zygisk 实现）
3. LSPosed 1.9.2（zygisk 版）
4. Hide My Applist（隐藏应用列表）

### 5. 验证

```bash
adb shell settings get global adb_enabled     # 1
adb shell uname -a                            # 伪装后的版本串
```

打开 Momo，应当只剩「已开启调试模式」一条，其余全部干净。

---

## 关于「已开启调试模式」这一条

这是本项目花时间最多的一段，值得完整记下来。

先说结论：**这一项做不到「adb 可用」和「检测不到」同时成立。** 尝试过三版实现，全部以 adb 失联告终，所以仓库里不提供相关代码。日常场景下把 USB 调试关掉即可，Momo 是全绿的。

思路本身不算错：检测器读 `adb_enabled`，最终落到 `SettingsProvider`，而这台机器上它跑在 `system_server` 里（`process=system`），理论上可以只注入系统框架，按调用者身份决定返回真值还是 0。

问题在于**这个数据源系统自己也在用**。`UsbDeviceManager` 判断「要不要启动 adbd」读的就是同一个值。调用者判据稍有偏差，系统自己就拿到 0，adbd 永远不启动——表现是 USB 调试开关明明开着，Windows 里却只有 `VID_2717&PID_FF40`（纯 MTP），adb 彻底失联。

三版判据依次试过：uid 白名单 → 加 pid 判断 → 读 `/proc/<pid>/cmdline` 比对进程名。全部失败。逐步推理见 [docs/04-antidetect.md](docs/04-antidetect.md)。

**实用建议**：把 USB 调试当成一次性开关——需要 adb 时打开，用完关掉。这样 Momo 在绝大多数时间里是全绿的。

---

## 已知限制

- **开启 USB 调试后，Momo 会报「已开启调试模式」**，无法与 adb 可用并存。日常关掉即可，见上一节。
- **重启后 MIUI 会关闭 USB 调试**，需要手动在开发者选项里重开。这是系统行为，与本方案无关。
- 内核补丁针对 4.9.186 这棵树调过，换机型或换内核版本需要重新对 fuzz。
- 只能用于**你自己持有**的设备。

---

## 致谢

完整依赖、版本与许可证见 [CREDITS.md](CREDITS.md)。核心项目：

- [KernelSU](https://github.com/tiann/KernelSU) — 内核级 root 的起点
- [BakaSU](https://github.com/Baka-SU/BakaSU)（原 ReSukiSU）— 本项目使用的分支
- [SUSFS](https://gitlab.com/simonpunk/susfs4ksu) — 内核侧隐藏补丁
- [Zygisk Next](https://github.com/Dr-TSNG/ZygiskNext) / [LSPosed](https://github.com/LSPosed/LSPosed) / [Hide My Applist](https://github.com/Dr-TSNG/Hide-My-Applist)
- [Momo](https://github.com/vvb2060/Mahoshojo) — 作为检测基准，非本项目组件

---

## 免责声明

本项目仅供**个人设备的安全研究与学习**使用。请勿用于规避他人设备的安全策略、绕过商业软件的风控或任何未经授权的场景。

因使用本仓库内容导致的设备损坏、数据丢失、保修失效或法律风险，由使用者自行承担。

---

## English summary

A kernel-level disguise kit for Snapdragon 845 devices (Xiaomi Mi 8 / dipper, MIUI 12.5, Android 10, kernel 4.9.186).

It combines two layers: SUSFS for kernel-side hiding (module paths, `uname`, cmdline, memory maps), and Zygisk Next + LSPosed for framework-level hooking when an app needs behavioural changes.

With USB debugging off — the normal state for daily use — Momo 4.4.1 reports **everything clean**. Turn debugging on and it adds one item, "debugging mode enabled". That trade-off is documented instead of hacked around, and the repo deliberately ships no code for it.

The attempt is worth reading anyway. The idea was to fake `adb_enabled` at its source: `SettingsProvider` runs inside `system_server` on this ROM, so injecting the system framework and returning `0` only to detector processes should have left the detector's own memory completely clean.

It failed three times, for the same reason: `UsbDeviceManager` reads the same value to decide whether to start `adbd`. Any imprecision in identifying the caller makes the system itself read `0`, `adbd` never starts, and the device silently loses adb — visible on Windows only as `VID_2717&PID_FF40`, MTP without ADB. Caller checks based on uid, then pid, then `/proc/<pid>/cmdline` all failed.

The lesson: faking a data source only works when the system does not depend on that value itself.

Builds are reproducible via GitHub Actions; flashable zips are published under Releases. Licensed GPL-2.0 because the kernel patches are derivative works of Linux.
