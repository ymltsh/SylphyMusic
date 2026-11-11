# 基于 2026-11-11 诊断记录的修复依据

## 案例一：09:55 UTC 的回绕假停滞

日志显示 Play 附近 `position_ms=4089`，12 秒后恢复检查中的播放器位置约 16232ms，第二次约 28442ms，说明媒体位置实际推进，却仍被恢复机制判为停滞。源码中 `_finished()` 的 `RepeatKind.one` 分支调用 `native.seek(Duration.zero); native.play()`，没经过公有 `seek()`，因而没有重置 `_watchdogPositionMs`；而 `_watchdogPositionMs` 只在 `nextMs > previousProgressMs + 400` 时更新，如果前一轮 EOF 基准较高，重播从 0 出发就无法满足条件。修复针对这种状态基准的失配。

## 案例二：10:22 UTC 的真实疑似 AO 故障

用户后台通知 Play 后，12 秒的检查在 `os_fgs=yes`、WakeLock `true`、焦点已授权、`music_active=false`、`session_moving=false` 条件下触发 `ao-reload`；在该命令后约 91ms 出现 `progress_resumed`。这更符合旧输出链没有恢复的假设，但缺少 AudioTrack PCM 写入与消费计数，不能断言 Android HAL 或 PowerKeeper 是根因。因此该补丁保持当前有界的 12 秒 AO 恢复策略，使用前置 2s / 3s 两个零副作用诊断检查点采集正常/异常对照。

## 曲尾 `player_error` 与完成事件竞争

另份同日日志出现 `player_error → recovery_started → reconnect_attempt → track_completed`，证明原有 `_failed` 会在 EOF 完成之前启动。前置的 02 补丁将近曲尾错误延迟 750ms；完成事件来时取消并丢弃，未完成时恢复原错误处理。此补丁不改动通用错误分类、不关闭超时保护。

## 正确性约束

- 曲目、播放意图、加载代次、导航代次必须在循环原生命令和早期探针时验证。
- 不在原生命令锁内调用公有 `seek()`，避免锁重入；沿用 `_runNativeCommand`。
- `loop_old_position_ignored` 只在循环 seek 后的短暂窗口有效，且不会触发网络请求、缓存修改或切歌。
- 2s/3s 仅诊断，不会主动调用 `ao-reload`，不会改变用户暂停或失焦状态。
- 本地缓存优先与完整 READY 校验由已有 `_loadCurrent()` 保持；本轮不修改缓存索引、租约或代理票据。

**检验边界：** 只有 Git 上下文应用检查（合成基线），未编译，未在 Android 设备验证；必须保留原生故障调查的不确定性。
