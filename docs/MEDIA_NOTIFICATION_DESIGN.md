# Android 媒体通知：单一媒体会话与稳定时钟

适用：主分支 `3ad7d3db1197db418d5b29bbf19d05758b988a24`，不改变 libmpv 播放/代理/缓存/队列。

## 原则

- 只有一个 Android MediaSession。锁屏通知、媒体中心、耳机和蓝牙控制均以该会话为权威。
- **播放意图**决定是否需要保留 Android 前台服务与暂停命令；**原生播放器实际推进**决定系统进度时钟是否走时；**缓冲阶段**必须如实向系统报告，不能为了保活伪装成 `STATE_PLAYING`。
- 音频尚未产生连续的真实位置样本时，向系统发送 `BUFFERING` + `speed=0`，绝不能通过墙上时钟制造“已经播放”的进度。
- 真实开始播放后，发布一次带真实播放位置和倍速的锚点。系统根据位置与时间基准推算，不依赖高频 Dart 位置消息。
- 正常位置回调只更新 Flutter UI 和进度证据。仅在状态改变、速度改变、Seek、位置明显偏离或每 20 秒定期校准时发布新的 MediaSession 状态。
- Android 原生通知的重新构建以语义变化（BUFFERING→PLAYING、时钟启停、Seek、大幅跳变、元数据改变）为条件，绝不每隔 1 秒 `notify()`。
- 使用平台标准 MediaStyle；不维护额外自定义 RemoteViews 作为第二个媒体通知展示层。

## 证据与保护边界

`MediaNotificationClock` 在两个连续、非 Seek 的有效位置样本之间发现 80ms–4s 的实际推进，才允许走时；加载/切歌/Seek/暂停时失效旧证据。若进入明确 buffering，立即撤销旧证据；如果原生 buffering 标志滞后、但之后确实持续收到位置推进，则可以重新允许走时。

后台事件稀疏时短暂容忍丢失的 Dart 回调：最近 6 秒未确认进度才冻结；若仍处于 buffering，容忍期缩短为 2 秒。这一容忍期只在**此前已经确认真实播放**的条件下生效，不能使一首尚未开始的歌曲空走进度。

`MediaSessionPublishGate` 使用单调时间比较平台推算的位置与原生实际位置：偏差超过 1200ms 或 20 秒锚点到期再校准。状态变化时不等待阈值。实际通知刷新仍应交给标准 MediaStyle / MediaSession 管理。

## 原生生命周期

`AudioService.java` 中 `playing` 继续表达用户的播放意图，控制前台服务启动/停止（`enterPlayingState` / `exitPlayingState`），但 `getPlaybackState()` 将缓冲映射回 Android 的 `STATE_BUFFERING`。即使播放意图为 true，也不会把尚未开始解码的媒体伪装成 `STATE_PLAYING`。

Android 10 使用标准 MediaStyle 替代专用白色按钮 RemoteViews，因而该版本的按钮着色可能不同，但优先保证通知行为统一与系统状态同步。没有创建第二个 MediaSession、没有更换 libmpv。

## 验收

1. 断网加载 20 秒：通知进度保持 0，控制仍可暂停，最终失败有明确边界。
2. 本地缓存播放 5 分钟：通知、应用 UI、系统媒体中心之间误差保持在约 2 秒内。
3. 锁屏、后台、息屏持续 30 分钟：位置不持续停在 0；Android 原生状态不高频更新。
4. 缓冲/解缓冲、音频焦点丢失/恢复、手动暂停、倍速播放：速度冻结和恢复一致。
5. Seek 到 2:00，再切歌/快速跳歌：不会沿用旧歌曲的时间锚点。
6. Android 10、12、13+ 和至少一台类原生 Android、一台 HyperOS 设备实测。

## 可运行的检查

```bash
flutter analyze
flutter test test/notification_clock_test.dart
flutter test test/playback_reliability_test.dart

# 纯 JVM 原生通知刷新判定，无需 Android SDK
javac -d /tmp/sylphy-notification-test \
  third_party/audio_service/android/src/main/java/com/ryanheise/audioservice/MediaNotificationRefreshPolicy.java \
  tool/MediaNotificationRefreshPolicyTest.java
java -cp /tmp/sylphy-notification-test MediaNotificationRefreshPolicyTest
```

**注意：** 本补丁在离线环境对目标版本的源代码片段逐段比对，并在重建的对应片段上进行 `git apply` 正/反向检查。已运行 JVM 纯逻辑测试。未运行 Flutter/Dart 编译、Android 打包或真机验收，不把此补丁宣称为已被设备验证的修复。

## 参考

- Android Media3 后台播放：https://developer.android.com/media/media3/session/background-playback
- audio_service PlaybackState：https://pub.dev/documentation/audio_service/latest/audio_service/PlaybackState-class.html
- Auxio MediaSessionHolder / Progression：https://github.com/OxygenCobalt/Auxio
- Musify Flutter audio_service：https://github.com/gokadzev/Musify/blob/master/lib/services/audio_service.dart
