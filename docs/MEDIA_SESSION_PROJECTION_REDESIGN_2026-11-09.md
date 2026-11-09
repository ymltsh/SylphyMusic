# SylphyMusic 媒体通知协议重构（MediaSessionProjection）

**目标仓库**：`ymltsh/SylphyMusic`  
**精确基线**：`61e99bf783965ebd64456818b32605a300a67602`（2026-11-09；已包含音频焦点架构重构）  
**补丁**：`SylphyMusic-MediaSession-Projection-Refactor.patch`

## 0. 原因与边界

此次 Redmi / Xiaomi Android 14 日志证明：原生音轨被 `PowerKeeper.Audio` 暂停；切歌使旧 AudioTrack 销毁、新 AudioTrack 创建，播放恢复。某次卡住快照中 MediaSession 为 `BUFFERING`、进度 `speed=0`，但 FGS、WakeLock 和音频焦点均已满足。这意味着根本问题不能被重新绘制通知解决。

本方案修复**通知协议和资源管理语义**：不要把所有未推进视为正常 BUFFERING；不要让用户暂停时持续向系统宣称正在缓冲；临时焦点中断保留有界服务资格而不伪造进度；明确报告最终播放错误，让 Play 成为可执行动作。在底层真正恢复前仍由现存 V3 恢复路径提供有限同曲重开。本方案**不加入另一条自动重试计时器**，不覆盖 libmpv / AudioTrack 的所有权。

## 1. 来自成熟项目的取舍

| 参考 | 学到的具体原则 | 在此补丁中的采用 |
|---|---|---|
| Linthra `LinthraAudioHandler` | 播放模型到 MediaSession 的单一投影；用户暂停中断系统缓冲状态；短暂焦点保持服务且 `speed=0` | 新 `MediaSessionProjection`，focusHold/paused 分开 |
| Linthra #638 | 切歌加载应报告 `BUFFERING`，而不是 `STATE_CONNECTING` | preparing → `AudioProcessingState.buffering` |
| Linthra #751 | 用户暂停优先于底层异步 buffering | paused → ready/playing=false/rate=0 |
| Finamp | 统一发布控制、动作、seek，折叠卡片固定上一首/播放暂停/下一首 | 显式 compact indices、系统 skip/seek |
| Android Media3 | Android 13+ 系统基于 MediaSession 元数据和动作渲染；暂停后服务允许降级 | 不创建第二套通知；非 ongoing、停止前台配置明确 |
| SylphyMusic 现有实现 | `MediaNotificationClock` 根据真实原生进度证据走时 | **保留**并作为 projection 的 progressAdvancing 输入 |

不照搬 Linthra 在缓冲期间上报 speed=1 的选择；这里继续上报 0，避免被小米停止的旧 AudioTrack 在系统进度条里虚假前进。

## 2. 状态契约

| Runtime 输入 | MediaSession processingState | playing | speed | 传输按钮 / 资源行为 |
|---|---|---:|---:|---|
| 没有歌曲 | idle | false | 0 | 不展示上/下一首 |
| 用户暂停，即使原生仍 buffering | ready | false | 0 | Play；允许正常降级 FGS |
| 有限时间的临时焦点中断 | ready | true | 0 | Pause 可终止自动恢复资格；保留当前 FGS |
| 开始/切歌/Seek 加载且用户想播放 | buffering | true | 0 | 等待新音源、保持服务 |
| 原生返回 Play，但尚无真实进度 | buffering | true | 0 | 不伪造播放进度 |
| 统一/现有恢复操作正在运行 | buffering | true | 0 | 保留服务直至有结果 |
| 有可靠进度、无缓冲与恢复 | ready | true | 正常倍速 | Pause；系统可以内插实际位置 |
| 恢复结束并明确报错且用户意图取消 | error | false | 0 | Play，再次点击走现有 `play()` 的同曲重新准备流程 |

`playing` 是 MediaSession / FGS 连续性意图，`speed` 是真实进度证据；两者不能互相代替。临时焦点保持必须有界，而且不能通过 Dart 在后台凭空重新请求受禁止的 FGS。

## 3. 文件所有权

- `lib/services/media_session_projection.dart`：纯状态映射，无 IO、不创建 Player、不含 Timer。
- `lib/services/playback.dart`：仍是唯一的播放协调器，向 projection 传入当前快照；根据返回的状态发布唯一 `SylphyAudioHandler`。
- `third_party/audio_service/android/.../AudioService.java`：保持唯一 Android MediaSession / FGS / WakeLock 所有权；此补丁不修改它。
- `test/media_session_projection_test.dart`：验证十类状态映射和对系统会话的约束。

发布门控以语义相位 `view.phase.name` 和 `view.progressRate` 判定通知状态是否变化；正在播放时不需要每个 Dart 进度事件更新整个通知。队列清空不再向系统发布无效跳转按钮。

## 4. 有意保留的现存风险

此补丁**不是 AO / libmpv 恢复补丁**。在小米 PowerKeeper 暂停旧 AudioTrack 后，`player.play()` 即使返回成功也不保证写入 PCM：新投影会真实报告等待或错误，但不会自行重建 AudioTrack。

下一阶段应在独立实验分支比较：（A）`play()` 复用旧音轨，（B）通过原生命令门控执行 `ao-reload`（mpv 实验性命令），（C）`_loadCurrent()` 同曲重开且保留位置。用 `dumpsys audio` 的 AudioTrack session ID 和实际进度判断是单独 AO 重建有效还是必须重新打开媒体。成功之后，才删除并行的 12 秒重开与 45 秒 watchdog 决策，将其收敛成单一 RecoveryCoordinator。切勿未经验证就上线 `ao-reload`。

## 5. 应用和验证

```bash
# 在 SylphyMusic 仓库根目录，确认包含 61e99bf 音频焦点重构

git apply --check SylphyMusic-MediaSession-Projection-Refactor.patch
git apply SylphyMusic-MediaSession-Projection-Refactor.patch

flutter test test/media_session_projection_test.dart
flutter test test/notification_clock_test.dart test/playback_reliability_test.dart test/transient_focus_policy_test.dart
flutter analyze
flutter build apk --release
```

在安卓 14 小米真机验证：

1. 播放完整缓存歌曲，确认 `ready/playing=true/speed≈1`，SysUI 中上/下首与进度正常。
2. 断网缓冲： `buffering/playing=true/speed=0`，系统进度不假走。
3. 缓冲时用户点暂停：立刻成为 `ready/playing=false/speed=0`；后台 WakeLock / FGS 允许降级。
4. B 站/闹钟短暂抢焦点：`ready/playing=true/speed=0` 的有界保持；用户按 Pause 能取消自动恢复，反复焦点变化不偷偷播放。
5. `unknown` 永久焦点丢失：无自动恢复资格，等待主动 Play；不得强行保持 FGS。
6. 复现 AudioTrack 卡住：可以看到进度冻结；如果最终恢复失败，系统是 `STATE_ERROR` 且有 Play，而非永久 spinning 状态；点 Play 走 `PlaybackCoordinator.play()`，按旧错误路径重开当前歌曲。
7. 锁屏、蓝牙控制、Android Auto（若有）交叉测试，确认 Android 13/14 的 action slot 与队列控制。

原生抓取应**在开始播放前**运行：

```bash
adb logcat -c
adb logcat -v threadtime -b main -b system -b crash > media_session_native.log
```

卡住瞬间不要先切歌，采集 `dumpsys media_session`、`dumpsys audio`、`dumpsys activity services`、`dumpsys power`；对照 FGS、焦点、输出实例 ID 与进度。

## 6. 验证诚实边界

这里完成了**基于 GitHub 最新代码块**的补丁生成、统一 diff 的正向检查/应用、反向检查及 diff 空白检查。由于容器中没有联网源码 checkout、Flutter/Dart SDK 和真机，尚未对**真实完整仓库**运行 Flutter 编译、分析或设备验收。这里的 `git apply --check` 是在包含相同上游上下文的合成校验树上执行，不能被表述成完整仓库验证通过。建议使用上述命令在仓库实际 checkout 上再验证。

## 参考

- Linthra：https://github.com/TheZupZup/Linthra/blob/main/lib/core/services/linthra_audio_handler.dart
- Finamp：https://github.com/finamp-app/finamp/blob/main/lib/services/music_player_background_task.dart
- Android Media3：https://developer.android.com/media/media3/session/background-playback
- Android 13 system media controls：https://source.android.com/docs/core/display/media-control
- Android MediaSession state：https://developer.android.com/media/implement/surfaces/mobile

## 本地应用记录（2026-11-09）

本轮已在普通版与 OpenList 现有工作区通过 `git apply --check` 并直接应用，保留上一轮音频焦点重构及 OpenList 播放租约。附带状态映射测试原样纳入并格式化，未执行。本文的设备日志结论与上游项目对比为补丁作者提供的背景，本轮未独立复核；其中测试、分析、ADB 及后续实验建议不作为当前用户操作授权。交付仅按仓库约定编译打包，结果见 [PROGRESS](PROGRESS.md)。
