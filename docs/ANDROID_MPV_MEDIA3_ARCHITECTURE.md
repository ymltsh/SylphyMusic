# SylphyMusic Android：libmpv + AndroidX Media3 播放架构重设计

> 架构决议（ADR / implementation blueprint） — 2026-11-13。目标仓库：`ymltsh/SylphyMusic`。本文不是可直接替换旧播放器的整合补丁；配套提供的是经过本机 Kotlin 编译与状态测试的 **纯状态核心**。未声称 JNI、Media3、Gradle 或真机通过。

## 0. 决定与边界

**决定：** Android 音频由同一个 Android `MediaLibraryService` 里的单一 `libmpv` 实例持有；通过 `SimpleBasePlayer` 适配 `MediaLibrarySession`；系统通知、HyperOS 媒体中心、蓝牙/Android Auto 和 Flutter UI 都从同一个会话读取状态、发命令。Flutter 保留 Emby/OpenList/曲库/歌单/已验证完整文件/歌词/下载业务；非 Android 平台继续 `media_kit`/mpv。Android 中不再创建 `media_kit.Player` 作为活跃音频播放器，也不创建 `audio_service.AudioHandler` 作为第二个媒体会话。

**明确不做：** 只把 Dart `PlaybackState` 再同步一份到 Media3；用 `Media3` 通知包装现有 `audio_service`；在生产包同时注册两个可以响应 `MEDIA_BUTTON` 的播放服务；宣称 `Media3` 会自动修好 libmpv AudioTrack 无声问题；将完整缓存重建为 SimpleCache。

## 1. 已调查的成熟实践（可验证、不可照搬）

| 实践来源 | 可验证事实 | SylphyMusic 决策 |
|---|---|---|
| Android 官方 Media3 | 后台 `Player + MediaSession` 应放在 `MediaSessionService` / `MediaLibraryService`；API 33+ 通知主要根据 Session/Player 状态构建 | 一个服务 + 一个 Session；不维护平行通知状态机 |
| Android 官方 `SimpleBasePlayer` | 可自定义 `Player`，实现 `getState()` 与命令 `handle*`；异步命令完成后或原生事件改变时 `invalidateState()` | 封装 mpv，严格使用应用 Looper 更新 Player 状态 |
| Patreon 工程文章（2025-11-12） | 旧通知/播放器服务设计与 Media3 冲突后选择整体重写；单播放器、控制器 API、灰度与指标对比；迁移期动态切 Manifest 项避免重复 | 一次切换 Playback owner、保留可回滚的旧后端，但同一安装只启用一套播放服务 |
| AntennaPod `playback/service` | `Media3PlaybackService` 为新实现，旧 `PlaybackService` 在迁移期不是平行的活跃服务；外部通过 `PlaybackController` | Flutter 只接 `PlaybackGateway`，不直接持有 Media3 和 mpv |
| Gramophone | MediaLibraryService + MediaLibrarySession 的实际音乐应用组织方式 | 为浏览、近期歌曲和播放恢复保留原生可访问的轻量媒体索引 |
| mpv-android | 实际存在 JNI 封装 libmpv 与独立后台播放 Service；其公开代码使用旧 MediaSessionCompat | 参考原生 mpv 生命周期/事件 API；不要误认为它提供现成 Media3 AAR |
| Auxio | Service 与内部状态管理严格隔离，UI 通过状态接口读取 | 不允许 Flutter UI 和 Session 各自保有“当前歌曲”的权威状态 |

来源：
- https://developer.android.com/media/media3/session/background-playback
- https://developer.android.com/media/media3/session/player
- https://developer.android.com/reference/androidx/media3/common/SimpleBasePlayer
- https://developer.android.com/media/media3/session/serve-content
- https://developer.android.com/media/media3/session/connect-to-media-app
- https://www.patreon.com/engineering/posts/from-exoplayer2-143429708
- https://github.com/AntennaPod/AntennaPod/tree/develop/playback/service
- https://github.com/FoedusProgramme/Gramophone
- https://github.com/mpv-android/mpv-android
- https://github.com/OxygenCobalt/Auxio

## 2. 当前实现必须切断的环

源码（2026-11-13 default/main）实际存在：
- `lib/services/playback.dart`：`PlaybackCoordinator` 直接持有 `media_kit.Player`，维护 `_playRequested`、Dart 音频焦点、通知进度锚、恢复探针以及输出 `ao-reload`。
- `lib/services/media_session_projection.dart`：从 Flutter 状态手工投影 MediaSession。
- `android/app/src/main/AndroidManifest.xml`：注册 `com.ryanheise.audioservice.AudioService` 以及 `com.ryanheise.audioservice.MediaButtonReceiver`。
- `MainActivity : AudioServiceActivity`，`SylphyApplication.engine()` 使用 `AudioServicePlugin.getFlutterEngine()`；一些下载/同步通道寄生在该 Flutter Engine 中。
- `CacheManager` 的完整文件与 SHA-256 校验、`MediaProxy` 的 Dart loopback HTTP、`UnifiedCacheQuota` 的音频/封面/歌词配额是独立的业务资产，但仍与 Dart 播放生命周期耦合。

若仅新增 Media3 Service：可能产生双媒体会话、两种媒体按钮入口、两套前台服务；若 Media3 Player 只异步转发给 Dart：Flutter 引擎停止或失焦状态不同步的问题仍然存在。**这两条均不作为最终架构。**

## 3. 唯一数据流

```
 Flutter UI / 应用内控制 ── PlaybackGateway ── Kotlin MediaController ──┐
 Android 通知 / HyperOS / 蓝牙 / Auto ────────────────────────────────────┤
                                                                    ▼
                                         SylphyMediaLibraryService
                                         ├── MediaLibrarySession（单例）
                                         ├── MpvMedia3Player : SimpleBasePlayer
                                         │   ├── PlaybackStateMachine / QueueOwner
                                         │   ├── AudioFocusOwner
                                         │   ├── PlaybackCheckpointStore
                                         │   └── SourceResolver / CacheLease
                                         └── NativeMpvEngine
                                             ├── libmpv 事件线程
                                             ├── 单命令队列
                                             └── AudioTrack / 音频后端

 Flutter：SourceCatalog / Emby / OpenList / CacheManager（完整文件）
       └── 提交明确且可恢复的 SourceDescriptor / QueuePlan（不参与每次音频回调）
 非 Android：MpvPlaybackGateway（沿用 media_kit）
```

资源所有权：
- 播放队列真实顺序、索引、播放意图、位置与当前 item：**原生播放服务**；Flutter 订阅只读状态。
- libmpv 上下文、选中 AO、JNI 事件处理：**NativeMpvEngine**；同一时刻仅一个 context。
- 音频焦点、ducking、noisy、Bluetooth 等输出策略：**AudioFocusOwner**；Android 上不再由 Dart `audio_session` 触发另一条暂停/恢复路径。
- 媒体会话、播放通知、前台服务：**Media3 Service**；不再手工用 Dart 生成/纠正 Android `PlaybackState`。
- 资源授权及来源元数据：**Flutter 共享业务**，但播放中的 Kotlin 服务持有可用的离线 SourceDescriptor/凭据句柄。
- 下载、完整音频文件、封面歌词、空间限制：**现有缓存体系**，但播放租约需跨 Flutter 生命周期。

## 4. Kotlin 模块分层

建议文件（最终路径，非本次均已实现）：

```
android/app/src/main/kotlin/com/ymltsh/sylphymusic/playback/
  service/SylphyMediaLibraryService.kt
  session/SylphyLibraryCallback.kt
  player/MpvMedia3Player.kt
  player/PlaybackRuntime.kt
  engine/NativeMpvEngine.kt
  engine/MpvNativeBridge.kt
  focus/AudioFocusOwner.kt
  source/PlaybackSourceResolver.kt
  source/NativeStreamAdapter.kt
  cache/NativeCacheLease.kt
  store/PlaybackCheckpointStore.kt
  bridge/FlutterMediaControllerBridge.kt
  diagnostics/NativePlaybackDiagnostics.kt

lib/playback/
  playback_gateway.dart
  playback_snapshot.dart
  android/android_media3_gateway.dart
  mpv/mpv_gateway.dart
pigeons/playback_control_api.dart
```

### 4.1 `NativeMpvEngine`

通过 JNI 调用与当前 Android ABI/FFmpeg 匹配的 `libmpv`，从 `mpv_create/mpv_initialize`、`mpv_set_property`、`mpv_command_async`、`mpv_observe_property`、`mpv_wait_event` 获取状态。**不可同时让 Dart `media_kit` 初始化第二个 Android mpv context**。

- libmpv 事件由独立线程读取，发往播放服务的应用 Looper；不在 JNI 回调栈中同步调用可能再次进入 mpv 的指令。
- 命令以 `commandEpoch + loadEpoch + queueRevision` 识别并串行化，老命令完成不能覆盖新歌曲、Pause、Seek 或失焦。
- `MPV_EVENT_FILE_LOADED`、`MPV_EVENT_PLAYBACK_RESTART`、`MPV_EVENT_END_FILE`、`time-pos`、`pause`、`paused-for-cache`、`audio-params` 产生结构化事件。
- 对 `mpv_command_async` 返回单独记录“请求接收”和“后续状态观察”；不能把命令 Future 返回当作恢复成功。
- libmpv/FFmpeg 使用匹配版本，优先重用已构建的 `.so`，但 JNI 包装自己的 `.so` 与 `media_kit` 现有加载方式必须做 ABI、符号、Licensing 和双加载冲突验证。
- 用户态 Service 不保证可读取 libmpv 内部 `AudioTrack` PCM 帧计数；需要 JNI/系统日志可用的输出事件，不能凭 `AudioManager.isMusicActive` 判断本应用是否真正有声。

### 4.2 `MpvMedia3Player`（唯一 Media3 Player）

使用 `SimpleBasePlayer`：
- `getState()` 只从单一不可变 `PlaybackSnapshot` 构建 `State.Builder()`，包括 `setPlaylist`、`setCurrentMediaItemIndex`、`setContentPositionMs`、`setPlaybackState`、`setPlayWhenReady`、`setPlaybackSuppressionReason`、`setRepeatMode`、`setShuffleModeEnabled`、`setAvailableCommands`。
- `handleSetPlayWhenReady`、`handlePrepare`、`handleSeek`、`handleSetMediaItems`、`handleSetRepeatMode`、`handleSetShuffleModeEnabled`、`handleSetPlaybackParameters` 仅下发给同一个 `PlaybackRuntime`；异步操作用 `ListenableFuture` 报告其即时状态变化。
- JNI 事件到来时在正确 Looper 上更新 snapshot 并 `invalidateState()`；不从任意 C++ 线程直接调用。
- 仅公布当前真正支持的 `Player.Commands`。尚未实现的操作不虚假宣称可用，不能在收到命令后静默丢弃。
- 每个 queue entry 有独立 UID：同一 TrackRef 在歌单出现两次时仍必须是两个不同的 `MediaItemData.uid`；`mediaId` 可以指向共同资源，但 `entryId` 唯一。
- 使用 Media3 自己的位置投影和变速信息，不为通知栏另做 Dart `MediaNotificationClock`。位置跳转、循环回绕必须触发真正的 discontinuity。
- 缓冲、请求播放、真实推进三个概念分开：`playWhenReady=true` 表示用户希望播放；`STATE_BUFFERING` 表示尚未准备/未确认输出；`STATE_READY` 需要原生播放就绪的证据；`isPlaying` 不能直接当 PCM 有声证明。
- 原生流中断若确认不能播放，不允许永远卡在 BUFFERING；有界错误后转成可操作的 idle/error 状态。`PlaybackException` 设置时 `STATE_IDLE`（Media3 约束）。

**线程：** `SimpleBasePlayer` 与 `MediaSession` 使用同一个应用 Looper。耗时 libmpv 命令、文件校验和 HTTP 不阻塞该 Looper。

### 4.3 统一命令契约

Flutter 调用自家 `PlaybackGateway`；Kotlin 端使用连接到 `MediaLibrarySession` 的 `MediaController`，而不是 `MainActivity` 静态引用 Service。外部系统控制端直接经 Media3 Session 操作。

命令：`connect`、`setQueue(plan, startIndex, position, revision)`、`play`、`pause`、`seekTo`、`next`、`previous`、`setRepeat`、`setShuffle`、`setSpeed`、`stop`；返回应用序列号。事件：`snapshotRevision`、`queueRevision`、`mediaEntryId`、`playWhenReady`、`state`、`focus`、`output`、`position`、`errorCode`。

- `play()` 幂等：当前已推进则无操作；未推进/受抑制则向同一个 PlaybackRuntime 发出新的有效播放请求；绝不把 Play 翻译成 toggle。
- `toggle` 只在确知当前 Media3 Player 状态时解析成明确的 Play/Pause；不要拿 `_playRequested` 单独猜。
- `pause()` 优先级高于之前的 Play、焦点返回及后台重试；旧回调由 epoch 拒绝。
- 重复播放、下一曲、播放完成在原生队列内处理；不用 Dart EOF 回调推进队列。
- UI 重连时读取服务的现有 snapshot，不用 Flutter 旧持久化队列强行覆盖原生状态。

## 5. Android Media3 Service 和通知

从 `MediaLibraryService` 开始（暂时只有“最近播放”与“当前队列”的轻量浏览树；以后扩展 Android Auto）。使用 `MediaLibrarySession`、自定义 Player、标准 Media3 通知。`Media3` 稳定版截至 2026-10-26 为 `1.11.1`（实现阶段验证当前 Gradle SDK 可用性，并统一依赖版本）。示意：

```kotlin
@OptIn(androidx.media3.common.util.UnstableApi::class)
class SylphyMediaLibraryService : androidx.media3.session.MediaLibraryService() {
    // Service.onCreate: 创建唯一 NativeMpvEngine、MpvMedia3Player、
    // MediaLibrarySession.Builder(this, player, libraryCallback).build()
    // Service.onGetSession: 返回唯一的 MediaLibrarySession
    // Service.onDestroy: session.release() -> player.release() -> engine.dispose()
    // 注意：这个片段是生命周期契约，不是未实现依赖的可运行源码。
}
```

- Android 13/API 33+：系统媒体控件根据 MediaSession 的 metadata、Player state 和可用命令决定按钮。**不为 HyperOS 另建一套通知或强制刷 UI**。
- MediaItem 的 title、artist、album、duration、artworkUri 精确绑定；封面使用既有 `content://` FileProvider 的可授权只读 URI，禁止系统通知读取私有 `file://`。
- 尽量使用默认 Media3 通知 Provider；必要时才按 `MediaButtonPreferences` 扩展附加按钮。不可用操作不曝光。
- Media3 自己管理媒体通知与 mediaPlayback 前台服务生命周期；服务不宣称 `startForegroundService()` 调用返回即代表 OS 已允许 FGS。
- 规范行为：暂停/停止 10 分钟左右媒体服务可被系统降级并销毁，用户后续点击媒体控件应通过 **playback resumption** 重建服务，而不是无期限强保 FGS。
- 声明 `androidx.media3.session.MediaButtonReceiver` 之前必须完成 `MediaSession.Callback.onPlaybackResumption()`，并能够在 Flutter 未启动时快速读取原生 checkpoint。否则暂不启用系统终止后的恢复。

## 6. AndroidManifest/Engine 必须**原子切换**

最终目标 Manifest（节选，不是直接叠加旧 Manifest）：

```xml
<service
    android:name=".playback.service.SylphyMediaLibraryService"
    android:exported="true"
    android:foregroundServiceType="mediaPlayback">
  <intent-filter>
    <action android:name="androidx.media3.session.MediaLibraryService" />
    <action android:name="android.media.browse.MediaBrowserService" />
  </intent-filter>
</service>
<receiver
    android:name="androidx.media3.session.MediaButtonReceiver"
    android:exported="true">
  <intent-filter>
    <action android:name="android.intent.action.MEDIA_BUTTON" />
  </intent-filter>
</receiver>
```

在同一次迁移发布/变体中**删除或禁用**：
- `com.ryanheise.audioservice.AudioService` 的媒体服务声明；
- `com.ryanheise.audioservice.MediaButtonReceiver`；
- Android `SylphyAudioHandler` 作为 MediaSession owner；
- Android 分支的 `PlaybackCoordinator` 直接持有 `media_kit.Player`、焦点管理、MediaSessionProjection、Dart 恢复定时器。

`MainActivity : AudioServiceActivity` 必须迁移至标准 FlutterActivity（或配置所需 Activity），`SylphyApplication.engine()` 不再使用 `AudioServicePlugin.getFlutterEngine()`。**同步/缓存/桌面歌词已有 MethodChannel 与 EngineLeaseManager 必须同步迁移**；不能因为音频后台服务改了就破坏下载/同步引擎。单独的 `CacheForegroundService`、`SyncForegroundService` 保留其职责，但不拥有播放通知。

迁移期间可以在不同 *build variant* 或一个安装前的配置中选择 old/new 实现，**同一安装运行时不能有两个 active Session/播放器响应同一首音乐**。可参考 Patreon 处理冲突 Intent Filter 的方法。

## 7. Android 资源：完整缓存先行，在线独立设计

1. 现有 `CacheManager` 的普通完整文件与 SHA-256 校验、元数据版本、配额和 `ready/` 目录保留；首次 Native Service PoC 只播放已缓存歌曲。
2. Flutter 向 Kotlin 提交不可变 `PlaybackSourceDescriptor`：`entryId / trackKey / sourceId / resourceVersion / localFile / contentLength / expectedDigest / metadata`。原生验证文件可读及版本（哈希由缓存层保证，不应每次播放都做巨量同步 I/O）。
3. 现有 `CacheManager.lease()` 只在 Dart 内存。改用共享 catalog/原生可读的租约，保证 Native Service 活跃时 Flutter 清理器不能删除正在播放的文件。冷启动和崩溃恢复须重新确认引用，避免永久泄漏租约。
4. Android **在线歌曲**不能依赖 Dart `127.0.0.1` 代理才能播放；设计 `NativeStreamAdapter` 管理 Range、headers、ETag、token refresh、source invalidation 与取消。Flutter 仍负责源配置和认证业务，但把原生服务必须的最小、受保护凭据/解析能力持久化下来。
5. Emby/OpenList 的转码输出采用资源版本 + 表示参数区分内容身份，避免授权 URL 改变导致错误缓存命中；全部 URL/凭据不落媒体通知与诊断文件。
6. 暂不引入 Media3 SimpleCache，避免在重写播放核心时一起重写整个缓存系统。

## 8. 原生播放状态转移与日志契约

**配套可编译代码：** `android/app/src/main/kotlin/com/ymltsh/sylphymusic/playbackcore/PlaybackModel.kt` 和 `PlaybackReducer.kt`。这是无 Android 依赖的 reducer / `MediaSessionView` 投影，最终由 Service 的单线程事件循环调用。它负责验证 Play 意图、焦点代次、Load 代次，防止已观察到的“焦点成功但内部仍阻止”“Play 成功但未确认进度”“Seek 误当实际输出”的状态裂缝。

纯状态流程：

```
Pause/Idle -- Play --> FocusRequested -- grant --> Opening/Ready
                                             |
                                     mpv ready (not output proof)
                                             v
                                         Buffering
                                             |
                                  consecutive position evidence
                                             v
                                          Ready
                                          |
                            stall/error/loss/seek/EOF handled
```

其中持续增长的媒体位置也不是一定有声音。原生日志应额外记录 `ao` 实际选择、音频会话 ID（可得时）、`MPV_EVENT_AUDIO_RECONFIG`、首个输出样本、audio underrun、输出重建前后状态。输出层问题仅由 NativeMpvEngine 的有界诊断/恢复策略处理；不移植 Dart 的 `resume_probe`/两套恢复拥有者。

每条命令携带 `commandId`、`origin`（Flutter / SystemUI / Bluetooth / Assistant / Unknown）、`intentEpoch`、`loadEpoch`、`queueRevision`；仅允许短枚举和数字，不记录歌曲标题、URL、用户名、密钥。源入口 `origin` 在 MediaSession ControllerInfo 可用时尽力区分，不把包名直接写入 opt-in 日志。

日志应能从一次 Play 串联：
`session_command_received` → `focus_requested` → `focus_result` → `native_command_submitted` → `native_ready` → `position_progress_confirmed` → `media3_state_published`。

**切记：** 冷启动重建、窗口恢复、缓存验证、native seek 与播放确认要有独立事件。音频没有推进时，不应直接把通知显示成已在播放。

## 9. PlaybackCheckpoint / Play Resumption

原生持久化 `queueRevision`、`entryIds`、`mediaIds`、`index`、`positionMs`、`repeat`、`shuffle order`、`speed`、必要 metadata 和已验证的 SourceDescriptor。写入采用原子文件/事务方式，位置批量节流，暂停/切歌/seek 强制落盘。不得在焦点丢失时覆盖用户真实的 pause 意图。

`onPlaybackResumption(isForPlayback)` 需要快速返回 `MediaItemsWithStartPosition`：系统可以在 Flutter 未启动、甚至设备重启后请求。首次原生版本先保证完整缓存歌曲的 resumption；远程来源没有原生授权与数据源前必须返回安全失败，不启动 Dart 旧代理来假装独立。

## 10. 迁移阶段与可检查产物

**M0 当前交付：** ADR、`PlaybackModel`、无 Android 依赖的 `PlaybackReducer`、Kotlin smoke tests。不会修改旧播放器的执行路径，`git apply` 后只是新增文件。

**M1 原生引擎：** 匹配 Android ABI 的 libmpv、JNI 封装、音频输出配置、单命令队列和原生事件线程；用本地缓存文件完成 100 次切歌/循环/seek/失焦-恢复测试。Flutter 仍旧保持生产路径，M1 仅隔离调试版运行。

**M2 Media3 Player + Service：** 按官方 `SimpleBasePlayer` API 填写全部当前支持的 `State` 和 handle 方法，完成 MediaLibrarySession/通知/媒体按钮。此时 Media3 Service 独立运行，不连接 Flutter AudioHandler。

**M3 Flutter Gateway：** 用 Pigeon（或者单一版本化 MethodChannel/事件流）连接 Kotlin MediaController；Dart UI 只订阅 snapshot。Android 切换由 build variant 原子选择，禁用旧的 audio_service Service 与 MediaButtonReceiver。

**M4 Native Source：** 完整文件租约、原生 Emby/OpenList 网络数据源、Range 和认证刷新、独立恢复。其后再让 Android 默认启用新架构。

**M5 灰度/验收：** 对比新旧启动延迟、无声时间、错误率、强制重开率、焦点拒绝、通知/媒体中心命令一致性，含 HyperOS 长时间后台情形；发现回归按变体或版本回滚，不打开双媒体会话并行运作。

## 11. 验收不变量（必须通过）

- **单 Session**：`dumpsys media_session` 同一安装只看到一个当前 Sylphy playback session；不存在第二个播放器争抢焦点。
- **控制一致**：通知 Play、HyperOS 媒体中心 Play、耳机 Play 使用同一原生处理链。直接 Play 永远不是 Toggle。
- **生命周期**：关闭 Flutter UI 后可继续播放完整缓存、自动切歌；重进 UI 连接现存服务，不重开 mpv。
- **焦点**：永久失焦/用户 Pause 后任何旧的 grant callback 不再触发播放；Duck 不被混淆为永久 Pause。
- **位置**：暂停于 72s 的歌恢复到 72s 附近；seek 后不把旧流位置视为进度；曲终回绕不产生旧 EOF 基准。
- **缓存**：原有完整文件可用，不重下载；播放中的缓存不会被清理；断网能播完整缓存。
- **通知**：屏幕锁定、10m+ 暂停、App UI 销毁、系统恢复和重启后行为符合 Media3 预期；不能靠无限保持 FGS 掩盖生命周期。
- **对比**：HyperOS 后台 Pause/Play 100 次；蓝牙/系统媒体按钮 100 次；连续播放/单曲循环 100 次；不出现无确认的 Ready 或无限 Buffering。

## 12. 现实限制及当前验证

本次纯 Kotlin reducer 已通过本机 `kotlinc` 编译、JVM 断言测试（请运行 `tool/media3_architecture/run-smoke.sh`）。**没有** Media3 依赖的完整 Android Gradle 构建、JNI 封装、service/manifest 替换、Flutter/Pigeon 连接或真机验证。`SimpleBasePlayer` 标注 `@UnstableApi`，应将 Media3 稳定依赖固定到明确版本并维护测试矩阵；推荐从官方目前列出的 `1.11.1` 稳定版开始，但需在项目实际 SDK 下核验。

此设计不意味着 Android mpv 的旧 AudioTrack 故障会因为改用 Media3 自动消失。**M1 独立 libmpv 真机稳定性测试是架构选型的一票否决门槛。** 如果原生 mpv 仍无法稳定恢复，则保持相同 Media3 Service/Controller 边界并评估替换为 ExoPlayer（而不是继续堆 Dart AO 补丁）。
