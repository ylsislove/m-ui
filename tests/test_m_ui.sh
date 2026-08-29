#!/bin/sh

set -eu

PROJECT_DIR=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d /tmp/m-ui-test.XXXXXX)

cleanup() {
    if [ -f "$TEST_ROOT/service.pid" ]; then
        service_pid=$(cat "$TEST_ROOT/service.pid" 2>/dev/null || true)
        case "$service_pid" in
            ''|*[!0-9]*) ;;
            *) kill "$service_pid" 2>/dev/null || true ;;
        esac
    fi
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT INT TERM

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/etc"

cat > "$TEST_ROOT/bin/adb" <<'EOF'
#!/bin/sh

case "$*" in
    *get-state*) printf 'device\n' ;;
    *connect*) printf 'connected\n' ;;
    *screen-state*)
        failures=0
        [ ! -f "$MUI_TEST_ADB_FAILURES" ] || failures=$(cat "$MUI_TEST_ADB_FAILURES")
        if [ "$failures" -gt 0 ]; then
            printf '%s\n' $((failures - 1)) > "$MUI_TEST_ADB_FAILURES"
            exit 1
        fi
        count=0
        [ ! -f "$MUI_TEST_STATE_COUNT" ] || count=$(cat "$MUI_TEST_STATE_COUNT")
        count=$((count + 1))
        printf '%s\n' "$count" > "$MUI_TEST_STATE_COUNT"
        if [ "$count" -eq 1 ]; then
            printf 'OFF\n'
        else
            printf 'ON\n'
        fi
        ;;
    *'shell dumpsys display'*)
        count=0
        [ ! -f "$MUI_TEST_STATE_COUNT" ] || count=$(cat "$MUI_TEST_STATE_COUNT")
        count=$((count + 1))
        printf '%s\n' "$count" > "$MUI_TEST_STATE_COUNT"
        if [ "$count" -eq 1 ]; then
            printf '  mScreenState=OFF\n'
        else
            printf '  mScreenState=ON\n'
        fi
        ;;
    *) exit 1 ;;
esac
EOF

cat > "$TEST_ROOT/bin/wget" <<'EOF'
#!/bin/sh

case "$*" in
    *getinstalledapp*)
        printf '%s\n' '{"status":0,"data":{"AppInfo":[{"AppName":"云视听小电视","PackageName":"com.xiaodianshi.tv.yst"},{"AppName":"桌面","PackageName":"com.mitv.tvhome"},{"AppName":"m-ui ADB Keeper","PackageName":"io.github.ylsislove.mui.adbkeeper"}]}}'
        ;;
    *startapp*)
        printf '%s\n' "$*" >> "$MUI_TEST_LAUNCHES"
        printf '%s\n' '{"status":0,"msg":"success"}'
        ;;
    *) exit 1 ;;
esac
EOF

cat > "$TEST_ROOT/bin/jsonfilter" <<'EOF'
#!/bin/sh

expression=""
while [ "$#" -gt 0 ]; do
    if [ "$1" = "-e" ]; then
        shift
        expression="$1"
        break
    fi
    shift
done

case "$expression" in
    '@.data.AppInfo[*].AppName') printf '云视听小电视\n桌面\nm-ui ADB Keeper\n' ;;
    '@.data.AppInfo[*].PackageName') printf 'com.xiaodianshi.tv.yst\ncom.mitv.tvhome\nio.github.ylsislove.mui.adbkeeper\n' ;;
    '@.status') printf '0\n' ;;
    *) exit 1 ;;
esac
EOF

cat > "$TEST_ROOT/etc/init" <<'EOF'
#!/bin/sh

case "$1" in
    start)
        sleep 30 &
        printf '%s\n' "$!" > "$MUI_PID_FILE"
        ;;
    stop)
        pid=$(cat "$MUI_PID_FILE" 2>/dev/null || true)
        [ -z "$pid" ] || kill "$pid" 2>/dev/null || true
        rm -f "$MUI_PID_FILE"
        ;;
    restart)
        "$0" stop
        "$0" start
        ;;
    enable) touch "$MUI_TEST_ENABLED" ;;
    disable) rm -f "$MUI_TEST_ENABLED" ;;
    enabled) [ -f "$MUI_TEST_ENABLED" ] ;;
    *) exit 1 ;;
esac
EOF

chmod +x "$TEST_ROOT/bin/adb" "$TEST_ROOT/bin/wget" "$TEST_ROOT/bin/jsonfilter" "$TEST_ROOT/etc/init"

export MUI_CONFIG_DIR="$TEST_ROOT/etc/m-ui"
export MUI_CONFIG_FILE="$MUI_CONFIG_DIR/config"
export MUI_PID_FILE="$TEST_ROOT/service.pid"
export MUI_LOG_FILE="$TEST_ROOT/m-ui.log"
export MUI_INIT_SCRIPT="$TEST_ROOT/etc/init"
export MUI_ADB_BIN="$TEST_ROOT/bin/adb"
export MUI_WGET_BIN="$TEST_ROOT/bin/wget"
export MUI_JSONFILTER_BIN="$TEST_ROOT/bin/jsonfilter"
export MUI_TEST_ENABLED="$TEST_ROOT/enabled"
export MUI_TEST_STATE_COUNT="$TEST_ROOT/state-count"
export MUI_TEST_LAUNCHES="$TEST_ROOT/launches"
export MUI_TEST_ADB_FAILURES="$TEST_ROOT/adb-failures"
export MUI_ADB_RECOVERY_DELAY=0
export MUI_ADB_RECOVERY_INTERVAL=1

assert_contains() {
    haystack="$1"
    needle="$2"
    printf '%s' "$haystack" | grep -F "$needle" >/dev/null || {
        printf '断言失败：未找到 %s\n' "$needle" >&2
        exit 1
    }
}

status_output=$("$PROJECT_DIR/m-ui" status)
assert_contains "$status_output" 'm-ui 状态：未运行'
assert_contains "$status_output" '是否开机自启：否'
assert_contains "$status_output" '电视 IP 地址：192.168.1.100'
assert_contains "$status_output" '电视自启动应用：未设置'
assert_contains "$status_output" '电视自启动应用延迟：8 秒'

invalid_ip_output=$("$PROJECT_DIR/m-ui" menu 2>&1 <<'EOF'
1
192.168.1.256

0
EOF
)
assert_contains "$invalid_ip_output" '输入无效，请输入正确的 IPv4 地址。'
assert_contains "$(cat "$MUI_CONFIG_FILE")" 'TV_IP=192.168.1.100'

"$PROJECT_DIR/m-ui" menu >/dev/null <<'EOF'
1
192.168.1.123

0
EOF
assert_contains "$(cat "$MUI_CONFIG_FILE")" 'TV_IP=192.168.1.123'
assert_contains "$("$PROJECT_DIR/m-ui" status)" '电视 IP 地址：192.168.1.123'

apps_output=$("$PROJECT_DIR/m-ui" menu <<'EOF'
2

0
EOF
)
assert_contains "$apps_output" '云视听小电视'
assert_contains "$apps_output" 'com.xiaodianshi.tv.yst'

"$PROJECT_DIR/m-ui" menu >/dev/null <<'EOF'
3
1

0
EOF

status_output=$("$PROJECT_DIR/m-ui" status)
assert_contains "$status_output" 'com.xiaodianshi.tv.yst'

"$PROJECT_DIR/m-ui" menu >/dev/null <<'EOF'
4
3

0
EOF
assert_contains "$(cat "$MUI_CONFIG_FILE")" 'LAUNCH_DELAY=3'

awk '
    /^POLL_INTERVAL=/ { print "POLL_INTERVAL=1"; next }
    /^LAUNCH_DELAY=/ { print "LAUNCH_DELAY=1"; next }
    { print }
' "$MUI_CONFIG_FILE" > "$MUI_CONFIG_FILE.tmp"
mv "$MUI_CONFIG_FILE.tmp" "$MUI_CONFIG_FILE"

"$PROJECT_DIR/m-ui" enable >/dev/null
status_output=$("$PROJECT_DIR/m-ui" status)
assert_contains "$status_output" '是否开机自启：是'
"$PROJECT_DIR/m-ui" disable >/dev/null

"$PROJECT_DIR/m-ui" start >/dev/null
status_output=$("$PROJECT_DIR/m-ui" status)
assert_contains "$status_output" 'm-ui 状态：已运行'
"$PROJECT_DIR/m-ui" stop >/dev/null

printf '1\n' > "$MUI_TEST_ADB_FAILURES"
"$PROJECT_DIR/m-ui" daemon &
daemon_pid=$!
sleep 4
awk '
    /^TV_IP=/ { print "TV_IP=192.168.1.124"; next }
    { print }
' "$MUI_CONFIG_FILE" > "$MUI_CONFIG_FILE.tmp"
mv "$MUI_CONFIG_FILE.tmp" "$MUI_CONFIG_FILE"
sleep 3
kill "$daemon_pid" 2>/dev/null || true
wait "$daemon_pid" 2>/dev/null || true

[ -f "$MUI_TEST_LAUNCHES" ] || {
    printf '断言失败：没有触发应用启动。\n' >&2
    exit 1
}

keeper_launch_count=$(grep -c 'io.github.ylsislove.mui.adbkeeper' "$MUI_TEST_LAUNCHES")
[ "$keeper_launch_count" -eq 1 ] || {
    printf '断言失败：ADB Keeper 启动了 %s 次，预期 1 次。\n' "$keeper_launch_count" >&2
    exit 1
}

app_launch_count=$(grep -c 'com.xiaodianshi.tv.yst' "$MUI_TEST_LAUNCHES")
[ "$app_launch_count" -eq 1 ] || {
    printf '断言失败：自启动应用启动了 %s 次，预期 1 次。\n' "$app_launch_count" >&2
    exit 1
}

assert_contains "$(cat "$MUI_LOG_FILE")" '检测到电视由息屏进入亮屏'
assert_contains "$(cat "$MUI_LOG_FILE")" '已启动电视应用'
assert_contains "$(cat "$MUI_LOG_FILE")" '已请求 ADB Keeper 自动恢复'
assert_contains "$(cat "$MUI_LOG_FILE")" 'ADB Keeper 已恢复电视 ADB'
assert_contains "$(cat "$MUI_LOG_FILE")" '电视 ADB 地址已更新：192.168.1.123:5555 -> 192.168.1.124:5555'

printf 'm-ui 本机模拟测试全部通过。\n'
