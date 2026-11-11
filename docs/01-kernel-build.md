# 01 · 内核构建

目标不是「编出来能开机」，而是**编出来看不出被编过**。分两部分：先让它编译通过，再让版本串和元信息看起来像原厂。

---

## 一、为什么 4.9 这么难

小米 8 的内核是 4.9.186。KernelSU 主线早已不支持 4.9，直接集成会连环报错。逐条记录踩过的坑：

### 1. `syscall_fn_t` 未定义

主线 KernelSU 的钩子函数签名用了 `syscall_fn_t`，这是 4.17+ 才有的类型。4.9 上必须用旧版本。

**结论：钉住 `v0.9.5` 或 BakaSU `v4.2.0-rc3`，别用 main。**

### 2. 树里残留的旧 KSU 钩子会打架

小米这棵树里已经有人塞过 KernelSU 的钩子，签名是 `const char __user **`，而新版本要求 `struct filename **`。直接打补丁会出现同名函数重复定义。

**做法：打补丁前先把树里所有 `ksu_handle_*` 的 extern 声明和调用点删干净**，让内核回到上游 4.9 的形状，再让补丁自己插。

```python
decl = re.compile(r'(?m)^extern int ksu_handle_\w+\([^;]*\);\n')
call = re.compile(r'(?m)^[ \t]*ksu_handle_\w+\([^;\n]*\);[ \t]*\n')
```

### 3. `fs/notify/fdinfo.c` 补丁必然失败

SUSFS 的补丁在这里引用了 `inotify_mark_user_mask()`，4.19 才引入。4.9 上无解，**直接从补丁里剔除这个文件**。

### 4. `fs/proc/cmdline.c` 靠 fuzz 会插错位置

小米树里这个文件是精简版，补丁的上下文对不上，fuzz 之后插到错误函数里。**改为手工插入**：定位 `cmdline_proc_show` 函数体开头，把 spoof 分支塞进去。

### 5. 编译告警变错误

老代码大量 `declaration-after-statement`，clang 13 下会报错。加一个编译参数绕开：

```
KCFLAGS=-Wno-declaration-after-statement
```

---

## 二、版本串伪装

`uname -a` 和 `/proc/version` 是最容易被抓的两处。要伪装成什么样？看同机型原厂：

```
Linux version 4.9.186-perf-g3f9c1a7 (builder@xiaomi) ...
```

### 四件事一起做

| 项 | 做法 | 作用 |
|---|---|---|
| `CONFIG_LOCALVERSION` | 设为 `"-perf-g3f9c1a7"` | 版本串主体 |
| `CONFIG_LOCALVERSION_AUTO` | 关闭 | 否则会追加 git 描述 |
| `scripts/setlocalversion` | 把 `-dirty` 输出改成空 | 否则脏树会带 `-dirty` |
| `.git` 目录 | 编译前 `rm -rf .git` | 从根上断掉 git 版本信息 |
| `KBUILD_BUILD_USER/HOST` | `builder` / `xiaomi` | 盖掉 CI 的 `runner@runnervmxxx` |
| `CONFIG_IKCONFIG` | 关闭 | 否则 `/proc/config.gz` 会暴露真实编译配置 |

### 验证

```bash
adb shell uname -a
adb shell cat /proc/version
adb shell ls /proc/config.gz     # 应当不存在
```

---

## 三、流水线

完整步骤在 [`.github/workflows/build-kernel.yml`](../.github/workflows/build-kernel.yml)，所有补丁内联在 yml 里，仓库不存内核源码。

顺序：装依赖 → clone AnyKernel3 → clone 内核树 → clone 工具链 → 集成 BakaSU → 剥离旧钩子 → 取 SUSFS 4.9 文件 → 打补丁 → 手工插 cmdline → 改 defconfig → 编译 → 打 zip。

**注意**：`patch` 步骤故意用 `--fuzz=3`，因为不同内核树的上下文有偏移。但如果出现 `.rej`，说明偏移超限，必须人工看。

---

## 四、排错速查

| 现象 | 大概率原因 |
|---|---|
| `syscall_fn_t` 未定义 | 用了 KernelSU 主线 |
| `ksu_handle_*` 重复定义 | 没剥离树里旧钩子 |
| `inotify_mark_user_mask` 未定义 | fdinfo.c 没剔除 |
| 版本串带 `-dirty` 或 `+` | 没删 `.git` 或没改 setlocalversion |
| 开机后模块全空、Zygisk 不启动 | 内核 UAPI 与 ksud 版本不匹配 |
