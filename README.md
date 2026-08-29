# m-ui

[![CI](https://github.com/ylsislove/m-ui/actions/workflows/ci.yml/badge.svg)](https://github.com/ylsislove/m-ui/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

部署在 OpenWrt/PandoraBox 路由器上的小米电视开机自动启动第三方 APP 工具。

m-ui 通过 ADB 读取电视的真实屏幕状态；当检测到屏幕由 `OFF` 变为 `ON` 时，等待设定时间，再通过电视局域网接口启动指定应用。可选的 ADB Keeper 还能在部分小米电视彻底断电后自动恢复 ADB。它适合“电视亮屏或通电启动后自动打开 B 站电视版”等场景。

> 项目已经在 PandoraBox 20.01、ARMv7 路由器与小米电视上实际验证。不同型号和系统版本可能关闭或修改相关局域网接口，请先阅读[兼容性说明](#兼容性与前提)。

## 功能

- 查看电视已安装应用，并直接选择自启动应用
- 使用真实屏幕状态识别息屏到亮屏，而不是仅判断电视是否联网
- 自定义亮屏后的启动延迟（0～300 秒）
- 启动、停止、重启和查看后台服务状态
- 设置或取消路由器开机自启
- ADB 断线后自动重试，不会持续刷相同错误日志
- 可选的无界面 ADB Keeper：冷启动后由路由器通过 `6095` 自动唤起，无需 Root 或刷机
- Keeper 恢复有明确上限：最多 3 次，连续失败后暂停本次在线会话，避免无限重试
- 日志写入内存并自动裁剪，避免不断占用闪存和存储空间
- 附带无外部依赖的 ARMv7 ADB 客户端，无需在老路由器软件源中安装 `adb`

## 工作原理

```text
每 2 秒读取一次 ADB 屏幕状态
        │                         │
        │ ADB 可用                │ ADB 不可用、6095 在线
        ▼                         ▼
 检测 OFF → ON          唤起已安装的 ADB Keeper
        │                         │
        │                  每秒验证 ADB，单次最多 10 秒
        └─────────────┬───────────┘
                      ▼
              等待用户设置的延迟
                      │
              再次确认屏幕仍为 ON
                      │
              通过 6095 启动指定应用
```

电视息屏后通常仍可联网，因此 `isalive`、`ping` 或端口连通性无法区分“亮屏”和“息屏”。m-ui 优先从 `dumpsys display` 读取 `mScreenState`，并在需要时使用 `dumpsys power` 的 `mWakefulness` 作为兼容性回退。

ADB 不可用但 `6095` 已上线时，m-ui 会立即唤起 Keeper，并在 10 秒内每秒检查 ADB。如果未恢复，等待 5 秒后重试，最多 3 次（总计约 40 秒）。三次都失败后，本次电视在线会话不再唤起 Keeper，只每 30 秒低频检查一次 ADB。电视经历离线→上线、m-ui 重启或电视 IP 变更后，才会开始一轮新的恢复会话。

## 兼容性与前提

电视需要满足：

- 与路由器位于同一局域网，且客户端之间可以互相访问
- 开放小米电视局域网控制接口（默认 TCP `6095`）
- 已开启网络 ADB（默认 TCP `5555`），并允许路由器的调试授权

路由器需要满足：

- OpenWrt / PandoraBox，使用 `procd` 管理服务
- 系统中有 `wget`、`jsonfilter`、`awk`、`sed` 等常见基础命令
- 当前随项目提供的预编译 `m-adb` 仅支持 Linux ARMv7；其他架构需要自行交叉编译

已验证环境：

- PandoraBox 20.01
- P&W R619AC（ARMv7）
- 小米电视，ADB 与 6095 局域网接口可用

## 快速开始

完整步骤见[安装指南](docs/INSTALL.md)。以下是在项目文件已经上传至路由器 `/tmp/m-ui` 后的安装命令：

```sh
cd /tmp/m-ui
TV_IP=192.168.1.100 sh install-router.sh
m-ui
```

将 `192.168.1.100` 换成电视的实际 IP。安装脚本升级时会保留已有的 `/etc/m-ui/config`。

首次建立 ADB 连接时，电视会出现调试授权弹窗。请选择允许；设备名通常显示为 `m-ui@router`。后台服务会自动继续重试。

如果电视彻底断电后会自动关闭 ADB，再按[安装指南](docs/INSTALL.md#5-可选安装-adb-keeper)一次性安装 ADB Keeper。Keeper 不联网、不常驻、不显示界面，仅在 m-ui 唤起时恢复 Android ADB 设置。

## 管理菜单

在路由器 SSH 终端中运行：

```sh
m-ui
```

菜单如下：

```text
0. 退出设置
1. 设置电视 IP 地址
2. 查看电视已安装应用
3. 设置电视自启动应用
4. 设置电视自启动应用延迟
5. 启动 m-ui
6. 停止 m-ui
7. 重启 m-ui
8. 查看 m-ui 状态
9. 查看 m-ui 日志
10. 设置 m-ui 开机自启
11. 取消 m-ui 开机自启
```

也可以直接执行非交互命令：

```sh
m-ui status
m-ui logs
m-ui start
m-ui stop
m-ui restart
m-ui enable
m-ui disable
m-ui version
```

## 配置与日志

配置文件：`/etc/m-ui/config`

| 配置项 | 默认值 | 说明 |
| --- | --- | --- |
| `TV_IP` | `192.168.1.100` | 电视 IPv4 地址 |
| `TV_ADB_PORT` | `5555` | 电视网络 ADB 端口 |
| `AUTOSTART_PACKAGE` | 空 | 自启动应用包名 |
| `AUTOSTART_APP_NAME` | 空 | 菜单显示用的应用名称 |
| `POLL_INTERVAL` | `2` | 屏幕状态轮询间隔，单位秒 |
| `LAUNCH_DELAY` | `8` | 检测到亮屏后的等待时间，单位秒 |

电视 IP 可以直接通过菜单第 `1` 项修改；后台服务会在下一轮检测时自动使用新地址，无需重启。

主日志位于 `/tmp/m-ui.log`，存放在内存文件系统中，重启路由器后会清空。文件超过约 128 KiB 时会只保留最近 200 行；m-ui 同时调用 `logger` 写入系统日志，系统日志的保存策略由路由器自身配置决定。

实际启动等待时间约为：`0～POLL_INTERVAL 秒的检测等待 + LAUNCH_DELAY`。例如轮询间隔 2 秒、延迟 3 秒时，通常会在亮屏后约 3～5 秒启动应用。

## 升级和卸载

重新运行 `install-router.sh` 即可覆盖程序文件，现有配置和 ADB 密钥不会被改动。如果服务原本正在运行，安装完成后会自动重新启动。

默认卸载保留配置和 ADB 密钥：

```sh
sh uninstall-router.sh
```

同时删除配置和 ADB 密钥：

```sh
sh uninstall-router.sh --purge
```

## 可选：本地 Web 遥控器

仓库根目录还保留了开发过程中使用的本地 Web 遥控器，可获取电视信息、列出/启动应用并发送常用遥控按键：

```sh
python3 server.py
```

浏览器打开 <http://127.0.0.1:8765>。服务默认仅监听本机地址；它不是 m-ui 后台服务的必要组件。

## 开发与测试

需要 Go 1.22 或更新版本：

```sh
go test ./...
sh tests/test_m_ui.sh
sh build-m-adb.sh
```

更多信息见[开发说明](docs/DEVELOPMENT.md)、[故障排查](docs/TROUBLESHOOTING.md)和[安全说明](SECURITY.md)。版本变化记录在 [CHANGELOG.md](CHANGELOG.md)。

## 已知限制

- 未安装 ADB Keeper 时，m-ui 仍只识别运行期间观察到的 `OFF → ON`。如果电视亮屏时直接断电，恢复后可能不会触发应用启动。
- ADB Keeper 依赖电视在 ADB 关闭时仍提供 `6095` 接口，且固件遵循 Android 的 `adb_enabled` 设置。必须在自己的电视上做彻底断电测试。
- Keeper 连续恢复 3 次仍失败时，m-ui 会暂停当前会话而不会无限唤起应用；详细原因需结合日志排查。
- 电视固件升级后可能关闭 ADB、清除 Keeper 权限或调试授权，也可能改变 `dumpsys` 输出和 `6095` 接口行为。
- 预编译 ADB 客户端目前只提供 ARMv7 版本。

## 致谢

电视 6095 局域网接口的探索参考了[这篇小米电视 API 文章](https://gddhy.net/2026/xiao-mi-dian-shi-api/)。

本项目与小米、哔哩哔哩及相关应用厂商无隶属或官方合作关系。

## 许可证

本项目采用 [MIT License](LICENSE)。
