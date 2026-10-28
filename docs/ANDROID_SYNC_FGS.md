# Android 手动同步前台服务

音乐源管理的「同步所有来源」「同步此来源」以及 WebDAV「只补全 WebDAV 标签（前台通知）」在用户点击后启动 dataSync 前台通知，索引与标签阶段分别显示进度，通知支持暂停。自动恢复 / 过期刷新仍是机会式任务，不从普通后台状态主动启动新 FGS。

SylphyApplication 持有 UI / 同步共用引擎，同时注册 audio_service 的缓存身份；音频服务释放时保留该引擎及缓存，防止第二引擎或 Dart 任务被销毁。缓存 Channel 迁移到 Application，Activity 只持有图标及通知权限请求。MainActivity 移除时清理 Activity handler，但不销毁共享引擎。

同步开始等待原生服务确认，失败不降级为无通知长任务。暂停 / 超时取消索引与标签请求，退出等待同步任务完成后关闭 SQLite。完整索引仍原子切换；标签按文件版本保留，下次手动补全跳过成功记录。

Android 13+ 通知权限拒绝不阻断前台服务；Android 12+ 后台启动限制、Android 15+ dataSync 累计时限与用户停止应用仍生效。进程死亡、系统停止或强停后不承诺继续运行。不同厂商电源策略需要真机验证。

验证入口：test/sync_foreground_test.dart；integration_test/sync_foreground_test.dart。普通原生测试验证前台同步；SYLPHY_FGS_TIMEOUT_TEST=true 仅用于受控测试 AVD，需外部驱动设置短时限、移除任务并重新打开 Activity。外部测试需恢复 device_config 和 compat 配置，不能对用户真机批量更改设置。

参考：[Android FGS 超时](https://developer.android.com/develop/background-work/services/fgs/timeout)、[Flutter 缓存引擎](https://docs.flutter.dev/add-to-app/android/add-flutter-screen)。
