#!/bin/sh

set -eu

if [ "$(id -u)" != "0" ]; then
    printf '请使用 root 用户运行卸载脚本。\n' >&2
    exit 1
fi

purge=0
case "${1:-}" in
    '') ;;
    --purge) purge=1 ;;
    *)
        printf '用法：sh uninstall-router.sh [--purge]\n' >&2
        exit 1
        ;;
esac

if [ -x /etc/init.d/m-ui ]; then
    /etc/init.d/m-ui stop >/dev/null 2>&1 || true
    /etc/init.d/m-ui disable >/dev/null 2>&1 || true
fi

rm -f /usr/bin/m-ui /etc/init.d/m-ui /usr/lib/m-ui/m-adb /var/run/m-ui.pid /tmp/m-ui.log
rmdir /usr/lib/m-ui 2>/dev/null || true

if [ "$purge" -eq 1 ]; then
    rm -f /etc/m-ui/config /etc/m-ui/adbkey /etc/m-ui/adbkey.pub
    rmdir /etc/m-ui 2>/dev/null || true
    printf 'm-ui 已卸载，配置和 ADB 密钥已删除。\n'
else
    printf 'm-ui 已卸载；/etc/m-ui 中的配置和 ADB 密钥已保留。\n'
fi
