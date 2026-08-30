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
- 可选的无界面 ADB Keeper：利用电视开机早期短暂可用的 ADB 窗口自动恢复调试，无需 Root 或刷机
- `6095` 通常只用于在线探测和启动用户选择的应用；仅当电视连续离线至少 120 秒后重新上线、ADB 仍不可用时，才单次唤起 Keeper 作为彻底断电兜底
- 日志写入内存并自动裁剪，避免不断占用闪存和存储空间
- 附带无外部依赖的 ARMv7 ADB 客户端，无需在老路由器软件源中安装 `adb`

## 工作原理

```text
每 2 秒尝试读取 ADB 屏幕状态
        │                              │
        │ ADB 可用                     │ ADB 不可用
        ▼                              ▼
无界面启用 Keeper 后台恢复      通过 6095 被动判断在线/离线
        │                              │
同时核对 display 与 power       冷启动前 120 秒保持快速 ADB 探测
        │                              │
检测真实 OFF → ON               等待 Keeper 后台恢复 ADB
        └──────────────┬───────────────┘
                       ▼
               等待用户设置的延迟
                       │
               再次确认屏幕仍为 ON
                       │
               通过 6095 启动指定应用
```

电视息屏后通常仍可联网，因此 `isalive`、`ping` 或端口连通性无法区分“亮屏”和“息屏”。m-ui 同时读取 `dumpsys display` 的 `mScreenState`、`dumpsys power` 的 `mWakefulness` 与最近唤醒/休眠时间：任一明确为休眠就按 `OFF` 处理；如果 `reboot,quiet` 后系统虽报告 `Awake + ON`，但 `mLastWakeTime/mLastSleepTime` 仍为 `0/0`，也会等待真正的遥控唤醒记录后才判为亮屏，避免物理黑屏时在后台启动应用并播放声音。

部分小米电视开机时会先按持久配置启动 ADB，几秒后再由厂商设置服务关闭它。m-ui 在确认电视离线后的前 120 秒保持快速探测；冷启动快速阶段每 1 秒开始一轮尝试，并优先启动 Keeper、再读取完整屏幕状态。一次网络操作仍受超时限制，因此实际间隔可能略长。一旦抓到窗口，Keeper 会立即写回 Android ADB 设置，并安排 5、10、15、30、60、90 秒的非唤醒重试，然后退出，不占用电视前台。每次冷启动会话最多成功布置一轮，90 秒后自然结束，不会周期续期。

m-ui 会单独保留“已确认电视离线”的冷启动状态。开机早期的短暂 ADB 连接不会把冷启动误判为普通网络抖动；ADB 恢复后只有确认电视真实为 `ON` 才会启动用户应用。短暂离线时 `6095` 不会用于启动 Keeper，因此电视静默重启且屏幕为 `OFF` 时，m-ui 不会因为恢复 ADB 而主动唤屏。

部分电视彻底断电并重新接通电源后，要等用户按一次遥控器开关键或电视实体开关键才会真正开机，真正开机前 ADB 和 Wi-Fi 应该都不可用。m-ui 只在电视的 `6095` 接口连续离线至少 120 秒后重新上线、且 ADB 仍不可用时，通过 `6095` 单次启动 Keeper。短暂静默重启不会达到该门槛，单次请求失败后也不会在同一在线会话中循环重试。

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

如果电视彻底断电后会自动关闭 ADB，再按[安装指南](docs/INSTALL.md#5-可选安装-adb-keeper)一次性安装 ADB Keeper。Keeper 不联网、不常驻、不显示界面；m-ui 会在 ADB 可用时为下一次厂商关闭 ADB 的时序准备后台恢复。

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
- ADB Keeper 的自动恢复需要电视接受开机广播，或像已验证机型一样在开机早期短暂开放 ADB。如果固件从启动第一刻就关闭 ADB 且拦截第三方开机广播，在不 Root、不刷机且不主动唤屏的前提下无法自举恢复。
- 必须在自己的电视上做一次彻底断电测试；不同固件的 ADB 短暂窗口和后台限制可能不同。
- 电视固件升级后可能关闭 ADB、清除 Keeper 权限或调试授权，也可能改变 `dumpsys` 输出和 `6095` 接口行为。
- `adb shell reboot quiet` 仅是开发诊断命令，不等价于电视自身的静默重启；部分机型会进入低背光近黑、桌面仍在渲染或出声、遥控器暂时无法亮屏的异常状态。m-ui 正式逻辑从不执行该命令。
- 预编译 ADB 客户端目前只提供 ARMv7 版本。

## 致谢

电视 6095 局域网接口的探索参考了[这篇小米电视 API 文章](https://gddhy.net/2026/xiao-mi-dian-shi-api/)。

本项目与小米、哔哩哔哩及相关应用厂商无隶属或官方合作关系。

## 许可证

本项目采用 [MIT License](LICENSE)。
