#!/bin/bash
# 编译 ADBHide 模块，产出 out/adbhide.apk
#
# 依赖（可用环境变量覆盖）：
#   ANDROID_HOME    Android SDK 根目录，脚本会自己找最新的 build-tools 与 platform
#   ANDROID_JAR     直接指定 android.jar
#   BUILD_TOOLS     直接指定 build-tools 目录
#   API_JAR         Xposed API jar，默认 ./api-82.jar
#
# 首次使用前，把 Xposed API 的 api-82.jar 放到本目录（见 README.md）。

set -e
cd "$(dirname "$0")"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
BT="${BUILD_TOOLS:-$(ls -d "$SDK"/build-tools/* 2>/dev/null | sort -V | tail -1)}"
AJ="${ANDROID_JAR:-$(ls -d "$SDK"/platforms/android-*/android.jar 2>/dev/null | sort -V | tail -1)}"
API="${API_JAR:-$(pwd)/api-82.jar}"

if [ -z "$BT" ] || [ -z "$AJ" ]; then
    echo "找不到 build-tools 或 android.jar，请设置 ANDROID_HOME"
    exit 1
fi

if [ ! -f "$API" ]; then
    echo "缺少 Xposed API：$API"
    echo "见本目录 README.md 的「准备 API jar」一节"
    exit 1
fi

D8="$BT/lib/d8.jar"
AAPT2="$BT/aapt2"
[ -x "$AAPT2" ] || AAPT2="$BT/aapt2.exe"
ZIPALIGN="$BT/zipalign"
[ -x "$ZIPALIGN" ] || ZIPALIGN="$BT/zipalign.exe"
APKSIGNER="$BT/lib/apksigner.jar"

echo "=== 环境 ==="
echo "build-tools : $BT"
echo "android.jar : $AJ"
echo "api jar     : $API"

rm -rf classes dexout out
mkdir -p classes dexout out

echo "=== 1) 编译 ==="
javac -source 8 -target 8 -nowarn -encoding UTF-8 \
    -bootclasspath "$AJ" -cp "$API" \
    -d classes $(find src -name '*.java')

echo "=== 2) dex ==="
java -cp "$D8" com.android.tools.r8.D8 --lib "$AJ" --min-api 29 \
    --output dexout $(find classes -name '*.class')

echo "=== 3) 资源 ==="
"$AAPT2" link -o out/base.apk -I "$AJ" --manifest AndroidManifest.xml -A assets

echo "=== 4) 合并 dex ==="
python3 - <<'PY'
import os, zipfile
with zipfile.ZipFile('out/base.apk') as zin, zipfile.ZipFile('out/unsigned.apk', 'w', zipfile.ZIP_DEFLATED) as zout:
    for it in zin.infolist():
        zout.writestr(it, zin.read(it.filename))
    zout.write('dexout/classes.dex', 'classes.dex')
print('merged:', os.path.getsize('out/unsigned.apk'), 'bytes')
PY

echo "=== 5) 对齐 ==="
"$ZIPALIGN" -f -p 4 out/unsigned.apk out/aligned.apk

echo "=== 6) 签名 ==="
if [ ! -f ks.jks ]; then
    keytool -genkeypair -keystore ks.jks -alias a -keyalg RSA -keysize 2048 \
        -validity 10000 -storepass android -keypass android \
        -dname "CN=local" >/dev/null 2>&1
    echo "已生成测试用 keystore（ks.jks）"
fi
java -jar "$APKSIGNER" sign --ks ks.jks --ks-pass pass:android --key-pass pass:android \
    --out out/adbhide.apk out/aligned.apk

echo
ls -lh out/adbhide.apk
echo "=== 完成 ==="
