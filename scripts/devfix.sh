#!/system/bin/sh
# 在设备上以 root 执行：sh devfix.sh
# 作用：修复「设置里点开发者选项没反应 / 闪退」
# 原理：com.android.settings 的 DevelopmentSettingsDashboardActivity 被组件状态禁用，
#       而 MIUI 的入口判断读的就是这个状态。settings put 改不动它，只能改 XML。

set -u

XML=/data/system/users/0/package-restrictions.xml
BAK=/data/local/tmp/package-restrictions.xml.bak

if [ "$(id -u)" != "0" ]; then
    echo "需要 root，请先 su"
    exit 1
fi

if [ ! -f "$XML" ]; then
    echo "找不到 $XML"
    exit 1
fi

echo "=== 处理前 ==="
grep -c 'DevelopmentSettingsDashboardActivity' "$XML" || true

cp -f "$XML" "$BAK" || { echo "备份失败"; exit 1; }
echo "已备份到 $BAK"

# 直接删掉这条 disabled-component 记录，比改 enabled 属性更彻底
sed '/Settings\$DevelopmentSettingsDashboardActivity/d' "$XML" > /data/local/tmp/pr.new
if [ ! -s /data/local/tmp/pr.new ]; then
    echo "生成的新文件为空，已中止"
    exit 1
fi

cat /data/local/tmp/pr.new > "$XML"
rm -f /data/local/tmp/pr.new

echo "=== 处理后 ==="
grep -c 'DevelopmentSettingsDashboardActivity' "$XML" || true
echo
echo "已修改，必须重启才生效：reboot"
echo "如果重启后异常，可用 TWRP 把 $BAK 拷回原位置"
