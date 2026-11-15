# Android background media resume V2

Target: the repository default branch at commit `92f955f1887946f5acd9ed0ef5e06a602c6bdcee`.
This patch does **not** require the earlier V1 patch.

## Behaviour

- The native media button callback attempts a **provisional**, bounded FGS
  promotion before waiting on Dart/database/player work. If Dart does not
  confirm the play intent within 20 seconds, the provisional FGS is demoted.
- An already-started AudioService is not sent another FGS start request on
  every pause/resume. Android restriction exceptions are logged, not ignored
  by setting `foreground=true`. Failed promotions may be retried on a later
  eligible user command or state update (at most once per 3 seconds for
  passive updates). There is **no** permanent wake lock or bypass of Doze.
- A remote track that was using the Dart loopback proxy is reopened after a
  15-minute pause; local files and complete cache files stay on the fast
  play path. Existing `_loadCurrent` generation checks still guard racing
  track-navigation operations.
- Diagnostic events: `SylphyMedia` contains `fgs_service_started`,
  `media_play_request_native`, `fgs_promoted`, `fgs_denied`,
  `fgs_provisional_timeout`, `fgs_demoted`; Dart emits `play_requested`,
  `play_resolve_source_started`, `play_resolve_source_completed`,
  `resume_source_refresh`, `native_play_started`, `native_play_completed`,
  and `progress_resumed`.

## Tests

```sh
javac -d /tmp/sylphy-v2-jvm \
  third_party/audio_service/android/src/main/java/com/ryanheise/audioservice/ForegroundResumeState.java \
  tool/ForegroundResumeStateTest.java
java -cp /tmp/sylphy-v2-jvm ForegroundResumeStateTest
flutter test test/playback_reliability_test.dart
```

## ADB validation

On the affected Xiaomi device test separately: 1) foreground playback,
2) pause/background 20 minutes, 3) pause/background 60 minutes, 4) notification
play from the RARE standby bucket, 5) repeated play/pause and skip. Compare
`adb logcat -v time -s SylphyMedia:* flutter:* ActivityManager:*` with app
DiagnosticLogs. Verify *actual advancing audio position*, not only the
MediaSession state. A system-level `fgs_denied` cannot be bypassed by this
patch; it must remain visible so users can apply OS-supported background
execution settings if needed.

## 本工作区合并说明

本工作区已含 V1，播放层已适配合并：复用已有暂停时间字段，保留票据接近过期时刷新、原生命令排队超时保护、淡入期间的新暂停保护，以及 OpenList 工作区的播放租约。上述 Tests / ADB validation 为用户自主验证建议，本次仅执行编译与打包，不运行测试或设备验收。
