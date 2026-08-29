#!/bin/sh

set -eu

SOURCE_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
DEFAULT_TV_IP="192.168.1.100"
CONFIG_TV_IP="${TV_IP:-$DEFAULT_TV_IP}"
ADB_BINARY="$SOURCE_DIR/dist/m-adb-linux-armv7"

if [ "$(id -u)" != "0" ]; then
    printf '请使用 root 用户运行安装脚本。\n' >&2
    exit 1
fi

for command_name in wget jsonfilter; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf '缺少必要命令：%s\n' "$command_name" >&2
        exit 1
    fi
done

for source_file in "$SOURCE_DIR/m-ui" "$SOURCE_DIR/m-ui.init" "$ADB_BINARY"; do
    if [ ! -f "$source_file" ]; then
        printf '缺少安装文件：%s\n' "$source_file" >&2
        exit 1
    fi
done

case "$(uname -m 2>/dev/null)" in
    armv7*|armhf) ;;
    *)
        printf '当前安装包仅包含 ARMv7 版 m-adb；检测到架构：%s\n' "$(uname -m 2>/dev/null || printf '未知')" >&2
        printf '请先为本机架构编译 m-adb，再替换 dist/m-adb-linux-armv7。\n' >&2
        exit 1
        ;;
esac

case "$CONFIG_TV_IP" in
    ''|*[!0-9.]*)
        printf '电视 IP 格式无效：%s\n' "$CONFIG_TV_IP" >&2
        exit 1
        ;;
esac

was_running=0
if [ -x /etc/init.d/m-ui ] && /etc/init.d/m-ui running >/dev/null 2>&1; then
    was_running=1
    /etc/init.d/m-ui stop || true
fi

mkdir -p /etc/m-ui
mkdir -p /usr/lib/m-ui
cp "$SOURCE_DIR/m-ui" /usr/bin/m-ui
cp "$SOURCE_DIR/m-ui.init" /etc/init.d/m-ui
cp "$ADB_BINARY" /usr/lib/m-ui/m-adb
chmod 0755 /usr/bin/m-ui /etc/init.d/m-ui /usr/lib/m-ui/m-adb

if [ ! -f /etc/m-ui/config ]; then
    {
        printf 'TV_IP=%s\n' "$CONFIG_TV_IP"
        printf 'TV_ADB_PORT=5555\n'
        printf 'AUTOSTART_PACKAGE=\n'
        printf 'AUTOSTART_APP_NAME=\n'
        printf 'POLL_INTERVAL=2\n'
        printf 'LAUNCH_DELAY=8\n'
    } > /etc/m-ui/config
    chmod 600 /etc/m-ui/config
fi

if [ "$was_running" -eq 1 ]; then
    /etc/init.d/m-ui start
fi

printf 'm-ui 安装完成，配置文件：/etc/m-ui/config\n'
printf '运行 m-ui 打开管理菜单。首次连接 ADB 时，请在电视上允许 m-ui@router 调试。\n'
