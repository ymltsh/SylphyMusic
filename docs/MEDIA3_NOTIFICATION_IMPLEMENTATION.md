# Android 媒体通知与原生播放服务

2026-11-13，主工作区实现。设计参考用户提供的 `SylphyMusic-MPV-Media3-Architecture-Foundation.zip`；附件中的路线图与测试建议不作为自动发布或设备操作授权。

## 当前实现

- 单个 `SylphyMediaLibraryService` / `MediaLibrarySession` / `MpvMedia3Player`，固定 Media3 common / session 1.11.1。默认 Media3 通知、前台服务、锁屏与耳机命令都读取同一个 Player。
- JNI 动态加载现有 ABI 对应的 libmpv。所有 context 的创建、命令、观察、停止和销毁共用一个工作线程；兼容项目当前 mpv 0.35 的 loadfile 参数。Media3 应用 Looper 处理不可变状态事件与唯一队列，不进行音频网络传输。
- Flutter 使用 AndroidMedia3Playback 公共接口，经 MediaController 连接同一会话；没有 Android media_kit.Player、AudioHandler、Dart audio_session、旧通知时钟或旧 AO 恢复定时器。非 Android 保持原播放实现。
- 队列条目 UID 与 TrackRef 分离，支持重复歌曲。原生负责自然结束、单曲循环、随机顺序、上一首历史（最多 300 项）、下一首、Seek、倍速与音量。外部浏览仅提供当前队列；选曲只接受已有精确 mediaId，不接受外部 URL / 文件。
- 播放意图、焦点、准备、缓冲、推进和错误独立。等待 Media3 前台通知完成后申请焦点；拒绝、永久失焦、用户暂停或 noisy 都不能被旧回调恢复。临时失焦保留意图最多五分钟。实际推进不代表已证明 PCM 有声。
- 原生采样每 200ms；三秒无推进冻结为缓冲，三十秒无推进停止并报告通用重试错误，不自动跳歌。Seek 和循环重置进度基准；重复 Play 对已推进状态幂等。播放 WakeLock 以 35 秒超时、按活跃状态续期，暂停 / 失败 / 销毁释放。
- 来源授权继续使用现有 MusicAdapter / AuthVault，得到的 URL / headers 仅交给原生内存 Range 适配器；播放字节不再经过 Dart HTTP listener。平台 TLS 校验保持开启，只跟随同 scheme / host / port 的跳转，不向其他源转发凭据。远程显式恢复重新解析授权地址。
- 保留既有 READY 文件、摘要 / 版本检查、完整缓存下载及统一配额。原生租约位于音频缓存的 `native-leases/<pid>/<track hash>/<lease id>`；停止确认 idle 或 context 销毁后释放。缓存清理、过期替换、孤立文件回收和配额淘汰均尊重租约。当前与后两首由原完整缓存管线验证、提交，取消仍保留用户接管的下载。
- 封面复用 ArtworkStore 与只读 content FileProvider。业务引擎由 SylphyApplication 缓存，缓存 / 同步与桌面歌词 Channel 脱离旧音频插件；后台暂停后释放应用内部 Controller 绑定。界面重连读取原生队列，首轮迁移才从原 Dart 数据库恢复。
- 原生 checkpoint 位于应用 no-backup 私有目录，通过串行临时写入 / rename 保存元数据、队列、位置、音量与本地资源引用，冷启动不自动播放；不保存远程 URL、认证头或密码。源停用 / 删除使相应本地引用失效并停止匹配输出。

## 当前边界

- 本轮没有实现完整的原生持久来源授权、令牌后台刷新与跨进程恢复索引，因此不注册 MediaButtonReceiver，不承诺系统杀进程后的媒体控件 playback resumption。已有本地描述符可由原生服务复用；新在线解析仍需要应用级 Flutter 业务引擎，Activity 不需要保持打开。
- 当前完整缓存下载与原生音频读取是独立请求，可能比旧 Dart relay 的顺路捕获消耗更多流量。没有把 Range 残片标成 READY；也没有引入 SimpleCache 或改动缓存数据库格式。
- 原生服务错误提供手动重试；不沿用旧 Dart AO 重载补丁，不承诺 Media3 自身解决所有 OEM / AudioTrack 无声问题。
- 当前队列浏览不等于完整 Android Auto 曲库、最近播放或语音搜索支持。
- 仅修改主工作区；OpenList 特性工作区保留原状。未改变版本号、提交、推送或发布。

## 2026-11-13 控制器权限与交互回归修复

用户反馈上一版媒体通知消失、进度不可拖动、切歌及多项播放页操作异常。代码核对确认：Media3 1.11 的旧 Callback.onConnect 默认结果是带特殊标记的空权限占位，旧实现把其中的空 availablePlayerCommands / availableSessionCommands 复制到新连接结果，丢失特殊标记。结果是应用 Controller 和应用内部通知 Controller 仅剩自定义命令权限，标准播放 / 暂停、Seek、切歌、速率 / 音量及时间线读取都不可用，通知管理器也无法读取有效队列。现在改用 onConnectAsync 与 AcceptedResultBuilder(session, controller)，为本应用补充自定义命令，保留标准 Player 命令；外部 Controller 延续 Media3 的可信 / 只读权限区分。来源：[固定版本 Callback 源码](https://github.com/androidx/media/blob/1.11.1/libraries/session/src/main/java/androidx/media3/session/MediaSession.java)。

桥接在下发标准操作前显式检查命令可用性，不再把被 Controller 静默忽略的操作作为成功。队列修订只在 Dart 接受完整快照后回传确认，避免新采样越过完整队列响应而漏掉元数据。缓冲期间快速切歌可复用已由 Media3 确认的前台状态，为当前意图申请焦点；旧通知回调不会把新意图永久留在等待状态。重复 prepare / play 不重复打开尚在加载的当前曲目。Seek 保留目标位置，拒绝旧解码器位置回写，超过八秒仍未接近目标则提示错误。首次恢复旧队列时使用读取的速率 / 音量 / ReplayGain 设置，避免被队列响应中的原生默认值覆盖。

本轮仍按仓库约定仅编译、打包；设备交互是否恢复由用户确认，不能把前一轮或本轮编译成功当成功能验收。

## 2026-11-13 进入 App 唤醒通知与 Seek 确认

Activity 再次可见，以及界面首次连接 Controller 时，发送仅本应用可用的 wake 会话命令。已有队列以暂停的元数据 READY 恢复媒体卡片，并通过 Media3 triggerNotificationUpdate 显式刷新；不因展示通知打开音频、申请焦点或改变播放意图。正在播放时保留原状态；空队列不创建无曲目的媒体卡片。

此前 UI 的 seek Future 在命令提交后即返回，滑块立刻释放拖动值，可能先回到旧采样再跳到新位置；旧 1.5 秒匹配容差也过宽。现仍经同一 MediaController / Session 操作唯一 Player，Seek 返回值等待原生 SEEK / PLAYBACK_RESTART 事件及接近目标的有效位置采样；位置容差按速率限定，确认后的快照先更新，再完成 UI 等待。原生 JNI 新增 playback restart 观察，八秒超时及来源失效 / 停止 / 切曲 / 销毁边界清理等待，旧目标不会完成新一次 Seek。

本轮没有运行测试、应用启动或设备验收；仅完成普通入口编译和内部打包，结果见 PROGRESS。

## 编译与验收

按仓库约定只进行普通入口 Android 三 ABI / Windows Release 编译与内部打包。没有运行 analyze、单元 / Widget / 集成测试、应用启动、设备命令或真实来源请求。构建记录与产物以本轮 PROGRESS 条目为准；通知显示、后台长暂停、HyperOS、蓝牙、真实声音与来源兼容性由用户验收。

参考：[Media3 后台服务](https://developer.android.com/media/media3/session/background-playback)、[SimpleBasePlayer](https://developer.android.com/reference/androidx/media3/common/SimpleBasePlayer)、[固定依赖版本](https://developer.android.com/jetpack/androidx/releases/media3)。附件原始设计保留于 [架构蓝图](ANDROID_MPV_MEDIA3_ARCHITECTURE.md)，其中尚未交付的里程碑不能视为已完成。

## De-click 更新

2026-11-13：经用户授权，Android 更换为带完整所需滤镜的固定 mpv-android 2026-09-17 原生运行库，先前“沿用 mpv 0.35 精简库”的描述属于历史。保持现有单一 Media3 Session / mpv context；新增默认关闭的 De-click 实验开关、逐样本 afade、原生事件日志和输出格式诊断。缓冲参数不变，滤镜淡出需要等待已排队的 PCM，可能产生额外跳转延迟。实现、来源及实听边界见 ANDROID_DECLICK.md / NATIVE_DEPENDENCIES.md。
