# 播放稳定性诊断 V2（仅采集，不改变恢复策略）

本方案以 `main` 的 `PlaybackCoordinator`、`DiagnosticLogs`、原生 `AudioService` 和 `SylphyApplication.engine()` 为基础。

## 采集边界

- **Dart JSONL（用户主动启用）**：每条事件带 `utc`、同一 Dart 实例内递增的 `seq`、`uptime_ms`（单调时钟），播放操作额外附带 `intent`、`load`、`nav`、`focus_epoch`，便于识别旧回调；不会保存曲名、曲目 ID、地址、文件路径、认证信息或异常原文。
- **Android 原生快照**：运行在 AudioService 使用的长期 FlutterEngine 上，不依赖 MainActivity。记录 `native_pid`、`native_seq`、`service_alive`、逻辑 FGS 请求、逻辑已确认、当前 OS 尽力查询 FGS、WakeLock、交互/省电状态、AudioManager 系统级音乐活动、MediaSession 状态及其进度锚点。`os_fgs=unknown` 不等于否定。某些平台可能无法查询。
- **独立 logcat**：`SylphyMedia`、`SylphyLifecycle`、`PowerKeeper.Audio`、`AudioTrack`、`AudioFlinger` 的消息**不会直接进入应用 JSONL**；PowerKeeper 属于厂商私有日志，应用通常无权读取。
- **尚无 PCM 实际流量测量**：此补丁没有改 libmpv；不能把 `playing`、`session_moving`、`music_active` 或 `progress_resumed` 等价为 AudioTrack 成功写入帧或扬声器发声。真正区分“mpv 不再产出 PCM”和“AudioFlinger/PowerKeeper 暂停旧轨”，需要对 libmpv `ao_audiotrack` 写入帧数、播放头、欠载、Session ID 增加原生可观测接口，或在复现现场通过 `dumpsys` 双快照验证。

## 新的故障链

1. `play_requested(intent=N)` / `android.snapshot(stage=play_requested)`：请求前，记录原生服务、FGS、WakeLock 状态。
2. `audio_focus.focus_request` / `focus_result(granted=…)`：验证焦点申请结果，而非将播放命令成功误当作焦点授权。
3. `source_selected(source=cache|local|proxy)`、`native_open_started` / `native_open_after`：验证完整缓存优先及 mpv 打开行为。只记录来源类别，不保存地址。
4. `native_play_started` / `native_play_completed` / 原生快照：确认异步命令执行和 OS 服务状态。
5. `resume_probe_armed` / `resume_probe_fired`：比较 `resume_ms` 与 `elapsed_ms`、`progress_gap_ms`；Dart Timer 在后台被冻住时，实际耗时会明显大于计划值。
6. `output_recovery_started`、`audio_output_reload_started`、`audio_output_reload_requested`、`resume_same_track_reopen`：关联一次 AO 恢复尝试和它前后的系统状态。
7. `progress_resumed(delay_ms, position_ms)`：只有进度推进才记录；这是 mpv 进度证据，**不是 PCM 可听证据**。

所有原生快照是异步尽力采集，最多等待两秒，失败只写 `snapshot_failed`；不能阻塞播放器或触发重试。捕获原生系统状态与原始命令严格分开。

## 复现与导出

1. 在 App 设置中打开已有的诊断记录开关。
2. 选择已完整缓存歌曲，播放约 20 秒、锁屏、暂停 3 分钟，再用通知 Play；不要立即进入前台。重复一次长暂停（15 分钟以上）和未完整缓存曲目。
3. 遇到无声且进度不动时，先运行 `tool/capture_playback_stall.ps1`，**不要先切歌**。它两次抓 `media.audio_flinger` 和音频、FGS、PowerKeeper 相关快照，用以比较是否真正有轨道帧数变化。
4. 等待自动 `ao-reload`、观察是否恢复，再从设置导出 SylphyMusic diagnostics。若需要核对 logcat，请将脚本归档文件与应用诊断一起分析。
5. 分享前检查原始 `dumpsys` / logcat 是否包含媒体元数据、通知标题、设备信息或第三方 App 相关内容；将其脱敏。原始文件默认放在 `.private/`。

## 判读规则

- `native_play_completed` + 原生 `os_fgs=no` / WakeLock=false：优先查后台启动受限；`os_fgs=unknown` 不视为拒绝。
- `os_fgs=yes`、WakeLock=true，但 `progress_gap_ms` 持续增大：前台服务不是充分条件；对照 PowerKeeper、AudioFlinger 的 AudioTrack Session ID 与 PCM 帧计数。
- 原生 `media_state` 仍显示 playing，但 `resume_probe_fired` 一直没有来：后台 Dart Timer/执行权可能被延迟；需要 logcat 与系统 `dumpsys power` 核实。
- `ao_reload_after` 后恢复进度，且 FGS、路由均未变化：更支持旧 AO/AudioTrack 输出上下文问题，但不单凭进度确认声音。
- 完整缓存仍有故障：不能归因于网络代理。缓存切换只影响来源，不会自动修复 FGS/AudioTrack。

**本补丁只增加观测能力，不改变现有 12 秒 AO 恢复、15 分钟长暂停重开、音频焦点或媒体通知政策。**

## 本地应用记录（2026-11-11）

本轮在普通版和 OpenList 现有工作区通过补丁检查并直接应用，保留缓存优先恢复、歌词行内翻译及 OpenList 播放租约等已有改动。Dart 文件已格式化。本文复现流程和附带 ADB 工具仅供用户主动验证，本轮未执行设备采集、测试、静态分析或应用启动；编译结果见 [PROGRESS](PROGRESS.md)。

编译适配：应用层直接调用 AudioService 静态快照需要解析其 AndroidX Media 父类，已在 app 模块显式声明 `androidx.media:media:1.7.0`，与现有 audio_service 插件依赖一致。
