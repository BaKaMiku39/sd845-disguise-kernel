#!/system/bin/sh
# 在设备上以 root 执行：sh propspoof.sh
# 作用：生成一个 KernelSU 模块，开机时用 resetprop 覆盖 bootloader 相关属性
# 说明：属性必须在 post-fs-data 阶段覆盖，太早属性服务没起，太晚已被读过

set -u

MOD=/data/adb/modules/propspoof
RP=/data/adb/ksu/bin/resetprop

if [ "$(id -u)" != "0" ]; then
    echo "需要 root，请先 su"
    exit 1
fi

if [ ! -x "$RP" ]; then
    echo "找不到 $RP，请确认 root 方案与路径"
    exit 1
fi

mkdir -p "$MOD"

cat > "$MOD/module.prop" <<'EOF'
id=propspoof
name=Bootloader Props Spoof
version=v1.0
versionCode=1
author=sd845-disguise-kernel
description=开机覆盖 ro.boot.* 属性，隐藏解锁状态
EOF

cat > "$MOD/post-fs-data.sh" <<'EOF'
#!/system/bin/sh
MODDIR=${0%/*}
RP=/data/adb/ksu/bin/resetprop
[ -x "$RP" ] || exit 0

# 属性名 目标值
SETS="
ro.boot.verifiedbootstate green
ro.boot.flash.locked 1
ro.secureboot.lockstate locked
ro.oem_unlock_supported 0
"

echo "$SETS" | while read -r k v; do
    [ -n "$k" ] || continue
    i=0
    while [ $i -lt 20 ]; do
        "$RP" "$k" "$v" 2>/dev/null
        [ "$(getprop "$k")" = "$v" ] && break
        i=$((i+1))
        sleep 1
    done
done
EOF

chmod 755 "$MOD/post-fs-data.sh"

echo "=== 模块已生成 ==="
ls -l "$MOD"
echo
echo "=== 立即试跑一次 ==="
sh "$MOD/post-fs-data.sh"
for k in ro.boot.verifiedbootstate ro.boot.flash.locked ro.secureboot.lockstate ro.oem_unlock_supported; do
    echo "$k = $(getprop "$k")"
done
echo
echo "重启后会自动应用。"
