# 诊断日志（用户主动启用）

设置 → 诊断与反馈 → 记录诊断日志。默认关闭；开关状态保存在既有 settings 表的 `diagnostic_logs_enabled` 字段。开启后开始记录，关闭后停止，历史文件仍可导出/清除。应用重启时按上次选择继续。

记录内容：事件 UTC 时间、播放器开始/完成/切歌/缓冲/播放状态、失败与恢复尝试、Android/Flutter 应用可见性、媒体代理请求结果。刻意不记录曲目名、来源 ID、账号、Token、URL、文件路径、原始异常文字、堆栈、音频字节。日志不能代替系统 logcat；Android 系统杀进程、原生崩溃及进程已经停止时的事件可能无法记录。

后台播放 P0 补丁增加本地代理探测 / 重启事件与 `dart_timer_delayed`，白名单字段 `gap_ms` 记录 Dart 看门狗相邻回调间隔。代理健康只表示回环 HTTP 监听器响应，不代表远程音源正常。Android 原生端另以 `SylphyLifecycle` 标签向系统 logcat 记录 Application 创建、Activity 可见 / 隐藏和进程 PID，不含来源、账号或曲目信息；这些原生日志独立于应用诊断开关，不包含在应用导出的诊断文件中。

播放稳定性诊断 V2 增加 Dart 单调时间与序列号、播放意图 / 加载代次、缓存优先来源决策、音频焦点结果、恢复检查实际延迟、AO 重载前后 Android 服务快照。Android 快照不包含 AudioTrack PCM 写入帧数与播放头，不能单凭 MediaSession 进度判断发声。详见 [播放稳定性诊断 V2](PLAYBACK_STABILITY_DIAGNOSTICS_V2.md)。

磁盘使用：保存在应用私有目录 `sylphy_music/diagnostics/`，最多 4 × 1024 KiB 的 JSON Lines 日志，满额轮转，追加由异步写队列处理；导出等待队列写入完成。日志记录失败不会中断音乐播放。关闭仅停止写入；清除操作删除保留的轮转文件。卸载应用会清除应用私有文件。

导出：平台文件保存对话框 `.txt`；Android/Windows 可在系统分享界面作为文本附件分享。Linux 因 share_plus 不支持共享文件，使用“导出诊断日志”保存后通过文件管理器分享。分享前建议检查文件，文件交由用户选择的第三方应用后不再受本应用控制。

以下命令仅供用户自主验证参考，不属于默认交付流程：

```
flutter pub get
flutter analyze
flutter test test/diagnostic_logs_test.dart
flutter test
flutter build apk --release
```

用户可在 Android 真实设备观察长时间锁屏、自动切歌、弱网、手动暂停、媒体通知状态，以及分享应用对附件的接收行为。此功能不申请额外媒体/文件权限。

## 推荐与 LLM 响应诊断

沿用设置 → 诊断与反馈 → 记录诊断日志开关和导出入口。开启后，重新生成每日精选 / 专辑推荐或执行 LLM 连接测试即可采集；命中已有快照时记录 snapshot_reused，不会为了记录日志强制请求 LLM。

- recommendation：generation_started、snapshot_reused、generation_empty、local_selected、llm_applied、local_fallback、generation_completed、generation_failed；type 区分 daily / albums，记录结果数和固定原因码。
- llm：request_started、response_received、request_succeeded / request_failed；request_id 关联同次请求，type 区分 daily / albums / connection_test。记录参与方式、候选数、请求数、HTTP 状态、耗时、实际接收字节数、模型内容字符数、有效结果 / 推荐词数、无效 / 重复 ID 数，以及可用的 Token 用量和结束原因。
- stage：prepare / connect / read_response / response_json / model_json。失败 reason 区分 disabled、configuration_changed、insecure_endpoint、response_too_large、http_error、timeout、network_error、invalid_json、invalid_envelope、missing_choices、missing_message、missing_content、content_too_large、missing_order、no_valid_ids、request_error 等；结合 http_status 可区分鉴权、限流或服务异常。

导出仍只包含白名单字段、整数和固定枚举，不写入服务地址、模型名、密钥、曲目 / 专辑元数据、模型推荐正文、原始服务响应、异常文字或堆栈。详细响应及错误文字仍仅在测试弹窗中查看。日志失败不影响推荐和播放；关闭开关后不新增记录。
