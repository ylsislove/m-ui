#!/bin/sh

set -eu

PROJECT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
if [ -z "${JAVA_HOME:-}" ] && [ -x "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/javac" ]; then
    JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi
if [ -n "${JAVA_HOME:-}" ]; then
    PATH="$JAVA_HOME/bin:$PATH"
    export JAVA_HOME PATH
fi
BUILD_TOOLS_VERSION="${BUILD_TOOLS_VERSION:-36.1.0}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-36}"
BUILD_TOOLS="$ANDROID_SDK_ROOT/build-tools/$BUILD_TOOLS_VERSION"
ANDROID_JAR="$ANDROID_SDK_ROOT/platforms/$ANDROID_PLATFORM/android.jar"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
RELEASE_DIST_DIR="$PROJECT_DIR/../../dist"
KEYSTORE_DIR="$PROJECT_DIR/.keystore"
KEYSTORE="$KEYSTORE_DIR/adb-keeper.jks"
KEYSTORE_PASSWORD_FILE="$KEYSTORE_DIR/password"
KEYSTORE_PASSWORD="${ADB_KEEPER_KEYSTORE_PASSWORD:-}"

for required_file in \
    "$ANDROID_JAR" \
    "$BUILD_TOOLS/aapt2" \
    "$BUILD_TOOLS/d8" \
    "$BUILD_TOOLS/zipalign" \
    "$BUILD_TOOLS/apksigner"; do
    if [ ! -x "$required_file" ] && [ ! -f "$required_file" ]; then
        printf '缺少 Android 构建文件：%s\n' "$required_file" >&2
        exit 1
    fi
done

for required_command in javac jar zip keytool; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        printf '缺少构建命令：%s\n' "$required_command" >&2
        exit 1
    fi
done

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/classes" "$BUILD_DIR/dex" "$DIST_DIR" "$RELEASE_DIST_DIR" "$KEYSTORE_DIR"

if [ -z "$KEYSTORE_PASSWORD" ] && [ -f "$KEYSTORE_PASSWORD_FILE" ]; then
    KEYSTORE_PASSWORD=$(cat "$KEYSTORE_PASSWORD_FILE")
fi

if [ ! -f "$KEYSTORE" ] && [ -z "$KEYSTORE_PASSWORD" ]; then
    KEYSTORE_PASSWORD=$(hexdump -n 24 -e '24/1 "%02x"' /dev/urandom)
    printf '%s\n' "$KEYSTORE_PASSWORD" > "$KEYSTORE_PASSWORD_FILE"
    chmod 600 "$KEYSTORE_PASSWORD_FILE"
fi

if [ -z "$KEYSTORE_PASSWORD" ]; then
    printf '已存在签名密钥，但缺少密码。请设置 ADB_KEEPER_KEYSTORE_PASSWORD 或恢复 %s。\n' "$KEYSTORE_PASSWORD_FILE" >&2
    exit 1
fi

find "$PROJECT_DIR/src" -name '*.java' -type f | sort > "$BUILD_DIR/sources.txt"
javac \
    -encoding UTF-8 \
    -source 8 \
    -target 8 \
    -bootclasspath "$ANDROID_JAR" \
    -d "$BUILD_DIR/classes" \
    @"$BUILD_DIR/sources.txt"

jar cf "$BUILD_DIR/classes.jar" -C "$BUILD_DIR/classes" .
"$BUILD_TOOLS/d8" \
    --release \
    --min-api 24 \
    --lib "$ANDROID_JAR" \
    --output "$BUILD_DIR/dex" \
    "$BUILD_DIR/classes.jar"

"$BUILD_TOOLS/aapt2" link \
    -o "$BUILD_DIR/unsigned.apk" \
    -I "$ANDROID_JAR" \
    --manifest "$PROJECT_DIR/AndroidManifest.xml" \
    --min-sdk-version 24 \
    --target-sdk-version 28 \
    --version-code 3 \
    --version-name 1.2.0

zip -q -j "$BUILD_DIR/unsigned.apk" "$BUILD_DIR/dex/classes.dex"
"$BUILD_TOOLS/zipalign" -f 4 "$BUILD_DIR/unsigned.apk" "$BUILD_DIR/aligned.apk"

if [ ! -f "$KEYSTORE" ]; then
    keytool -genkeypair \
        -keystore "$KEYSTORE" \
        -storepass "$KEYSTORE_PASSWORD" \
        -keypass "$KEYSTORE_PASSWORD" \
        -alias adb-keeper \
        -dname "CN=m-ui ADB Keeper,O=ylsislove" \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 \
        >/dev/null 2>&1
    chmod 600 "$KEYSTORE"
fi

"$BUILD_TOOLS/apksigner" sign \
    --ks "$KEYSTORE" \
    --ks-key-alias adb-keeper \
    --ks-pass "pass:$KEYSTORE_PASSWORD" \
    --key-pass "pass:$KEYSTORE_PASSWORD" \
    --out "$DIST_DIR/m-ui-adb-keeper.apk" \
    "$BUILD_DIR/aligned.apk"

"$BUILD_TOOLS/apksigner" verify --verbose --print-certs "$DIST_DIR/m-ui-adb-keeper.apk"
cp "$DIST_DIR/m-ui-adb-keeper.apk" "$RELEASE_DIST_DIR/m-ui-adb-keeper.apk"
printf '已生成 %s\n' "$DIST_DIR/m-ui-adb-keeper.apk"
