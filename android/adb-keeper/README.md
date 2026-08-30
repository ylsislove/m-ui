# m-ui ADB Keeper

用于处理部分小米电视在彻底断电后自动关闭 ADB 的问题。

应用不申请联网权限、不启动常驻服务、不显示界面，只做以下事情：

1. m-ui 在 ADB 可用时启动它的 `NoDisplay` 活动，将 Android 标准设置 `development_settings_enabled` 与 `adb_enabled` 写为 `1`。
2. 安排 5、10、15、30、60、90 秒的非唤醒重试后立即退出，不占用或唤醒电视屏幕。
3. 同时声明开机广播接收器作为兼容尝试；部分小米固件会拦截第三方应用开机自启，主恢复路径不依赖该广播。
4. 短暂离线时不接受 m-ui 通过电视 `6095` 接口启动，避免静默重启时意外点亮屏幕；仅当电视完整离线至少 120 秒后重新上线且 ADB 仍不可用时，允许一次彻底断电兜底。

它需要在 ADB 尚可使用时安装，并通过 ADB 一次性授予 `android.permission.WRITE_SECURE_SETTINGS`。不需要 Root、刷机或系统签名。

## 构建

需要 JDK、Android SDK Platform 36 与 Build Tools 36.1.0：

```sh
sh build.sh
```

第一次构建会在 `.keystore/adb-keeper-v2.jks` 和 `.keystore/password-v2` 生成签名密钥与随机密码，两者都不会提交到 Git。更新已发布 APK 时必须同时保留这两个文件；也可通过 `ADB_KEEPER_KEYSTORE_PASSWORD` 提供密码。输出文件为 `dist/m-ui-adb-keeper.apk`，同时复制到仓库根目录的 `dist/`。
