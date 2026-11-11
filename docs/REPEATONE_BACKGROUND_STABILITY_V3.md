# SylphyMusic 单曲循环 / 后台恢复诊断 V3

## 原因与边界

这包基于 **2026-11-11** 读取到的公开 GitHub `main` 的 `lib/services/playback.dart` (blob `42d7d209...`)；用户日志显示应用已经含有 V2 诊断，因此本包把 V2 作为**可选前置**，不假定其已经推送到 GitHub。包中的 02 为上一轮 EOF 竞争补丁，03 是本轮新增补丁。先备份未提交的用户修改。

1. 单曲循环原 `_finished()` 调用 `native.seek(Duration.zero)`，未重置 `_watchdogPositionMs`，导致新一轮位置落在前一轮曲尾基准以下，12 秒恢复器误把正常推进当作停滞，可能连续 `ao-reload` + 同曲重开。
2. 曲尾 `player.stream.error` 可能先于 `completed` 到来，立即 `_failed` 会抢占正常 EOF；02 补丁短暂保留近曲尾错误，完成事件到来后忽略，真实错误仍交给原恢复器。
3. 对真实后台音频输出停滞，不缩短原 12 秒恢复阈值，而是新增 2 秒 / 3 秒纯诊断采样，记录位置基准、位移、事件数、缓冲与焦点等。遇到未确认进度时同时异步采集 Android 原生服务快照。

## 应用顺序

**当前本地仓库已经包含 V2 与 EOF 竞争修复时：只应用 03。**

```sh
git apply --check patches/03-repeatone-background-diagnostics-v3.patch
git apply patches/03-repeatone-background-diagnostics-v3.patch
```

**当前本地只有 V2（日志有 `android.snapshot` / `resume_probe_fired`，但没有 `end_error_deferred` 处理逻辑）时：**

```sh
git apply --check patches/02-eof-race.patch
git apply patches/02-eof-race.patch
git apply --check patches/03-repeatone-background-diagnostics-v3.patch
git apply patches/03-repeatone-background-diagnostics-v3.patch
```

**如果从远程 `main` 起步、尚未应用 V2：** 按照 01 → 02 → 03 顺序应用，每一步先 `git apply --check`。

> 由于用户本地分支可能比远程 GitHub 更新，**务必先 `git apply --check`**。如果某补丁已经在分支中，可能显示“已应用”或上下文不匹配；不要强行重复应用，也不要 `git reset` 覆盖用户工作。普通版与 OpenList 特性分支分别检查。

建议本地格式化和构建：

```sh
dart format lib/services/playback.dart lib/services/diagnostic_logs.dart
flutter build apk --release
```

本工具环境没有 Dart / Flutter SDK，尚未对完整项目编译；补丁在**带真实目标代码片段的合成基线**上通过 `git apply --check`、应用和反向检查。未运行测试、ADB 或真机验证。**未向 GitHub 提交、推送、发布。**

## 事件观测

- `end_error_deferred`、`end_error_ignored`：正常 EOF 与异常竞争；没有 `completed` 则仍会报错。
- `track_completed`：新增完成位置、时长与旧看门狗基准。
- `loop_seek_started`：进入单曲循环时重置看门狗基准、过期恢复检查；并设置第一条新循环位置的接收状态。
- `loop_old_position_ignored`：旧曲尾位置在 seek 附近流入，仅记录一次并丢弃该样本；最多等待 5 秒，避免长期过滤。
- `loop_first_position`：新一轮第一个接受的位置，`stage=fresh|fallback`；后续位置由原看门狗计算。
- `loop_seek_completed` / `loop_seek_superseded` / `loop_seek_failed`：成功、过期或异常。
- `early_resume_probe(stage=early_2s|early_3s)`：只在 Android 且用户开启诊断时记录。`baseline_ms`、`position_ms`、`delta_ms`、`position_events`、`watchdog_position_ms`、`progress_gap_ms`、`native_playing`、`buffering`、`mpv_confirmed` 和来源。
- 12 秒 `resume_probe_fired` 增加 `position_ms`、`watchdog_position_ms`、`position_events`、`native_playing`、`buffering`、`mpv_confirmed`；有助于识别“位置增长，但看门狗没确认”的假停滞。

## 真机观察矩阵

- 单曲循环完整缓存曲目 3 次以上；曲尾不应反复显示“加载失败”，应看到 `track_completed → loop_seek_started → loop_first_position`，且不再每轮触发 `resume_probe_fired`。
- 列表循环与切歌正常；旧的曲尾错误若未得到 `completed` 证实，仍应走失败恢复而不是永久屏蔽。
- 后台暂停 2～10 分钟，再用通知栏 Play；比较 `early_2s` / `early_3s` / 12 秒检查的真实位置差与媒体状态。正常恢复和卡顿均采集，以建立判读阈值。
- 确认用户 Pause、Seek、Next、焦点失去后旧探针不能触发 AO 重载。2 秒 / 3 秒探针从不执行播放恢复。

## 无法由此证明的内容

`Android.music_active` 为**系统级**指标，`MediaSession.session_moving` 是投影，`mpv.position` 是播放器进度；这些都不是 libmpv 所有 AudioTrack 的 PCM 写入帧数或 Android 播放头。彻底定位 PowerKeeper 对音轨的干预需要修改 libmpv AO 插桩或用 ADB 两次抓 `media.audio_flinger` 并结合 `AudioTrack`、`PowerKeeper.Audio` logcat。绝不记录媒体 URL、曲目身份、认证凭据、原生日志原文到公开诊断。

## 本地应用记录（2026-11-11）

两个工作区已含 V2 与 EOF 修复，因此按文档只应用 03，未重复应用 01 / 02。恢复超时日志的一处格式化上下文不能直接匹配，已按补丁新增字段适配合并，保留 OpenList 播放租约、前几轮代码及其他用户修改。Dart 文件已格式化；测试、ADB、启动与真机矩阵未执行，附件分析中的日志结论未在本轮独立复核。仅进行本地编译打包，结果见 [PROGRESS](PROGRESS.md)。原包中的 patches 路径为历史应用说明，所用原包保留在本地 .private/。
