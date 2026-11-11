# 致谢与依赖清单

本项目的每一层都建立在别人的工作上。以下按「在本项目里承担什么角色」分类，许可证一列以上游仓库为准。

---

## 一、内核层

| 项目 | 在本项目中的作用 | 许可证 | 地址 |
|---|---|---|---|
| KernelSU | 内核级 root 的原始实现，BakaSU 的上游 | GPL-2.0 | https://github.com/tiann/KernelSU |
| BakaSU（原 ReSukiSU） | 实际集成的 root 方案，本项目钉在 `v4.2.0-rc3` | kernel 目录 GPL-2.0-only，其余 GPL-3.0-or-later | https://github.com/Baka-SU/BakaSU |
| SUSFS（susfs4ksu） | 内核侧隐藏：`SUS_PATH` / `SUS_MOUNT` / `SUS_KSTAT` / `SPOOF_UNAME` / `SPOOF_CMDLINE` / `SUS_MAP` | 见上游 | https://gitlab.com/simonpunk/susfs4ksu |
| susfs4ksu 4.9 回移分支 | 本项目直接取用的 4.9 版补丁与 `susfs.c` | 见上游 | https://github.com/wxx9248/susfs4ksu （`kernel-4.9-v2` 分支） |
| 小米开源内核（dipper） | 内核源码基线 | GPL-2.0 | https://github.com/MiCode/Xiaomi_Kernel_OpenSource |
| 内核树构建分支 | 流水线实际 clone 的树（含 zstd 等改动） | GPL-2.0 | https://github.com/diyishengqing/Xiaomi_Kernel_OpenSource-sdm845 （`88-zstd` 分支） |
| 交叉编译工具链 | clang 13 + linaro gcc 4.9 打包 | 见上游 | https://github.com/diyishengqing/android-kernel-tools （`clang13` 分支） |
| AnyKernel3 | 把 `Image.gz-dtb` 打成可刷 zip | 见上游 | https://github.com/osm0sis/AnyKernel3 ；本项目使用 https://github.com/diyishengqing/AnyKernel3 |

---

## 二、框架层

| 项目 | 在本项目中的作用 | 许可证 | 地址 |
|---|---|---|---|
| Zygisk Next | Zygisk 实现，LSPosed 的运行基础 | 见上游 | https://github.com/Dr-TSNG/ZygiskNext |
| LSPosed | Xposed 框架，提供模块加载与作用域管理 | GPL-3.0 | https://github.com/LSPosed/LSPosed |
| XposedBridge API | `api-82.jar`，模块编译依赖 | 见上游 | https://github.com/rovo89/XposedBridge |
| Hide My Applist | 隐藏应用列表，配合对抗包名/应用枚举 | 见上游 | https://github.com/Dr-TSNG/Hide-My-Applist |
| Momo | **仅作为检测基准**，用于验证方案有效性，非本项目组件 | 见上游 | https://github.com/vvb2060/Mahoshojo |

---

## 三、工具链

| 项目 | 用途 | 许可证 | 地址 |
|---|---|---|---|
| jadx | 反编译 APK，分析检测逻辑 | Apache-2.0 | https://github.com/skylot/jadx |
| apktool | 拆包 / 重打包 / 资源修改 | Apache-2.0 | https://github.com/iBotPeaches/Apktool |
| frida | 动态插桩，运行时验证 | 见上游 | https://github.com/frida/frida |
| PCAPdroid | 设备侧抓包 | 见上游 | https://github.com/emanuele-f/PCAPdroid |
| Termux | 设备侧 shell 环境 | 见上游 | https://github.com/termux/termux-app |
| TWRP | 第三方 recovery，本机型的刷入通道 | 见上游 | https://github.com/TeamWin/android_bootable_recovery |
| Magisk | 早期用于 boot 镜像处理与 `magiskboot` | GPL-3.0 | https://github.com/topjohnwu/Magisk |

---

## 四、关于分发

- 本仓库**不包含**任何第三方二进制文件。所有 APK、内核 zip 均由使用者自行构建，或从 Releases 获取。
- Releases 中的内核 zip 由本仓库的 GitHub Actions 现场编译，源码来自上表所列仓库。
- Releases 中的 APK 若包含第三方应用，均保留原始签名与出处说明。

---

## 五、如果遗漏了你的项目

很可能是疏忽。请提 Issue 说明项目地址与所属模块，我会补进本文件。
