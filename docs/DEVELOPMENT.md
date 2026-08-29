# 开发说明

## 目录结构

```text
m-ui                       交互菜单与后台监控逻辑（POSIX shell）
m-ui.init                  OpenWrt procd 服务定义
install-router.sh          安装/升级脚本
uninstall-router.sh        卸载脚本
cmd/m-adb/                 最小化 ADB-over-TCP 客户端（Go）
dist/m-adb-linux-armv7     供 ARMv7 路由器直接使用的静态程序
tests/test_m_ui.sh         使用模拟命令验证完整状态转换
server.py + index.html     可选的本机 Web 遥控器
```

## 设计边界

- m-ui 不修改电视系统，也不在电视上安装组件。
- ADB 只用于读取系统屏幕状态；应用列表和启动动作使用电视的 HTTP 局域网接口。
- 配置文件由 `awk` 按键读取，不作为 shell 脚本加载，避免把电视返回的应用名称当作命令执行。
- 守护进程只维护一个 PID 文件，并交给 OpenWrt `procd` 管理和按策略拉起。
- 连续连接失败只记录一次，恢复连接时再记录一次，避免电视离线时刷日志。

## 本地测试

需要 Go 1.22 或更新版本。Shell 测试会创建独立的临时目录并模拟 ADB、HTTP 接口、`jsonfilter` 和 init 服务，不会连接真实电视或修改系统目录。

```sh
go test ./...
sh tests/test_m_ui.sh
```

还可以执行语法检查：

```sh
sh -n m-ui m-ui.init install-router.sh uninstall-router.sh build-m-adb.sh tests/test_m_ui.sh
```

## 构建 ARMv7 客户端

```sh
sh build-m-adb.sh
```

该脚本使用以下目标：

```text
CGO_ENABLED=0
GOOS=linux
GOARCH=arm
GOARM=7
```

输出为 `dist/m-adb-linux-armv7`。提交新版本前，应在实际 ARMv7 路由器上完成 ADB 授权、状态读取和断线重连测试。

## 发布检查

1. 更新 `m-ui` 中的版本号和 `CHANGELOG.md`。
2. 运行全部测试与 ARMv7 构建。
3. 确认仓库不存在私钥、家庭 IP、MAC、密码或路由器配置备份。
4. 在实际路由器执行覆盖安装，确认配置与 ADB 密钥得到保留。
5. 验证 `OFF → ON` 只触发一次应用启动。
