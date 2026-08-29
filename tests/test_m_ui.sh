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
    *probe*)
        if [ -f "$MUI_TEST_HTTP_STATE" ] && [ "$(cat "$MUI_TEST_HTTP_STATE")" = "offline" ]; then
            exit 1
        fi
        printf 'open\n'
        ;;
    *screen-state*)
        [ ! -f "$MUI_TEST_ADB_ALWAYS_FAIL" ] || exit 1
        if [ -s "$MUI_TEST_ADB_SEQUENCE" ]; then
            scripted_state=$(sed -n '1p' "$MUI_TEST_ADB_SEQUENCE")
            sed -n '2,$p' "$MUI_TEST_ADB_SEQUENCE" > "$MUI_TEST_ADB_SEQUENCE.tmp"
            mv "$MUI_TEST_ADB_SEQUENCE.tmp" "$MUI_TEST_ADB_SEQUENCE"
            case "$scripted_state" in
                ON|OFF) printf '%s\n' "$scripted_state"; exit 0 ;;
                FAIL) exit 1 ;;
                *) exit 1 ;;
            esac
        fi
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
    *'request?action=isalive'*)
        printf '%s\n' '{"status":0,"msg":"alive"}'
        ;;
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
export MUI_TEST_ADB_ALWAYS_FAIL="$TEST_ROOT/adb-always-fail"
export MUI_TEST_ADB_SEQUENCE="$TEST_ROOT/adb-sequence"
export MUI_TEST_HTTP_STATE="$TEST_ROOT/http-state"
export MUI_ADB_CONNECT_TIMEOUT=1s
export MUI_HTTP_PROBE_TIMEOUT=1s
export MUI_ADB_RECOVERY_VERIFY_SECONDS=1
export MUI_ADB_RECOVERY_RETRY_DELAY=0
export MUI_ADB_RECOVERY_MAX_ATTEMPTS=3
export MUI_ADB_PAUSED_POLL_INTERVAL=1
export MUI_COLD_BOOT_STABLE_SECONDS=1

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

: > "$MUI_TEST_LAUNCHES"
: > "$MUI_LOG_FILE"
: > "$MUI_TEST_ADB_ALWAYS_FAIL"
printf 'online\n' > "$MUI_TEST_HTTP_STATE"

"$PROJECT_DIR/m-ui" daemon &
daemon_pid=$!
sleep 5

keeper_launch_count=$(grep -c 'io.github.ylsislove.mui.adbkeeper' "$MUI_TEST_LAUNCHES" || true)
[ "$keeper_launch_count" -eq 3 ] || {
    printf '断言失败：连续失败时 ADB Keeper 启动了 %s 次，预期限制为 3 次。\n' "$keeper_launch_count" >&2
    exit 1
}

app_launch_count=$(grep -c 'com.xiaodianshi.tv.yst' "$MUI_TEST_LAUNCHES" || true)
[ "$app_launch_count" -eq 0 ] || {
    printf '断言失败：ADB 恢复失败时不应启动自启应用。\n' >&2
    exit 1
}
assert_contains "$(cat "$MUI_LOG_FILE")" 'ADB Keeper 连续恢复失败，已暂停本次电视在线会话'

printf 'offline\n' > "$MUI_TEST_HTTP_STATE"
sleep 2
printf 'online\n' > "$MUI_TEST_HTTP_STATE"
sleep 5
kill "$daemon_pid" 2>/dev/null || true
wait "$daemon_pid" 2>/dev/null || true

keeper_launch_count=$(grep -c 'io.github.ylsislove.mui.adbkeeper' "$MUI_TEST_LAUNCHES" || true)
[ "$keeper_launch_count" -eq 6 ] || {
    printf '断言失败：电视重新上线后 ADB Keeper 累计启动了 %s 次，预期 6 次。\n' "$keeper_launch_count" >&2
    exit 1
}

pause_count=$(grep -c 'ADB Keeper 连续恢复失败，已暂停本次电视在线会话' "$MUI_LOG_FILE" || true)
[ "$pause_count" -eq 2 ] || {
    printf '断言失败：预期两次独立在线会话各暂停一次，实际为 %s 次。\n' "$pause_count" >&2
    exit 1
}
assert_contains "$(cat "$MUI_LOG_FILE")" '电视 6095 接口已离线，ADB 自恢复会话已重置'

rm -f "$MUI_TEST_ADB_ALWAYS_FAIL"
: > "$MUI_TEST_LAUNCHES"
: > "$MUI_LOG_FILE"
printf 'online\n' > "$MUI_TEST_HTTP_STATE"
printf 'ON\nFAIL\nON\nON\n' > "$MUI_TEST_ADB_SEQUENCE"

"$PROJECT_DIR/m-ui" daemon &
daemon_pid=$!
sleep 4
kill "$daemon_pid" 2>/dev/null || true
wait "$daemon_pid" 2>/dev/null || true

keeper_launch_count=$(grep -c 'io.github.ylsislove.mui.adbkeeper' "$MUI_TEST_LAUNCHES" || true)
[ "$keeper_launch_count" -eq 1 ] || {
    printf '断言失败：普通 ADB 抖动时 Keeper 应启动 1 次，实际为 %s 次。\n' "$keeper_launch_count" >&2
    exit 1
}
app_launch_count=$(grep -c 'com.xiaodianshi.tv.yst' "$MUI_TEST_LAUNCHES" || true)
[ "$app_launch_count" -eq 0 ] || {
    printf '断言失败：普通 ADB 抖动不应重复启动自启应用。\n' >&2
    exit 1
}

: > "$MUI_TEST_LAUNCHES"
: > "$MUI_LOG_FILE"
printf 'offline\n' > "$MUI_TEST_HTTP_STATE"
printf 'FAIL\nON\nFAIL\nON\nON\n' > "$MUI_TEST_ADB_SEQUENCE"

"$PROJECT_DIR/m-ui" daemon &
daemon_pid=$!
sleep 1
printf 'online\n' > "$MUI_TEST_HTTP_STATE"
sleep 5
kill "$daemon_pid" 2>/dev/null || true
wait "$daemon_pid" 2>/dev/null || true

keeper_launch_count=$(grep -c 'io.github.ylsislove.mui.adbkeeper' "$MUI_TEST_LAUNCHES" || true)
[ "$keeper_launch_count" -eq 1 ] || {
    printf '断言失败：冷启动时 Keeper 应启动 1 次，实际为 %s 次。\n' "$keeper_launch_count" >&2
    exit 1
}
app_launch_count=$(grep -c 'com.xiaodianshi.tv.yst' "$MUI_TEST_LAUNCHES" || true)
[ "$app_launch_count" -eq 1 ] || {
    printf '断言失败：冷启动早期 ADB 短暂可用后，自启应用启动了 %s 次，预期 1 次。\n' "$app_launch_count" >&2
    exit 1
}
assert_contains "$(cat "$MUI_LOG_FILE")" '检测到冷启动会话中 ADB 已恢复且电视已亮屏'

: > "$MUI_TEST_LAUNCHES"
: > "$MUI_LOG_FILE"
printf 'offline\n' > "$MUI_TEST_HTTP_STATE"
printf 'FAIL\nON\nON\nON\n' > "$MUI_TEST_ADB_SEQUENCE"

"$PROJECT_DIR/m-ui" daemon &
daemon_pid=$!
sleep 1
printf 'online\n' > "$MUI_TEST_HTTP_STATE"
sleep 4
kill "$daemon_pid" 2>/dev/null || true
wait "$daemon_pid" 2>/dev/null || true

keeper_launch_count=$(grep -c 'io.github.ylsislove.mui.adbkeeper' "$MUI_TEST_LAUNCHES" || true)
[ "$keeper_launch_count" -eq 0 ] || {
    printf '断言失败：ADB 冷启动后持续稳定时不应唤起 Keeper。\n' >&2
    exit 1
}
app_launch_count=$(grep -c 'com.xiaodianshi.tv.yst' "$MUI_TEST_LAUNCHES" || true)
[ "$app_launch_count" -eq 1 ] || {
    printf '断言失败：ADB 冷启动后持续稳定时，自启应用启动了 %s 次，预期 1 次。\n' "$app_launch_count" >&2
    exit 1
}
assert_contains "$(cat "$MUI_LOG_FILE")" '检测到电视冷启动后已稳定亮屏'

printf 'm-ui 本机模拟测试全部通过。\n'
