# 04 · 反检测分层，与调试模式的一次取舍

这篇记录两件事：**反检测应该按层思考**，以及**「伪装调试模式」为什么最后被放弃，改用按需开关的做法**。后者比前者更有价值——它划出了一条容易被忽略的边界。

---

## 一、检测发生在哪一层

| 层 | 检测器会查什么 | 你该在哪动手 |
|---|---|---|
| 内核层 | `/proc/mounts`、`kallsyms`、`uname`、模块目录 | SUSFS 编进内核 |
| 系统服务层 | 设置项、属性、包列表、进程列表 | 在系统服务里改返回值 |
| 进程层 | 自己的 maps、类结构、线程名、调试器状态 | 只能注入，**必然留痕** |
| 应用层 | 签名、完整性、业务逻辑 | 静态改包或不碰 |

本身没有错。**错的是第二层的适用范围。**

---

## 二、尝试：在 system_server 里伪造 adb_enabled

### 动机

检测器报「已开启调试模式」，读的通常是 `Settings.Global.getInt("adb_enabled")`。查一下这个数据在哪：

```bash
adb shell dumpsys activity providers | grep -A2 settings
```

```
* ContentProviderRecord{... com.android.providers.settings/.SettingsProvider}
  package=com.android.providers.settings process=system
```

`process=system` —— `SettingsProvider` 跑在 `system_server` 里。于是想法很自然：只注入系统框架，在数据出口处按调用者身份分流，检测器拿到 0，系统拿到真值。

### 第一次：直接注入检测器

最直觉的做法——写个 Xposed 模块 hook `Settings.Global.getInt`，作用域勾到 Momo 上。

结果：调试模式没藏住，反而多出三条。

```
环境异常
  找到 Zygisk
  发现代码注入
  Zygote 被注入
```

日志里还有一行关键信息：

```
I LSPosed : skip injecting into io.github.vvb2060.mahoshojo:...MahoService2 because it's isolated
```

Momo 的检测逻辑跑在**隔离进程**里，而 LSPosed 按设计不注入隔离进程。也就是说 hook 根本没落在关键位置，反而把自己的痕迹留在了能被扫描的进程里。

**教训一：注入即暴露。往检测器进程里塞代码，是必输的局。**

### 第二、三次：改成按 uid / pid 分流

改为注入 `system_server`，拦截 `SettingsProvider.query()` 和 `call("GET_global", ...)`：

```java
if (uid == 1000 || uid == 0 || uid == 2000) return;   // 系统、root、shell 放行
// 其他返回 0
```

装好、启用、重启，然后——

**手机能正常开机，但 adb 彻底失联。**

Windows 里只剩：

```
WPD   MI 8   USB\VID_2717&PID_FF40\FD365EA1
```

`FF40` 是纯 MTP。USB 调试正常工作时应该是 `FF48`（MTP + ADB）。设备侧看：

```bash
getprop sys.usb.config     # mtp        ← 没有 adb
getprop init.svc.adbd      # stopped
```

### 为什么

`UsbDeviceManager` 判断「要不要启动 adbd」，读的是**同一个** `adb_enabled`。它属于 `system_server` 自身逻辑，理论上会走「系统 uid 放行」那条路。但 `Binder.getCallingUid()` 在非跨进程调用时并不可靠——它返回的是当前线程上一次 binder 事务残留的值。`system_server` 的线程刚处理完某个应用的请求，接着自己读设置，就会读到那个应用的 uid，被误判成「普通应用」，拿到 0。

第二版加了 `pid != myPid` 判断，仍不够：残留的 pid 可能是一个**真实存在的应用进程**，校验照样通过。

第三版改成读 `/proc/<pid>/cmdline` 比对进程名，逻辑上已经不可能误伤 `system_server`（它自己的 cmdline 就是 `system_server`）——但启用后 adbd 依然不启动。

**教训二：当「系统自己也依赖这个值」时，伪造它就是和系统对赌。判据写得再小心，只要有一次误判，代价就是失去 adb 控制通道。**

于是这一项不再硬做，改成按需开关：平时关调试，Momo 全绿；要用 adb 时再开。代价为零，也不碰系统状态。

---

## 三、怎么判断一个值能不能这样伪造

动手之前问三个问题：

1. **这个值是谁写的？谁在读？** 用 `dumpsys` 把读写方都找出来，别只看检测器那一侧。
2. **系统内部有没有依赖它做决策？** `adb_enabled` 决定 adbd 是否启动；`ro.boot.verifiedbootstate` 决定系统是否信任当前启动链。这类值不能碰。
3. **伪造失败的代价是什么？** 如果失败会让你失去设备控制权（adb 断、无法解锁、无法回滚），就不值得做。

按这个标准筛一遍：

| 目标 | 系统是否自用 | 能不能伪造 |
|---|---|---|
| 模块目录、`uname`、`cmdline` | 否 | 可以（SUSFS 就是在做这个） |
| 包列表、应用枚举 | 部分 | 可以，注意别影响系统服务 |
| `adb_enabled` | **是**（adbd 启停） | 不要 |

---

## 四、日常怎么办

按代价从低到高：

1. **按需开关（本项目采用）。** 平时把 USB 调试关掉，Momo 全绿；需要用 adb 时打开，用完关掉。adb 本来就是临时工具，没人会一直挂着调试模式用手机。这一条的成本是零。
2. **静态改包。** 反编译目标，改掉判断逻辑再重签。不注入、不留运行时痕迹，但要过签名校验和加固。
3. **内核层。** 用 SUSFS 的 `SUS_MAP` 之类隐藏痕迹，或者更彻底地在 syscall 层做文章。工作量大，且需要重编内核。

之所以把「按需开关」排在第一，是因为它不改变系统状态，也就没有把设备控制权搭进去的风险。**能不改的就不改，这是最省事也最安全的方案。**

---

## 五、方法论

- **先问「这个值谁产生、谁消费」**，再决定在哪一层动手。`dumpsys` 比盲猜快得多。
- **尽量不动目标进程。** 只有在值是目标自己算出来的时候（签名校验、本地加密），才值得注入，并且要接受「会被发现」。
- **验证要看两侧**：系统侧看真实值，应用侧看伪造值。
- **改数据源之前，先确认系统不靠它活着。**

这次失败的真正价值，是让第二条边界变得具体：数据源不是随便挑的，**挑错了会把设备控制权一起搭进去**。
