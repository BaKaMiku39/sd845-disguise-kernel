# ADBHide

让检测器读到 `adb_enabled = 0`，而系统里的 USB 调试保持开启。

**核心思路：不注入检测器。** 伪造点在 `system_server` 的 `SettingsProvider` 里，检测器自己的进程完全干净。原理见 [docs/04-antidetect.md](../../docs/04-antidetect.md)。

---

## 作用域

LSPosed 管理器里，本模块的作用域**只勾「系统框架」（android）**，其他一律不勾。

勾了具体 App 会怎样？会把这些 App 也纳入注入范围，白白增加暴露面，而且没必要——所有 App 读设置都会经过系统框架。

> 血泪教训：曾经把作用域勾到 Momo 上，结果调试模式没藏住，反而多出「找到 Zygisk」「发现代码注入」「Zygote 被注入」三条。**注入即暴露。**

---

## 行为

| 调用者 uid | 读到的 `adb_enabled` |
|---|---|
| 1000（system） | 真实值，`adbd` 与开发者选项不受影响 |
| 0（root） | 真实值 |
| 2000（shell） | 真实值 |
| 其他所有 App | `0` |

拦截两个入口，缺一不可：

- `SettingsProvider.query()` — 直接查 `content://settings/global/adb_enabled`
- `SettingsProvider.call("GET_global", ...)` — `Settings.Global.getInt/getString` 走的是这条

---

## 准备 API jar

编译需要 Xposed API 的 `api-82.jar`，本仓库不附带。任选一种：

1. 从 [XposedBridge](https://github.com/rovo89/XposedBridge) 的发布页取 `api-82.jar`
2. 从已安装的 LSPosed 模块开发模板里取
3. 用 Gradle 依赖导出：`de.robv.android.xposed:api:82`

放到本目录，文件名保持 `api-82.jar`（或用 `API_JAR` 环境变量指定路径）。

---

## 编译

```bash
export ANDROID_HOME=/path/to/android-sdk
./build.sh
```

产物：`out/adbhide.apk`。

需要 JDK 8+、Android SDK（build-tools 含 d8/aapt2/zipalign/apksigner）、python3。

---

## 安装与生效

```bash
adb install -r out/adbhide.apk
```

1. 打开 LSPosed 管理器 → 模块 → ADBHide → 启用
2. 作用域只勾「系统框架」
3. **重启**（`system_server` 不会热加载模块）

---

## 验证

```bash
# 系统侧：真实值
adb shell settings get global adb_enabled      # 1

# 应用侧：伪造值
adb shell am force-stop io.github.vvb2060.mahoshojo
adb shell am start -n io.github.vvb2060.mahoshojo/.home.HomeActivity
# Momo 里不应出现「已开启调试模式」
```

想看反例，把作用域勾到 Momo 上再试一次——三条注入痕迹会立刻回来。

---

## 局限

- 只覆盖 `Settings.Global`。如果检测器读 `/proc` 或 `sysfs`，需要内核侧配合（SUSFS `SUS_MAP`）。
- 若检测器以 system uid 运行，会被放行。
