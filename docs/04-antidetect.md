# 04 · 反检测：把伪造点找对

这篇是整个项目的核心。方法只有一句：**先搞清楚这个值是谁产生的，再决定在哪一层动手。**

---

## 一、检测发生在哪一层

| 层 | 检测器会查什么 | 你该在哪动手 |
|---|---|---|
| 内核层 | `/proc/mounts`、`kallsyms`、`uname`、模块目录 | SUSFS 编进内核 |
| 系统服务层 | 设置项、属性、包列表、进程列表 | 在系统服务里改返回值 |
| 进程层 | 自己的 maps、类结构、线程名、调试器状态 | 只能注入，**必然留痕** |
| 应用层 | 签名、完整性、业务逻辑 | 静态改包或不碰 |

前三层是「设备看起来怎样」，最后一层是「这个 App 自己算得对不对」。

---

## 二、失败案例：把模块勾到检测器上

最初的做法很直觉：写个 Xposed 模块，hook `Settings.Global.getInt("adb_enabled")` 返回 0，然后**把作用域勾到 Momo 上**。

结果：

```
环境异常
  找到 Zygisk
  发现代码注入
  Zygote 被注入
可疑痕迹
  已开启调试模式
```

调试模式那条没消失，反而多出三条。日志说明了原因：

```
I LSPosed: Loading xposed for io.github.vvb2060.mahoshojo
I LSPosed-Bridge: Loading legacy module com.local.adbhide
I LSPosed: skip injecting into ...MahoService2 because it's isolated
```

两个关键信息：

1. 模块确实加载了，但 Momo 的检测逻辑跑在**隔离进程**里（`isolated`），LSPosed 按设计不注入隔离进程——hook 根本没生效在关键位置。
2. 一旦 LSPosed 注入 Momo，`/proc/self/maps` 里就有了我们的映射，`XposedBridge` 类也进了它的地址空间。检测器扫自己进程，一抓一个准。

**结论：往检测器进程里塞代码，是必输的局。** 它能读内核、能扫自己的内存，你藏不住。

---

## 三、正确做法：改数据源

### 找到真正的数据源

Momo 读调试开关，不管走哪条 API，最终都会落到 `SettingsProvider`。查一下它跑在哪：

```bash
adb shell dumpsys activity providers | grep -A2 settings
```

```
* ContentProviderRecord{... com.android.providers.settings/.SettingsProvider}
  package=com.android.providers.settings process=system
```

`process=system` —— 它不在独立进程，**就在 `system_server` 里**。

于是可以只注入系统框架（`android`），在数据出口处拦截：

```java
// 只勾「系统框架」作用域
if ("android".equals(lp.processName) || "system".equals(lp.processName)) {
    hookProvider(lp);
}
```

### 拦截点有两个

Android 的 `Settings.Global.getInt()` 走的是 `ContentProvider.call("GET_global", name, args)`，不是 `query()`。两个都要拦：

```java
XposedBridge.hookAllMethods(sp, "query", hook);   // 直接查 URI 的路径
XposedBridge.hookAllMethods(sp, "call",  hook);   // Settings.Global.getXxx 的路径
```

URI 形态：`content://settings/global/adb_enabled`，判断 `getPathSegments()` 是否为 `[global, adb_enabled]`。

### 关键：按调用者 uid 分流

不能无差别返回 0，否则 `adbd` 自己读到「调试已关闭」就会停掉，你就断了控制通道。

```java
private static boolean keepReal(int uid) {
    return uid == 1000      // system，adbd 与开发者选项在这
        || uid == 0         // root
        || uid == 2000;     // shell，adb shell
}

if (keepReal(Binder.getCallingUid())) return;   // 放行，读真实值

MatrixCursor c = new MatrixCursor(new String[]{"value"});
c.addRow(new Object[]{"0"});                    // 其他所有调用者读到 0
param.setResult(c);
```

`call()` 分支则返回：

```java
Bundle b = new Bundle();
b.putString("value", "0");
param.setResult(b);
```

### 结果

| 谁在读 | 读到 | 为什么 |
|---|---|---|
| system_server 内部（adbd、开发者选项） | `1` | uid 1000，放行 |
| `adb shell settings get` | `1` | uid 2000，放行 |
| Momo / 其他 App | `0` | 被伪造 |

而且 **Momo 的进程里一行我们的代码都没有**：`maps` 干净、没有 `XposedBridge`、没有异常线程名。它读到的世界就是「调试没开」。

---

## 四、验证方法

```bash
# 系统侧：真实值
adb shell settings get global adb_enabled          # → 1

# 应用侧：伪造值
adb shell am force-stop io.github.vvb2060.mahoshojo
adb shell am start -n io.github.vvb2060.mahoshojo/.home.HomeActivity
# Momo 界面应当无条目
```

对比实验很有价值：把作用域勾回 Momo，你会立刻看到那三条注入痕迹回来。这能证明「伪造点位置」比「hook 写得多巧」重要得多。

---

## 五、局限

- 只覆盖 `Settings.Global` 的读取路径。若检测器改读 `/proc`、`sysfs`，需要 SUSFS 的 `SUS_MAP` 或内核态拦截。
- 按 uid 白名单放行是权宜之计。如果检测器以 system uid 运行（极少数情况），会被放行。
- 修改系统框架意味着**每次改配置都要重启**，`system_server` 不会热加载模块。

---

## 六、方法论：换个检测项怎么办

1. **先问「这个值谁产生」**——内核？系统服务？App 自己？
2. **能用 `dumpsys` 定位就定位**。`dumpsys activity providers`、`dumpsys package`、`dumpsys mount` 比盲猜快得多。
3. **尽量不动目标进程**。只有在值是目标自己算出来的时候（签名校验、本地加密），才考虑注入，并且要接受「会被发现」这个前提。
4. **验证要看两侧**：系统侧看真实值，应用侧看伪造值。只看一侧会误判。

一句话总结这个项目：**不要和检测器比谁藏得好，去改它看到的世界。**
