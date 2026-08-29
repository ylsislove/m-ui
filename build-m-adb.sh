#!/bin/sh

set -eu

PROJECT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
mkdir -p "$PROJECT_DIR/dist"

env CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 \
    go build -trimpath -ldflags '-s -w -buildid=' \
    -o "$PROJECT_DIR/dist/m-adb-linux-armv7" "$PROJECT_DIR/cmd/m-adb"

printf '已生成 dist/m-adb-linux-armv7\n'
