# sd845-disguise-kernel

> 给骁龙 845（小米 8 / dipper）用的「伪装内核 + 反检测」组合：内核版本串、bootloader 状态、root 痕迹、调试开关，全部在内核层与系统服务层处理，**不在检测器自己的进程里注入任何代码**。

[![Device](https://img.shields.io/badge/device-dipper%20%2F%20MI%208-555)](#适用范围)
[![Android](https://img.shields.io/badge/android-10-3ddc84)](#适用范围)
[![Kernel](https://img.shields.io/badge/kernel-4.9.186--perf-blue)](#适用范围)
[![License](https://img.shields.io/badge/license-GPL--2.0-red)](LICENSE)

---

## 实测结果

Momo 4.4.1 全项通过，无「环境异常」、无「可疑痕迹」。

![Momo 全项通过](assets/img/momo-clean.png)

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
| 数据源层 | 在 `system_server` 里伪造返回值 | 读设置、读属性的检测 | 无注入痕迹 |

**关键结论：进程内注入无法对目标隐身。** 检测代码和你的 hook 在同一个地址空间，谁先跑谁赢，而检测通常先跑。所以能改数据源就不要进进程——这也是本仓库 `ADBHide` 的设计前提。

---

## 仓库结构

```
.
├── .github/workflows/build-kernel.yml   内核构建流水线（补丁全部内联）
├── kernel/defconfig.susfs               SUSFS 相关 config 片段
├── module/adbhide/                      ADBHide 模块源码与构建脚本
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

### 5. 装 ADBHide

从 Releases 取 `ADBHide-*.apk`，或自行编译（见 [`module/adbhide/`](module/adbhide/)）：

```bash
adb install -r ADBHide-v1.1.apk
```

然后打开 LSPosed 管理器 → 模块 → ADBHide → **作用域只勾「系统框架」**，重启。

### 6. 验证

```bash
adb shell settings get global adb_enabled     # 1，系统内部看到真实值
```

打开 Momo，应当没有任何条目。**Momo 读到的是 0，而 adbd 照常工作**——这就是数据源层伪造的意义。

---

## 关键设计：为什么钩 system_server

检测器读调试开关，最终都会落到 `SettingsProvider`。而在这台机器上：

```
package=com.android.providers.settings  process=system
```

它跑在 `system_server` 里，不在独立进程。于是可以只注入系统框架，拦截 `query()` 和 `call()`：

- 调用者 uid 是 system / root / shell → 返回真实值，adbd、开发者选项不受影响
- 其他任何 uid → 返回 `0`

好处是检测器自己的进程**一行我们的代码都没有**，`/proc/self/maps` 干净，`XposedBridge` 类不存在，线程名也没有异常。它读到的世界就是「调试已关闭」。

对比一下失败过的做法：把 ADBHide 作用域勾到 Momo 上。结果是调试模式确实被 hook 了，但 Momo 立刻多报三条——「找到 Zygisk」「发现代码注入」「Zygote 被注入」。**注入即暴露**，这是硬约束。

---

## 已知限制

- **重启后 MIUI 会关闭 USB 调试**，需要手动在开发者选项里重开。这是系统行为，与本方案无关。
- 伪造点只覆盖 `Settings.Global` 读取路径。若检测器改读 `/proc`、`sysfs` 或直接扫内核内存，需要另做处理（可配合 SUSFS 的 `SUS_MAP`）。
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

It combines three layers: SUSFS for kernel-side hiding (module paths, `uname`, cmdline, memory maps), Zygisk Next + LSPosed for framework-level hooking, and a data-source-level fake for the USB debugging flag.

The last part is the point. Instead of injecting into the detector, `ADBHide` hooks `SettingsProvider` **inside `system_server`** and returns `0` for `adb_enabled` to every caller except system/root/shell. Detectors read "debugging off" while `adbd` keeps working — and their own process stays completely clean, with no injected library, no `XposedBridge` class, no suspicious thread names.

Injecting into the detector itself was tried first and failed predictably: the debugging flag was hidden, but Momo immediately reported three injection traces. In-process hooking cannot be hidden from the process being hooked.

Builds are reproducible via GitHub Actions; flashable zips are published under Releases. Licensed GPL-2.0 because the kernel patches are derivative works of Linux.
