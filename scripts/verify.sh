#!/system/bin/sh
# 一键体检，只读，不改任何东西
# 用法：adb push verify.sh /data/local/tmp/ && adb shell sh /data/local/tmp/verify.sh
#      root 下执行信息更全（模块列表、susfs 状态需要 root）

echo "===== 身份 ====="
id

echo
echo "===== 内核版本串 ====="
uname -a
echo "--- /proc/version ---"
cat /proc/version

echo
echo "===== cmdline（解锁状态） ====="
tr ' ' '\n' < /proc/cmdline | grep -E 'verifiedboot|buildvariant|flash.locked' || echo "(无匹配)"

echo
echo "===== 编译配置是否泄漏 ====="
if [ -e /proc/config.gz ]; then
    echo "存在 /proc/config.gz —— 未关闭 IKCONFIG"
else
    echo "不存在 /proc/config.gz —— 正常"
fi

echo
echo "===== 调试开关（系统侧真实值） ====="
settings get global adb_enabled

echo
echo "===== root 方案 ====="
if [ -x /data/adb/ksu/bin/ksud ]; then
    /data/adb/ksu/bin/ksud -V 2>&1
else
    echo "未找到 ksud（可能无 root 或路径不同）"
fi

echo
echo "===== SUSFS ====="
if [ -x /data/adb/ksu/bin/ksu_susfs ]; then
    /data/adb/ksu/bin/ksu_susfs show version 2>&1
else
    echo "未找到 ksu_susfs"
fi

echo
echo "===== 模块 ====="
ls -1 /data/adb/modules 2>/dev/null || echo "(需要 root)"

echo
echo "===== Zygisk 进程 ====="
ps -A 2>/dev/null | grep -iE 'zn-daemon|zn-zygisk|lspd' | head -6 || echo "(无)"

echo
echo "===== 结束 ====="
