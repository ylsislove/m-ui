# 安装指南

## 1. 准备电视

1. 给电视设置固定 DHCP 租约，避免 IP 变化。
2. 确认电视与路由器处于同一局域网，且未启用访客网络或客户端隔离。
3. 在电视的开发者设置中开启 ADB 调试或网络调试。
4. 记下电视 IP；下文以 `192.168.1.100` 为例。

可以从电脑先验证两个端口：

```sh
nc -vz 192.168.1.100 5555
nc -vz 192.168.1.100 6095
```

部分系统没有 `nc`，也可以直接在浏览器访问：

```text
http://192.168.1.100:6095/request?action=isalive
```

注意：接口可访问只代表电视在线，不能代表屏幕是亮着的。

## 2. 上传项目文件

在电脑上下载或克隆本项目：

```sh
git clone https://github.com/ylsislove/m-ui.git
```

然后将整个目录传到路由器。示例中的路由器地址是 `192.168.1.1`：

```sh
scp -r m-ui root@192.168.1.1:/tmp/m-ui
```

如果下载后的目录名称不同，只要保证路由器上的目录同时包含以下文件即可：

```text
m-ui
m-ui.init
install-router.sh
dist/m-adb-linux-armv7
```

## 3. 安装

通过 SSH 登录路由器：

```sh
ssh root@192.168.1.1
cd /tmp/m-ui
TV_IP=192.168.1.100 sh install-router.sh
```

安装脚本会检查必要命令和 CPU 架构，然后写入：

```text
/usr/bin/m-ui
/etc/init.d/m-ui
/usr/lib/m-ui/m-adb
/etc/m-ui/config
```

如果 `/etc/m-ui/config` 已存在，安装脚本不会覆盖它。

## 4. 完成 ADB 授权

运行管理菜单并启动服务：

```sh
m-ui
```

选择 `5. 启动 m-ui`。第一次连接时，电视应显示 ADB 调试授权弹窗，设备名称通常为 `m-ui@router`。选择始终允许后，m-ui 会在下一轮自动连接。

如果弹窗没有出现，可在路由器上手动触发：

```sh
/usr/lib/m-ui/m-adb -s 192.168.1.100:5555 connect 192.168.1.100:5555
```

ADB 私钥会自动生成在 `/etc/m-ui/adbkey`，权限为 `600`。不要把它提交到 Git 仓库或发给他人。

## 5. 可选：安装 ADB Keeper

如果电视彻底断电后会自动关闭 ADB，可在电脑上用官方 Android Platform Tools 执行：

```sh
adb connect 192.168.1.100:5555
adb install -r dist/m-ui-adb-keeper.apk
adb shell pm grant io.github.ylsislove.mui.adbkeeper android.permission.WRITE_SECURE_SETTINGS
```

将 IP 换成电视实际地址。第一次连接时需要在电视上确认这台电脑的 ADB 授权。

如果从 `v1.3.2` 或更早版本升级时出现 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，是因为早期发布版的签名密码已经丢失，无法继续使用原签名覆盖安装。只需执行一次干净迁移：

```sh
adb uninstall io.github.ylsislove.mui.adbkeeper
adb install dist/m-ui-adb-keeper.apk
adb shell pm grant io.github.ylsislove.mui.adbkeeper android.permission.WRITE_SECURE_SETTINGS
```

这只会重装无用户数据的 Keeper，不会影响路由器上的 m-ui 配置。`v1.3.3` 之后的 APK 使用固定保存的新签名，可继续通过 `adb install -r` 正常升级。

Keeper 不申请联网权限、不常驻、不显示界面。ADB 可用时，m-ui 会通过 ADB 启动一次 Keeper 的 `NoDisplay` 活动；Keeper 写入 Android 标准的 `development_settings_enabled` 和 `adb_enabled`，安排 5、10、15、30、60、90 秒的非唤醒重试，然后立即退出。开机广播是辅助路径，主恢复路径利用部分小米电视开机早期短暂开放 ADB 的窗口。

短暂离线时 `6095` 不会启动 Keeper；只有电视连续离线至少 120 秒后重新上线、ADB 仍不可用时，才会单次用于彻底断电兜底。可以做一次彻底断电验证；成功时，`m-ui logs` 会出现“已在冷启动 ADB 窗口中优先启用 Keeper 无界面后台恢复”“ADB Keeper 有限后台恢复已准备”或“已通过 6095 单次唤起 Keeper 兜底恢复”，并最终在确认真实亮屏后启动用户应用。

## 6. 选择应用并启用服务

再次运行 `m-ui`：

1. 选择 `1`，确认或修改电视 IP 地址。
2. 选择 `2`，确认能读取电视应用列表。
3. 选择 `3`，设置希望亮屏后启动的应用。
4. 选择 `4`，设置启动延迟。
5. 选择 `5`，启动后台服务。
6. 选择 `10`，设置路由器开机自启。

最后选择 `8` 检查状态，并实际让电视息屏再亮屏测试一次。

## 7. 升级

上传新版本文件并再次运行安装脚本即可。已有配置、应用选择和 ADB 授权都会保留：

```sh
cd /tmp/m-ui
sh install-router.sh
```

如果电视 IP 发生变化，运行 `m-ui` 后选择 `1. 设置电视 IP 地址` 即可。后台服务会在下一轮检测时自动改用新地址，无需重启。安装时传入的 `TV_IP` 环境变量只在第一次创建配置时生效。

路由器上的 `uninstall-router.sh` 不会删除电视上的 Keeper。如果不再使用，请在 ADB 可用时另行执行：

```sh
adb uninstall io.github.ylsislove.mui.adbkeeper
```
