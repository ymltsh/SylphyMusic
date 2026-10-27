# 诊断日志（用户主动启用）

设置 → 诊断与反馈 → 记录诊断日志。默认关闭；开关状态保存在既有 settings 表的 `diagnostic_logs_enabled` 字段。开启后开始记录，关闭后停止，历史文件仍可导出/清除。应用重启时按上次选择继续。

记录内容：事件 UTC 时间、播放器开始/完成/切歌/缓冲/播放状态、失败与恢复尝试、Android/Flutter 应用可见性、媒体代理请求结果。刻意不记录曲目名、来源 ID、账号、Token、URL、文件路径、原始异常文字、堆栈、音频字节。日志不能代替系统 logcat；Android 系统杀进程、原生崩溃及进程已经停止时的事件可能无法记录。

磁盘使用：保存在应用私有目录 `sylphy_music/diagnostics/`，最多 3 × 512 KiB 的 JSON Lines 日志，满额轮转，追加由异步写队列处理；导出等待队列写入完成。日志记录失败不会中断音乐播放。关闭仅停止写入；清除操作删除保留的轮转文件。卸载应用会清除应用私有文件。

导出：平台文件保存对话框 `.txt`；Android/Windows 可在系统分享界面作为文本附件分享。Linux 因 share_plus 不支持共享文件，使用“导出诊断日志”保存后通过文件管理器分享。分享前建议检查文件，文件交由用户选择的第三方应用后不再受本应用控制。

测试：

```
flutter pub get
flutter analyze
flutter test test/diagnostic_logs_test.dart
flutter test
flutter build apk --release
```

发布前仍须在 Android 真实设备验证至少 2 小时锁屏、自动切歌、弱网、手动暂停、媒体通知状态，以及授权分享应用对附件的接收行为。此功能不申请额外媒体/文件权限。
