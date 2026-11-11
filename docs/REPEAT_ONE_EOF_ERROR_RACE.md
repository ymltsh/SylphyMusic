# SylphyMusic 单曲循环 EOF 错误竞争 — 诊断与候选补丁

基线：`ymltsh/SylphyMusic` 公开 main 分支的 `lib/services/playback.dart`（读取时文件 blob SHA `42d7d2099ccb1250c9914b482fbaf377982afb38`）。

## 日志证据

在用户诊断日志 `SylphyMusic-diagnostics-20261111_095646012042Z.txt` 中，7 次 `player_error` 里有多次处于同一首完整缓存歌曲的末尾：
- 2026-11-11 04:24:52.565Z：`player_error` → `reconnect_attempt`，166 ms 后 `track_completed index=5`，接着 `playing=true`；已发起的失败重试仍于 04:24:52.976Z 用 `resume_ms=186047` 重新打开缓存歌曲。
- 2026-11-11 04:28:04.251Z：同曲同样先报错，326 ms 后 `track_completed`，但后续 `_loadCurrent` 用 `resume_ms=185964` 再开。
- 2026-11-11 05:37:54.314Z：`player_error`，170 ms 后 `track_completed index=181`，又以 `resume_ms=186111` 重新打开。
- 2026-11-11 09:54:51.159Z、09:54:57.240Z：同一 index=181 再次重演，导致 `reconnect_attempt` 达 2 次。
- 2026-11-11 09:55:09.556Z：第三次 `player_error` 触发 `_failed` 的失败次数上限并暂停。此轮没有立即收到 `completed`，但很可能受前两次错误重试后近曲尾重新打开的影响，尚不能确认真实 mpv 错误原因。

缓存来自 `source_selected source=cache cache_hit=true`，并有 `player_opened`、`load_finished`，不是已证明的缓存校验失败。原始错误详情在隐私诊断文件中不可见，因而不能完全排除其他底层错误。

## 改动

1. 当播放器已播放、歌曲进度距已知时长末尾约 2.5 秒内收到 `stream.error` 时，暂缓 750 毫秒，不立即显示错误或重连。
2. 如果在此期间对同一个加载代次收到 `stream.completed=true`，取消挂起的错误，正常单曲循环。
3. 如果未收到完成事件，且歌曲/加载/导航/播放意图/循环代次均未变化，仍如实上报错误并进入既有恢复机制（避免吞掉真正的错误）。
4. `pause()`、`seek()`、新加载、关闭时取消挂起回调。
5. `_failed` 在数据库和重试延迟之后重新核对 `_transitionEpoch`，避免旧的恢复任务在单曲循环已经开始后又重载到曲尾。
6. 新增 `end_error_deferred`、`end_error_ignored`、`end_error_superseded` 等不含敏感信息的诊断事件。

本补丁不修改缓存格式、媒体代理、Android 前台服务、AO 重载策略或通知控制。

## 应用

```bash
git apply --check SylphyMusic-Repeat-One-EOF-Error-Race-Fix.patch
git apply SylphyMusic-Repeat-One-EOF-Error-Race-Fix.patch
dart format lib/services/playback.dart
flutter build apk --release
```

应保留当前仓库所有本地改动；如 `git apply --check` 不通过，不要强制覆盖。仅在用户明确允许后提交或发布。

## 新日志验收

同一首完整缓存歌曲设置单曲循环，连续播放至末尾多次。正常场景应出现 `end_error_deferred` → `end_error_ignored` → `track_completed`，而不应出现 `reconnect_attempt` 或加载失败提示。如果 `end_error_deferred` 之后没有 `track_completed`，应在约 750 毫秒后出现真实 `player_error`，以便继续追查。

验证范围：本地以 GitHub 检索到的代码片段重建合成源码基线，通过 `git apply --check`、正向应用和反向检查。**未在完整仓库或 Android 真机上构建、运行、测试。**

## 本地应用记录（2026-11-11）

在普通版与 OpenList 现有工作区通过补丁检查并直接应用，保留播放稳定性诊断 V2、缓存优先恢复及 OpenList 播放租约等已有改动。本文日志结论来自补丁作者，本轮未独立复核，也未执行上述设备验收建议。当前仅编译打包，不运行测试、静态分析、ADB 或应用启动；实际结果见 [PROGRESS](PROGRESS.md)。
