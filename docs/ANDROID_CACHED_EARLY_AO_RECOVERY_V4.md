# SylphyMusic — Android 完整缓存快速 AO 恢复 V4

## 基线与适用范围

- 以 2026-11-11 读取到的 `ymltsh/SylphyMusic` 最新 `main` 为代码上下文；`playback.dart` blob `9f14443a875bb1c6ab3ffbd9de366b1431d3f9e9`，`diagnostic_logs.dart` blob `61df232cc31fe909cf89d56b7d8b22e19feddfe0`。
- 代码已包含之前的 V2 诊断日志、EOF 竞争防护和 V3 单曲循环进度基准修复。**不要再次叠加旧版本补丁**。
- 本补丁仅针对：Android 下，`play()` 复用已打开的 **本地文件或已完整缓存文件**（非 `proxy`），而且此前处于暂停状态。
- 不改变首次打开新歌曲、代理/网络流、媒体预缓存、FGS/WakeLock、焦点策略、淡入淡出、缓存租约或队列管理。

## 行为变化

1. 既有 `native.play()` 返回后，仍建立 12 秒验证定时器。
2. 在播放意图未变化的前提下，于约 2 秒和 3 秒采样进度。两个样本都必须满足：`playing=true`、`buffering=false`，不在打开/seek/循环回绕/切歌/其他恢复中，尚未确认真实位置推进，采样位置距基线不超过 250ms，且进度时钟自上次有效推进已分别停滞 >=1800ms / >=2500ms。
3. 只有当前复用的是完整缓存/本地输出、2 秒样本符合条件且 3 秒样本也符合条件、同一 intent 尚未执行过 AO reload，才调用**已有** `_reopenUnconfirmedResume(..., fromEarlyProbe: true)`。
4. 仍由原有 `NativeCommandGate` 串行执行最多一次 `ao-reload`。成功请求后照旧验证进度；仍无进度时，原有 12 秒复查可触发一次同曲重新打开，不自动跳歌。
5. 如果 Timer 被后台冻结延迟（2 秒检查实际超过 3 秒或 3 秒检查超过 4.5 秒），**不以两条迟到事件作为独立故障证据**；继续使用原来的 12 秒验证。
6. 即使用户关闭“诊断日志”开关，早期恢复仍生效。开关只控制文件持久化，不控制播放策略。

## 应用

解压后在仓库根目录执行：

```bash
git apply --check SylphyMusic-Android-Cached-Early-AO-Recovery-V4.patch
git apply SylphyMusic-Android-Cached-Early-AO-Recovery-V4.patch

dart format lib/services/playback.dart lib/services/diagnostic_logs.dart lib/services/early_resume_recovery_policy.dart test/early_resume_recovery_policy_test.dart
flutter test test/early_resume_recovery_policy_test.dart
flutter test test/playback_reliability_test.dart test/diagnostic_logs_test.dart test/media_session_projection_test.dart
flutter analyze
flutter build apk --release
```

`git apply` 对仓库有修改时优先检查 `--check` 的实际结果。如不适用，请对照最新 `playback.dart` 适配，切勿使用 `--reject` 后忽略失败块。撤销：

```bash
git apply -R SylphyMusic-Android-Cached-Early-AO-Recovery-V4.patch
```

## 新增日志

- `resume_probe_armed`: `output_state=unverified`、`reused_output=true|false`。
- `early_resume_probe`: `stage=early_2s|early_3s`、`early_stalled=true|false`、`reused_output`、`delta_ms`、`position_events`、`progress_gap_ms`、原有 `intent/load`，并继续采集原生系统快照。
- `early_recovery_decision`: `reason=early_no_progress|progress_confirmed|first_probe_not_stalled|second_probe_not_stalled|guarded`。
- `output_recovery_started`: `trigger=early_no_progress`，`output_state=recovering`；12 秒/45 秒触发仍分别为 `resume_check` / `watchdog`。
- `progress_resumed`: `output_state=advancing`，仍只是 **mpv 媒体位置推进**的证据，不能证明 PCM 实际发声。

不记录曲目名、URI、账号、Token、路径或原始异常文本。底层 AudioTrack PCM 帧数仍需 libmpv 输出层插桩。

## 真机验收重点

1. **重现样本**：完整缓存的歌曲在锁屏/后台发生焦点中断后，约 1–2 分钟点击通知栏 Play。检查 2s/3s 均 `early_stalled=true` 且触发 `early_no_progress`，随后观察 `progress_resumed`；*不能仅凭命令返回宣称有声*。
2. **正常本地恢复**：2s 前有有效进度，不应出现 `output_recovery_started trigger=early_no_progress`。
3. **慢速真正缓冲**：`buffering=true` 时绝不快速 AO 重载；原 12 秒兜底保留。
4. **用户暂停/切歌/seek/单曲循环**：旧 intent 的快速检测不能操作新歌曲；单曲循环不应再次将旧曲尾作为看门狗基准。
5. **长时间后台冻结**：迟到的 2s/3s 探针不能在恢复瞬间误触发快速 AO。
6. **代理流/首次打开**：不走快速 AO 恢复，仍走原来的源刷新/验证。
7. **关闭日志开关**：恢复仍按上述逻辑执行，但不再写诊断文件。

## 验证边界

已在由 GitHub 当前目标源码片段组成的合成上下文中执行 `git apply --check`、实际应用、反向检查并通过。因运行容器无法连接 git 远程、没有 Flutter/Dart SDK，本次**未在真实完整 checkout 执行编译、静态分析、单元测试，也未运行 Android 真机**。这不是 PCM 级根因修复，而是降低用户遇到已确认输出停滞时的无声等待。

## 本地应用记录（2026-11-11）

本轮在已具备 V2 诊断、EOF 防护和 V3 回绕基准修复的普通版与 OpenList 工作区通过检查并直接应用 V4，未重复叠加前置补丁。保留 OpenList 租约与其他已有修改，Dart 文件已格式化，附带策略测试已纳入但未执行。按用户“应用，推送更新”请求进行正式构建和双通道发布；测试、analyze、ADB 和设备矩阵未执行，实际发布结果见 [PROGRESS](PROGRESS.md)。
