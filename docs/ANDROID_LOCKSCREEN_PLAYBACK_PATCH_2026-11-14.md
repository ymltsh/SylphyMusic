# Android Media3 连续焦点 + 后台 / 锁屏稳定性整合补丁（2026-11-14）

基线：`ymltsh/SylphyMusic` main `d4066db8eec973dae1bc993350000bce780f543b`。
目标：减少长时间锁屏 / 后台运行时的意外停止，记录能定位前台服务、焦点、锁与原生输出的证据。
增加跨曲目 AudioFocus 租约复用：SetMedia 继承 HELD、open 仅在没有有效焦点时 abandon，焦点回调按独立 focusGeneration 校验；同曲有限重开也不释放焦点。

## 依据与限制

2026-11-14 用户诊断记录中，UTC 06:00:57 歌曲从 0 开始，06:02:43 Flutter 进入 paused，06:32:11 从 107291ms 同曲重载。其间约 29m27s，无其他导出事件；`uptime_ms` 仅增加约 4m44s，怀疑设备长期休眠。用户明确：停播超过五分钟再恢复均属于其发现故障后手动操作。**日志没有记录系统焦点、FGS、WakeLock 或 PCM 帧计数，不能断言原始根因。**

## 修改

- 独立 `PlaybackWakeLease` 定时续期 35 秒 PARTIAL_WAKE_LOCK，每 10 秒刷新；不再依赖 libmpv/JNI 采样回调与主线程定期触发 `notifyState()`。暂停 / 结束 / 错误 / 销毁及时释放，前台准备最多 60 秒，暂时失焦最多保留 30 秒，原生 JNI 采样线程彻底停滞超过 90 秒则停止租约并报错；不无限占用 CPU。独立线程的采样心跳不依赖 Android 主线程，因此单纯 UI 主线程卡顿不应导致误判。
- 只有**同一条音频已经实际观察过媒体进度推进**、焦点保持、文件已加载、没有 Seek/正在打开，且同曲未恢复过，20 秒不推进且非 `paused-for-cache` 真缓冲才尝试**一次同曲重新打开**；不会跳歌。恢复后再次不推进依然在原 30 秒截止上报错误，不增加无限重试。
- 结构化诊断新增 `audio_focus_*`、`playback_intent_changed`、`wake_lease_state`、`native_poll_gap`、`native_poll_timeout`、`wake_transient_expired`、`wake_start_timeout`、`stall_reopen_requested`、`native_playback_failed`、`playback_heartbeat`、`media3_notification_*`、`media_service_created/destroyed` 等。
- Android 原生端在用户开启诊断后额外持久化两段轮转备份（每段约 512 KiB），Flutter 导出加入 `native_audio_backup` 段，可能与已有记录重复。关闭诊断会清理原生备份；日志清理也会清理备份。它减少了 Dart 后台回调延迟带来的关键事件丢失，但不替代 Android logcat，也不提供 PCM 帧计数。
- 统一 `native_uptime_ms`（不包括深度休眠）与 `elapsed_ms`（包含休眠）。**Media3 notification Future 完成不等于系统已确认前台服务；`os_fgs` 仅使用废弃的 `getRunningServices` 尽力观测本服务，`unknown` 不视为失败**。日志只含白名单事件与字段，不含歌名、URI、令牌和错误原文；logcat 只输出枚举状态。现有导出在 Dart 停顿时可能丢失尚未投递的原生日志，需要配合 adb logcat/dumpsys。

## 本地验证

```sh
kotlinc android/app/src/main/kotlin/com/ymltsh/sylphymusic/playbackcore/PlaybackRecoveryPolicy.kt tool/PlaybackRecoveryPolicyTest.kt -include-runtime -d /tmp/sylphy-recovery-test.jar
java -jar /tmp/sylphy-recovery-test.jar
flutter test test/playback_native_test.dart
flutter analyze
flutter build apk --release
```

## 真机验收

1. 锁屏并持续播放完整缓存音乐 2～4 小时，重复 3 次；应持续切歌。
2. 经过 20 分钟后模拟短暂音频焦点中断，确认焦点返回可继续播放，真实暂停不持有 WakeLock。
3. 用 ADB 强制模拟 AudioTrack 停滞或慢速缓冲，验证最多一次 `stall_reopen_requested`，未推进则最终失败，不能自动跳歌。
4. 故障前后分别记录 `adb shell dumpsys power`、`adb shell dumpsys media_session`、`adb shell dumpsys media.audio_flinger` 与 `adb logcat -d -s SylphyPlayback:I '*:S'`。判断时对比 Android FGS 与 PCM/播放头状态。
5. 明确区分：媒体 `time-pos` 推进仍不能证明物理扬声器真实发声；需要人工听感或 AudioFlinger 帧数辅助确认。

未通过设备测试前，不应宣称彻底修复。此前 Android Dart 旧 AO 补丁不应叠加在新的 Media3 原生播放器路径上。
