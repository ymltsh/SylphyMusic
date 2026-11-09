# SylphyMusic 后台媒体播放/输出生命周期一体化重构

**目标仓库** `ymltsh/SylphyMusic`  
**精确代码基线** `61e99bf783965ebd64456818b32605a300a67602`（2026-11-09 最新 `main`，已包含此前焦点重构）  
**补丁** `SylphyMusic-Integrated-Playback-Lifecycle-Refactor.patch`

## 1. 为什么不是单独的“通知补丁”

小米 Android 14 的日志显示，应用一度收到原生 Play 成功回调，但旧 AudioTrack 没有持续输出；用户切歌以后旧 AudioTrack 被销毁，新 AudioTrack 创建，播放恢复。另一份原生日志证明系统曾记录 `Service.startForeground() not allowed due to bg restriction`，但应用立刻打印 `fgs_promoted`；PowerKeeper 随后看到 `mHasForegroundServices=false` 并暂停长时间无数据的音轨。SystemUI 还曾因 `EACCES` 无法读取应用私有封面文件。

这分别对应三种不同的资源所有权，**不能只靠重绘通知修复**：

- **媒体会话**：正确表达播放意图、真实进度、缓冲、错误及媒体控制。
- **Android AudioService**：唯一请求、观测和释放 FGS / WakeLock 的原生所有者，任何内部布尔值都不等于 OS 授权。
- **libmpv Player**：唯一音轨/解码/输出所有者。两个检测器只触发同一个有界恢复执行器，不允许额外 Player 或自动跳歌。

## 2. 参考成熟项目及实际取舍

| 参考 | 实际做法 | 在本次补丁中采用 |
|---|---|---|
| Linthra `LinthraAudioHandler` / #751 | 用户暂停压过底层 buffering；短暂焦点失去有界保持 FGS | `MediaSessionProjection`，继续沿用已合并的 `TransientFocusPolicy` |
| Auxio `AuxioService` / `MediaSessionHolder` | Service 统一切换前台，MediaSession 只发布状态 | 保持单一 AudioService，分开「前台请求」「OS 观察」日志；不复制 Auxio 未验证的本地 success 标志 |
| Finamp #1643、audio_service #996 | 暂时失焦时过早降级可触发 Android 后台重启禁令 | 保留有界的焦点保留策略，不把全部用户暂停永久保持前台 |
| Media3 AudioSink / mpv | 输出启动、实际推进、输出重新建立是不同事件 | mpv `ao-reload` 一次，**必须验证真实进度**，失败后同曲重新打开一次 |
| Linthra MediaArtworkFileProvider | SystemUI 在自己的进程加载 `content://` 封面，授予精确只读 URI | 缓存专用的 FileProvider，默认 `exported=false`、只读、限定 `cache-path` |

## 3. 当前实现修改

### A. 唯一恢复执行器

`lib/services/playback.dart` 中原有两条恢复路径：

- 12 秒本地恢复检测 `_verifyResumeProgress` → `_reopenUnconfirmedResume`。
- 45 秒 watchdog `_checkForStall` → `_recoverStall` → `_failed`（旧方法可将完整缓存按远程来源处理并跳歌）。

本补丁删除 `_recoverStall` 独立执行路径。**两个检测触发器只允许进入 `_reopenUnconfirmedResume`**。由 `_stalledRecoveryRunning` / `_handlingFailure`、当前歌曲、`_loadGeneration`、`_playIntentGeneration`、`_navigationEpoch` 提供独占和过期回调屏蔽。

唯一恢复顺序：

1. 系统焦点允许，歌曲、导航和播放意图仍为当前，且确实没有位置推进。
2. Android 本地歌曲 / 完整缓存：调用一次 `NativePlayer.command(['ao-reload'])`，通过现有 `NativeCommandGate` 串行化。**AO 命令返回不代表音频已恢复**，再次核对实际位置推进。
3. 仍不推进或命令不支持：保存当前位置，`_loadCurrent(autoplay: true, manual: true)` **只重开同一首**，不跳歌；网络代理来源先检查 loopback 代理健康（必要时尝试重启），再采取此步骤；完整缓存/本地文件绝不探测代理，也不把网络失败误判为音轨失败。
4. 同曲重开后仍不推进：主动暂停，公布可操作的错误，等待用户手动 Play；不无限循环。

策略提取为 `audio_output_recovery_policy.dart`，新增 8 项纯状态测试；原有 `playback_reliability_test.dart` / 通知测试继续保留。

**实验性与限制：** `ao-reload` 是 mpv 实验性内部命令，不能假设所有打包 libmpv 都支持。单次 AO 重载必须与 Android 的 AudioTrack Session ID 和 `progress_resumed` 对照；若无效，走同曲重开。恢复检测定时器仍可能受到 Dart isolate 冻结而延迟，此补丁**不解决系统冻结问题**，只是删除重复恢复所有权。

### B. 真实区分前台请求和系统观测

原生 `AudioService.java` 的 `fgs_promoted` 改为 `fgs_request_submitted`：Java API 未抛异常只能说明调用返回，不能证明系统允许。收到用户 Play 时的 `fgs_reaffirmed` 同样改为 `fgs_reaffirm_requested`。

增加异步、带 epoch 的本应用服务状态查询：

- `fgs_os_confirmed`：观察到当前本应用 `AudioService` 是 FGS。
- `fgs_os_not_foreground`：观察到服务存在但 `foreground=false`，撤销逻辑租约并释放对应 WakeLock；下一个合格的用户动作可重试。
- `fgs_os_status_unknown`：无法观察，绝不伪报 OS 成功。

`ForegroundResumeState` 新增 `osConfirmed`，与逻辑 `isForeground()`（表示已提交或仍维持请求）分离。跟踪的旧请求由 epoch 屏蔽，防止降级后的异步检查修改新会话。

**API 限制：** `ActivityManager.getRunningServices()` 从 API 26 开始废弃；Android 官方仍称它可以返回**调用方自己的服务**，但仅适合诊断与服务管理 UI。此查询是针对小米故障的**尽力观测**，不能作为跨所有 ROM 的稳定平台保证。最终确认必须配合 `dumpsys activity services`，原生查询结果为 `unknown` 时保持不确定性。不得尝试通过重复 startForegroundService 绕过 Android 12+ 背景限制。

### C. MediaSession 状态投影与通知

合并此前尚未进入 `main` 的 `MediaSessionProjection` 方案：

- 用户真正暂停：`ready / playing=false / speed=0`，哪怕旧解码器仍报 buffering。
- 暂时失焦（有界资格）：`ready / playing=true / speed=0`，保留已有 FGS。
- 正常准备、恢复：`buffering / playing=true / speed=0`。
- 真正推进：`ready / playing=true / speed=真实倍速`。
- 明确最终错误：`error / playing=false / speed=0`，展示可再次点击的 Play。
- 不使用额外自定义 RemoteViews，也不创建第二个 MediaSession。显式声明紧凑通知的三个标准按钮。

`androidStopForegroundOnPause: true`、`androidNotificationOngoing: false`；用户暂停释放资源，临时中断仍遵循已有的有界保持规则。

### D. 通知封面可跨进程读取

原 `File.uri` 指向私有应用目录，SystemUI 跨进程不可读。新增：

- `MediaArtworkFileProvider.kt`，只允许读取，并只在访问具体 `content://` URI 时将其精确授权给系统媒体宿主（可用包不存在时忽略）。
- `res/xml/media_artwork_paths.xml`，仅导出 `cacheDir/media_session_covers/`，不暴露原始音频、数据库或应用其他文件。
- Flutter 拿到既有封面后复制到专用缓存目录，URI 不包含服务器账号、令牌或真实私有路径。
- 位图 Downscale 至 256×256，降低 Binder 传输压力。

缓存属于 Android 缓存空间，可能被 OS 清除；不会影响正常解码或播放。`FileProvider` 读权限是独立的显示问题，不将其与 AudioTrack 卡住混为一谈。

## 4. 精确应用

**这份文件已经包含上一份 MediaSessionProjection 补丁的内容**。不要单独再应用 `SylphyMusic-MediaSession-Projection-Refactor.patch`，也不要重复应用旧 V1/V2/V3；焦点重构已在指定 `main` 中。

```bash
git checkout 61e99bf783965ebd64456818b32605a300a67602
git switch -c fix/media-service-output-lifecycle
git apply --check SylphyMusic-Integrated-Playback-Lifecycle-Refactor.patch
git apply SylphyMusic-Integrated-Playback-Lifecycle-Refactor.patch
flutter format lib/services/playback.dart lib/services/media_session_projection.dart lib/services/audio_output_recovery_policy.dart test/media_session_projection_test.dart test/audio_output_recovery_policy_test.dart
flutter test test/media_session_projection_test.dart test/audio_output_recovery_policy_test.dart test/transient_focus_policy_test.dart test/playback_reliability_test.dart test/notification_clock_test.dart
flutter analyze
flutter build apk --release
```

独立 JVM 状态测试（不依赖 Android SDK）：

```bash
mkdir -p /tmp/sylphy-jvm-classes
javac -d /tmp/sylphy-jvm-classes \
  third_party/audio_service/android/src/main/java/com/ryanheise/audioservice/ForegroundResumeState.java \
  tool/ForegroundResumeObservationTest.java
java -cp /tmp/sylphy-jvm-classes ForegroundResumeObservationTest
```

还原补丁：`git apply -R SylphyMusic-Integrated-Playback-Lifecycle-Refactor.patch`（需当前文件未被后续修改）。

## 5. 小米 Android 14 真实性验收

**A 组（关键）：** 同一首完整缓存歌曲，后台暂停 3–20 分钟后通过通知 Play，卡住时不手动切歌。检查是否出现 `audio_output_reload_requested`、`resume_same_track_reopen`、`progress_resumed`，观察 AudioTrack session ID 是否真正改变，是否有 `PowerKeeper.Audio pauseAudioTracks`。

**B 组：** 其他应用短暂抢占焦点、恢复。检查有界 FGS 保持、用户暂停后 Play 按钮、不会在后台非法重复提升 FGS。

**C 组：** 在系统已明确限制 FGS 时运行。检查 `fgs_request_submitted → fgs_os_not_foreground` 或 `unknown` 与 `dumpsys` 结果是否一致；**不允许宣称受到限制的服务已经恢复成功**。

**D 组：** 浏览通知、锁屏和蓝牙歌曲元数据。检查 SystemUI 日志中不再出现封面私有路径 `EACCES`。

原生日志：

```bash
adb logcat -c
adb logcat -v threadtime -b main -b system -b crash > sylphy_native_log.txt
```

在声音卡住时（切歌前）立即抓取 `dumpsys activity services com.ymltsh.sylphymusic`、`dumpsys audio`、`dumpsys media_session`；之后才观察自动同曲修复。请保留同一设备上旧版和新版的 A/B 记录。

## 6. 已执行与未执行

已执行：按最新基线原始源代码片段构造校验树，`git apply --check`、`git apply --whitespace=error`、`git apply -R --check` 均通过；Android `res/xml` 已解析；独立 `ForegroundResumeObservationTest` 已用 `javac` 编译并运行通过。

未执行：**未能获取完整本地 Git 仓库，没有在完整 checkout 上执行 `git apply`；此环境无 Flutter SDK / Android SDK，未执行 Dart 分析、Flutter 单测、APK/AAB 编译或小米真机验证。** 这是一份可审查的工程候选补丁，而非已证明根治的发布版本。

## 7. 参考

- Linthra 媒体会话与封面：<https://github.com/TheZupZup/Linthra/blob/main/lib/core/services/linthra_audio_handler.dart>、<https://github.com/TheZupZup/Linthra/blob/main/android/app/src/main/kotlin/io/github/thezupzup/linthra/MediaArtworkFileProvider.kt>
- Auxio Service / MediaSession / ExoPlayer：<https://github.com/OxygenCobalt/Auxio/tree/dev/app/src/main/java/org/oxycblt/auxio/playback/service>
- Finamp 音频焦点 / FGS 讨论：<https://github.com/finamp-app/finamp/pull/1643>
- Android `getRunningServices` 的废弃和自有服务诊断例外：<https://developer.android.com/reference/android/app/ActivityManager#getRunningServices(int)>
- Android `FileProvider` 精确 URI 授权：<https://developer.android.com/reference/androidx/core/content/FileProvider>
- media_kit `NativePlayer.command`：<https://pub.dev/documentation/media_kit/latest/media_kit/NativePlayer-class.html>

## 本地集成记录（2026-11-10）

本轮保留已应用的 MediaSessionProjection，剔除重复导入、通知配置、状态发布及已存在文件的补丁部分后，在普通版与 OpenList 现有工作区通过增量补丁检查并应用。附带新增 Dart / JVM 策略测试已纳入但未执行。FileProvider authority 使用 `${applicationId}.mediaartwork`，Dart URI 从 PackageInfo 获取实际包名，避免两版本并存冲突；保留 OpenList 播放租约及其他已有工作。

本文中的上游设备证据、测试结果和后续实验建议来自补丁作者，本轮未独立复核，也不作为额外操作授权。当前只进行本地 Release 编译打包，未执行测试、analyze、ADB 或设备验收；实际结果见 [PROGRESS](PROGRESS.md)。AO 重载效果及 ROM 前台观测准确性仍待用户设备确认。
