# 03 · 刷入与回滚

---

## 一、先备份

刷内核前至少备份 `boot` 分区和 `modem`、`persist`。TWRP 里：

```
Backup → 勾选 Boot / Modem / EFS → 存到外部存储或 OTG
```

**不要存在 `/data` 里**——出问题时最可能出问题的就是 data。

---

## 二、为什么只能走 TWRP

本文机型在一台特定笔记本上 **`fastboot` 完全枚举不到设备**：

```
fastboot devices        # 空
```

`lsusb` 能看到设备，但 bootloader 的 USB 描述符不被该控制器接受。换线、换口、换 USB 2.0 hub 都无效。

所以全流程改走 TWRP：

```bash
adb reboot recovery
# 或关机后：音量上 + 电源
```

TWRP 里有 `install`，可以直接刷 AnyKernel3 的 zip，效果与 fastboot 刷 boot 一致。

> 如果你的机器 fastboot 正常，`fastboot flash boot boot.img` 更省事。本项目提供的 zip 同样可以用 AnyKernel3 支持的方式刷入。

---

## 三、刷入

```
TWRP → Install → 选择 sd845-kernel-<日期>.zip → 滑动确认
```

刷完**先别急着重启**，回 TWRP 主界面确认没有红色报错。

然后：

```
Reboot → System
```

首次开机会比平时慢（模块初始化），属正常。

---

## 四、刷后核验

```bash
adb shell uname -a                    # 版本串是否伪装成功
adb shell settings get global adb_enabled
adb shell ls /data/adb/modules        # 非 root 应被拒
```

管理器里确认：

1. 模块列表能看到 Zygisk Next / LSPosed
2. 超级用户里能看到已授权应用
3. 打开 Momo，应当无异常条目

---

## 五、回滚

出问题（不开机、卡 logo、模块全空且反复重启）时：

**方案 A：TWRP 恢复备份**

```
TWRP → Restore → 选备份 → 只勾 Boot → 滑动
```

**方案 B：刷回原厂 boot**

小米 8 的官方线刷包里有 `boot.img`，TWRP 里 `Install → Install Image → 选 boot.img → 勾 Boot`。

**方案 C：卡在开机动画但 adb 可用**

```bash
adb shell magisk --remove-modules     # 若装了 Magisk
# 或直接删模块目录（需要 root）
adb shell su -c 'rm -rf /data/adb/modules/zygisk_lsposed'
```

---

## 六、MIUI 的两个坑

### 1. 开发者选项进不去

表现：设置里点「开发者选项」闪退或无响应。

原因：`Settings$DevelopmentSettingsDashboardActivity` 被组件状态禁用。改法：

```bash
adb shell su -c "sed -i 's/name=\"com.android.settings.Settings\$DevelopmentSettingsDashboardActivity\" enabled=\"false\"/name=\"com.android.settings.Settings\$DevelopmentSettingsDashboardActivity\" enabled=\"true\"/' /data/system/users/0/package-restrictions.xml"
adb reboot
```

脚本见 [`scripts/devfix.sh`](../scripts/devfix.sh)。

> 直接改 XML 有风险，改前先 `cp` 一份备份。而且改完必须重启，system_server 只在开机时读这个文件。

### 2. 关掉 USB 调试会连带关掉 USB 共享

`settings put global adb_enabled 0` 之后，USB 网络共享也会被系统收回，adb 直接断开。

**这也是为什么不能用「临时关调试」的方式来骗过检测器**——你会同时失去对设备的控制通道。正确做法是保持 `adb_enabled=1`，在读取路径上做假，见 [04-antidetect.md](04-antidetect.md)。

### 3. 重启后 USB 调试自动关闭

MIUI 的安全策略：重启后 `adb_enabled` 归零，需要手动在开发者选项里重开。这是系统行为，任何模块都改不了（改了就等于系统层留痕）。

实操建议：**reboot 之前先把要做的 adb 操作做完**，重启后第一件事是手动开调试。
