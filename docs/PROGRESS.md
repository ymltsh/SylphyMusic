# 实施与验证记录

## 2026-10-30 合并 AudioTrack 验证分支并发布 1.0.13+26

用户确认 AudioTrack 补丁有效，授权合并 `validation/android-audiotrack`。已合入 main 并推送，保留验证版的音频输出顺序与实际后端诊断逻辑，移除实验专用命名并更新验证说明；源码提交 `2926907`。

正式版 [1.0.13+26](https://github.com/ymltsh/SylphyMusic/releases/tag/v1.0.13%2B26) 已发布，Android 三 ABI、Windows Release 与安装程序编译成功，Android 正式签名校验通过。六个远端附件大小及 SHA-256 与本地一致，GitHub latest、原始与加速正式清单均指向本版，清单提交 `7e5bb80` 已推送。产物位于 `build/releases/1.0.13-26/`，日志为 `build/test_logs/release-1.0.13.log`。

本轮未运行静态分析、测试或设备验证；补丁有效性依据用户对 Beta 版的验证反馈，Windows 未代码签名。

## 2026-10-30 AudioTrack 验证分支与测试更新 1.0.13-beta+25

在 `validation/android-audiotrack` 分支应用 `SylphyMusic-android-audiotrack-validation.patch`，基于当前已发布的耳机控制改动：Android 请求优先 AudioTrack、回退 OpenSL ES，并在每首曲目进度超过 500ms 后记录实际 `current-ao`。实验代码未合入 main；main 仅更新测试清单。

发布预发布版 [1.0.13-beta+25](https://github.com/ymltsh/SylphyMusic/releases/tag/v1.0.13-beta%2B25)，标签指向验证源码提交 `0f3a655`。Android 三 ABI、Windows Release 与安装程序编译成功，Android 正式签名校验通过，六个远端附件的大小和 SHA-256 与本地一致。测试清单提交 `b97f38e` 已推送 main，正式版清单保持 1.0.12+24。

产物位于 `build/releases/1.0.13-beta-25/`，日志为 `build/test_logs/release-1.0.13-beta.log`。未运行静态分析、测试或设备验证；实际后端及爆音对比由用户参照 `docs/ANDROID_AUDIOTRACK_VERIFICATION.md` 验证。

## 2026-10-30 应用耳机播放控制补丁并发布 1.0.12+24

应用 `sylphymusic-headset-transport-loop.patch`：Android 原生媒体按键入口拒绝空事件并消费长按重复事件，不重复转发到 Dart。外部播放 / 暂停 / 切换命令在间隔不超过 800 毫秒的连续突发中最多接受六次，超限暂停并忽略后续命令，静默超过 800 毫秒后恢复；耳机单击依据同步播放意图切换，避免原生状态延迟造成反复启停。应用内操作、系统焦点处理与停止命令保留原路径，同步第三方补丁说明。

发布正式版 [1.0.12+24](https://github.com/ymltsh/SylphyMusic/releases/tag/v1.0.12%2B24)，Android 三 ABI、Windows Release 与安装程序编译成功，Android 正式签名匹配；六个固定名称资产远端大小 / SHA-256 与本地一致，GitHub latest 与远端正式清单已更新。仅清单提交 `32af9b1` 已推送，源码改动保留本地。日志为 `build/test_logs/release-1.0.12.log`，产物位于 `build/releases/1.0.12-24/`。

按用户约定未运行静态分析、测试或设备验证，耳机与蓝牙实际操作由用户确认；Windows 未代码签名。

## 2026-10-30 桌面歌词字号 / 背景自动淡出并发布 1.0.11+23

Android 桌面歌词增加独立字号滑块（12–40，默认 20），复用 settings 保存并经既有通道即时传入原生 TextView；更新去重包含字号。原生背景与关闭按钮在显示、修改颜色 / 字号或操作后静置 2.5 秒，以 350 毫秒淡出，仅保留歌词；触摸恢复操作区域，拖动期间取消淡出，松手重新计时。普通歌词更新保留当前背景透明度，不重置淡出计时；关闭窗口移除计时回调并取消动画。

发布正式版 [1.0.11+23](https://github.com/ymltsh/SylphyMusic/releases/tag/v1.0.11%2B23)，Android 三 ABI、Windows Release 与安装程序构建完成，Android 正式签名匹配；六个固定名称资产远端大小 / SHA-256 与本地一致，GitHub latest 与远端正式清单已更新。仅清单提交 `4671cb9` 已推送，源码改动保留本地。日志为 `build/test_logs/release-1.0.11.log`，产物位于 `build/releases/1.0.11-23/`。

按用户约定未运行静态分析、测试或设备验证，实际悬浮交互由用户确认；Windows 未代码签名。

## 2026-10-30 应用歌词颜色 / Android 桌面歌词补丁并发布 1.0.10+22

应用 `sylphymusic-lyrics-colors-android-desktop.patch`，适配现有封面预热装配上下文，保留后两首预取。歌词页提供专辑取色、跟随系统与固定颜色；Android 新增默认关闭的悬浮桌面歌词，可在歌词设置中主动开启、授权悬浮窗、拖动或关闭，颜色支持跟随系统与固定值。复用现有播放器、歌词加载与 audio_service 引擎，在 disposeAsync 中先关闭悬浮歌词协调再关闭播放和存储。颜色与开关复用 settings，不修改数据库 schema。修正 Kotlin 关闭按钮 text 属性与函数参数同名导致的编译错误。

本次包含此前炭灰深色主题与自适应导航补丁，发布正式版 [1.0.10+22](https://github.com/ymltsh/SylphyMusic/releases/tag/v1.0.10%2B22)。Android 三 ABI、Windows Release 与安装程序编译成功，六个固定名称资产远端大小 / SHA-256 与本地一致；GitHub latest 和远端正式清单已更新，仅清单提交 `8a40160` 已推送，源码修改保留本地。

Android 正式签名匹配，Windows 未代码签名。按用户约定未运行静态分析、测试或设备验证，实际功能与悬浮权限流程由用户确认。发布日志为 `build/test_logs/release-1.0.10.log`，产物位于 `build/releases/1.0.10-22/`。

## 2026-10-30 应用炭灰深色主题与自适应底部导航补丁

应用 `sylphymusic-charcoal-dark-adaptive-navbar.patch`：深色 Surface 改为分层炭灰色，保留用户主色作为强调色；一级页纯色底与播放页共用主题 Surface，深色封面模糊遮罩沿用炭灰底色。播放页基础主题复用 sylphyTheme；底部 NavigationBar 根据字体缩放与屏幕高度调整到 68–104 逻辑像素，保留系统安全区处理，深色导航栏与折叠 FAB 使用对应主题层级。同步外观说明。

Android 三 ABI Release 与 Windows Release 编译、内部打包完成，版本保持 `1.0.9+21`，产物位于 `build/internal-review/`，日志为 `build/test_logs/charcoal-dark-adaptive-navbar-build.log`。未运行静态分析、测试或设备验证，未提交、推送或发布。

## 2026-10-30 应用歌词 / 菜单 / 滑动补丁并发布 1.0.9+21

应用 `sylphymusic-lyrics-menu-slide-fix.patch`：LRC 时间标签兼容 Emby 附带的结束标记，避免后缀混入歌词；播放页更多菜单复用歌曲操作入口，加入歌单与黑名单 / 取消屏蔽；迷你播放器打开播放页使用自下向上动画，返回使用向下退出动画，遵循系统减少动画设置。本次同时交付此前未发布的后两首封面、歌词与音频预取补丁。

Android 三 ABI、Windows Release 和安装程序编译成功，发布正式版 [1.0.9+21](https://github.com/ymltsh/SylphyMusic/releases/tag/v1.0.9%2B21)。六个固定名称资产的远端大小 / SHA-256 与本地一致，GitHub latest 和远端正式清单已指向本版；仅清单提交 `5fbd1d8` 已推送，源码改动保留本地。发布进程通过 NO_PROXY 绕过本机代理，不修改系统代理设置。

按用户约定未运行静态分析、测试或设备验证，实际行为由用户确认。Android 使用正式签名，Windows 未代码签名。日志为 `build/test_logs/release-1.0.9.log`，本地产物位于 `build/releases/1.0.9-21/`。

## 2026-10-30 应用后两首预取补丁

应用 `sylphymusic-two-track-prefetch.patch`，适配补丁中省略的 setRepeat / clearQueue 函数上下文及文件分隔头。播放时按实际队列顺序预热后两首封面、歌词，顺序尝试完整音频缓存；第一首完整缓存失败时回退内存前缀预取。列表循环可跨队尾，随机模式不猜测下一轮顺序，单曲循环不预取其他曲目。队列、模式和播放意图变化使过期计划失效，保留现有来源取消与缓存完整性边界。

自动整曲下载令牌可被手动请求接管，取消自动工作时包含尚未注册活动连接的下载；相同资源签名不因 touch 重复校验摘要。应用装配共用 ArtworkStore 回调，新增诊断 rank 字段进入白名单，避免导出过滤预取顺序信息。同步架构说明。

Android 三 ABI Release 与 Windows Release 编译、内部打包完成，版本保持当前 `1.0.8+20`，产物位于 `build/internal-review/`，日志为 `build/test_logs/two-track-prefetch-build.log`。按用户约定未运行分析、测试或设备验证，未连接私人音源，未提交、推送或发布。

## 2026-10-29 发布 1.0.8+20

按用户要求发布正式版 [1.0.8+20](https://github.com/ymltsh/SylphyMusic/releases/tag/v1.0.8%2B20)，内容是上一轮的音频焦点恢复补丁，更新日志保持三条面向用户的描述。Android 三 ABI APK、Windows 安装程序、便携 ZIP 与摘要文件共六个固定名称资产上传完成，远端大小与本地一致；正式清单 `latest` 指向 1.0.8+20、history 保留 11 条，清单提交 `7ce3f6d` 已推送。

首轮在发布阶段失败：系统代理仍指向 `127.0.0.1:7890`，本机代理客户端当时未监听，Python urllib 读取注册表代理后连接被拒绝，构建与签名校验已完成但未创建 Release。随后临时关闭系统代理、以 `--skip-build` 复用 `build/releases/1.0.8-20/` 产物重跑，上传与清单推送完成后恢复代理设置。Android 正式签名校验通过，Windows 未代码签名；按约定未运行静态分析、测试或设备验证，实际恢复行为由用户确认。日志位于 `build/test_logs/release-1.0.8.log` 与 `release-1.0.8-publish.log`。

## 2026-10-29 应用音频焦点恢复补丁

应用 `sylphymusic-audio-focus-resume.patch`：把「焦点丢失」与「可恢复播放」拆成两份状态，GAIN 不再立即重启。暂停型丢失时登记恢复资格与曲目；GAIN 后等待 2 秒稳定期，期间校验恢复代次、播放意图代次、加载代次、当前曲目与 15 秒时间上限，任一变化即放弃。12 秒内第二次丢失判定为抖动并取消自动恢复，避免视频类源逐条抢占焦点时反复启停。永久丢失（`unknown`）不产生恢复资格；duck 走 `_ducking` 与统一音量入口，用户调整音量不会覆盖闪避值。

同时修正三处行为：焦点被系统暂停时不再把 `_userPaused` 推断为用户暂停（原 `_loadCurrent` 按 `_playRequested` 覆盖）；释放焦点被拒不再抛出 `StateError` 触发跳曲，改为显示「系统暂时未授予音频焦点」；清空队列与退出时显式 `setActive(false)` 释放焦点。播放、暂停、换曲、重试、清空队列等用户操作会重置恢复状态。

`flutter build windows --debug` 与 Android 三 ABI Release 编译成功。按约定未运行静态分析、测试或设备验证，通话、蓝牙与耳机插拔后的实际恢复行为由用户确认。

## 2026-10-29 发布 1.0.7+19 并将源码同步到仓库

按用户要求发布正式版 [1.0.7+19](https://github.com/ymltsh/SylphyMusic/releases/tag/v1.0.7%2B19)，更新日志收敛为两条面向用户的变化，不再附带签名与验证过程说明：新增播放页「歌曲信息」，修复部分 Emby 服务器歌词缺失。Android 三 ABI APK、Windows 安装程序、便携 ZIP 与摘要文件共六个固定名称资产上传完成，远端大小与本地一致；正式清单 `latest` 指向 1.0.7+19、history 保留 10 条，清单提交 `07ee94e` 已推送。README 同步补充「歌曲信息」说明。

Android 正式签名校验通过，Windows 未代码签名；按约定未运行静态分析、测试或设备验证，实际界面效果由用户确认。日志位于 `build/test_logs/release-1.0.7.log`，本地产物位于 `build/releases/1.0.7-19/`。

本轮同时把 1.0.4 以来一直保留在工作区的源码、原生补丁与文档提交到仓库，此前各次发布只推送版本清单，`main` 与实际发布内容长期不一致。

## 2026-10-29 重写面向用户的 README，开发说明迁入 CONTRIBUTING

按用户要求参考官网重写 `README.md`：顶部 Logo、三张界面截图（音乐首页 / 沉浸播放 / 歌单封面流）、品牌句与徽章，以及核心能力、支持的音源、下载、快速开始、技术栈、文档索引与许可证。截图与 Logo 取自官网 `assets/`，等比缩放后存放在 `.github/assets/`；`pubspec.yaml` 只声明具体文件，因此不进入 Flutter 资源包。徽章与五个固定名称下载地址均实测返回 200，正式版徽章显示 `v1.0.6+18`。

原 README 的开发内容迁入 [CONTRIBUTING](../CONTRIBUTING.md)：环境与平台 Runner 约定、Windows / Linux 运行命令、用户自主验证清单、私密联调环境变量与测试文件、内部打包体积与产物、验收与发布边界。`docs/README.md` 同步修正 README / CONTRIBUTING 两条用途说明，并把 Emby `Extradata` 内嵌歌词的优先级补充到 [Emby 歌词](EMBY_LYRICS.md)。仅文档变更，未重建应用、未运行静态分析或测试。

## 2026-10-29 应用歌曲信息与 Emby Extradata 歌词补丁

应用外部补丁：新增 `lib/ui/song_info_sheet.dart`，播放页菜单「音质信息」改为「歌曲信息」并分组展示基本 / 音频 / 文件 / 来源信息，过滤鉴权流地址后再展示原始路径；`lib/services/sources.dart` 在字幕流转换接口之前优先解析 MediaStreams 的 `Extradata` 原文，能得出 LRC 时间轴就直接返回，仅纯文本时留作回退，沿用 1 MiB 限制。

两处补丁由 `git apply` 直接应用，行号偏移自动校正；`dart format` 重排 `song_info_sheet.dart`。`flutter build windows --debug` 成功（`build\windows\x64\runner\Debug\sylphy_music.exe`），按约定未运行静态分析、测试或设备验证，界面效果由用户确认。

## 2026-10-29 去除唱片孔、补充歌词过渡并发布 1.0.6+18

按用户要求移除共用 PlayerCover 的圆形唱片中央打孔点，保留外圈、封面和旋转。发布期间用户补充歌词预览缺少动画，停止尚未上传的首轮发布流程后，补充 LyricsPreview 的 320 毫秒滑动 / 淡入淡出及高亮颜色、字重过渡；按粗体测量固定行高，减少高亮改变导致的布局跳动，遵循系统减少动画设置。保留既有可见行数、自适应缩放与两行省略规则。此次同时包含本地 / 云歌单复制菜单互斥调整。

重新构建并发布正式版 [1.0.6+18](https://github.com/ymltsh/SylphyMusic/releases/tag/v1.0.6%2B18)，Android 三 ABI APK、Windows 安装程序、便携 ZIP 和摘要文件共六个固定名称资产已上传，远端大小 / SHA-256 与本地一致，GitHub latest 与远端正式清单已指向该版本。仅清单提交 `d37f11c` 已推送，源码改动保留本地。

Android / Windows Release 构建成功，Android 正式签名匹配，Windows 未代码签名；按用户约定未运行静态分析、测试或设备验证。日志位于 `build/test_logs/release-1.0.6.log`，本地产物位于 `build/releases/1.0.6-18/`。歌词动画实际效果由用户确认。

## 2026-10-29 歌单复制菜单按目标类型互斥

按用户澄清，云歌单隐藏“复制为云端歌单”，本地歌单隐藏“复制为本地歌单”及原先同类型的“复制歌单”；两类歌单仅保留跨类型复制。收藏保留复制为独立歌单的入口，云端目标仍要求存在已启用的可写来源。网格与详情共用此规则。

Android 三 ABI 与 Windows Release 编译 / 内部打包完成，日志为 `build/test_logs/playlist-copy-menu-build.log`，产物位于 `build/internal-review/`。未运行分析、测试或设备验证，未提交、推送或发布。

## 2026-10-29 发布 1.0.5+17 固定附件名更新

按用户要求发布正式版 [1.0.5+17](https://github.com/ymltsh/SylphyMusic/releases/tag/v1.0.5%2B17)，安装附件使用五个固定文件名，另附 SHA256SUMS.txt。GitHub latest 已指向本次正式版，远端六个资产大小 / SHA-256 与本地一致，远端正式清单为 1.0.5+17，清单提交 `daff65a` 已推送。官网可使用 releases/latest/download 下的固定名称，历史版本附件保持原名。源码与脚本修改保留本地，未额外提交。

Android 三 ABI Release、Windows 安装程序和便携包构建完成，Android 正式签名匹配；未运行静态分析、测试或设备验收。日志位于 `build/test_logs/release-1.0.5.log`，本地产物位于 `build/releases/1.0.5-17/`。

## 2026-10-29 发布附件改为固定文件名

按用户要求调整 release.py 与 Windows 安装脚本：五个安装附件统一为 `sylphy-music-arm64-v8a.apk`、`sylphy-music-armeabi-v7a.apk`、`sylphy-music-x86_64.apk`、`sylphy-music-setup.exe`、`sylphy-music-windows.zip`。本地版本目录、Release Tag 与安装包内部版本继续保留版本号；摘要、资产上传、复用产物和版本清单链接同步使用固定名称。应用历史清单仍指向各自 Tag，官网可在新正式 Release 发布后使用 releases/latest/download 固定链接。

同步更新流程说明与已有复用产物用例中的文件名。Python 脚本编译成功，未运行分析或测试，未重建应用、上传新资产、修改历史附件或发布版本；当前 1.0.4 的旧附件保持原名，新固定链接尚待下次发布生效。

## 2026-10-29 发布 1.0.4+16

按用户要求一键发布正式版 [1.0.4+16](https://github.com/ymltsh/SylphyMusic/releases/tag/v1.0.4%2B16)，包含 Android 10 白色媒体控制按钮、内置图标资源裁剪修复、歌单类型菜单 / 逐条移除及 FAB / 横条启动默认项。Android 三 ABI APK、Windows 安装 EXE、便携 ZIP 和摘要文件共六个资产发布完成，远端大小和 SHA-256 与本地一致，远端正式清单已指向新版本。仅清单提交 `e5c3d7f` 已推送，源码修改保留在本地。

Android 与 Windows Release 构建成功，Android 正式证书匹配，Windows 未代码签名；未执行静态分析、测试、启动或设备验证。日志位于 `build/test_logs/release-1.0.4.log`，本地产物位于 `build/releases/1.0.4-16/`。

## 2026-10-29 修复 Release 通知控制图标被裁剪

用户反馈 Android 10 通知按钮不可见但可点击。检查现有 Release 的 `build/app/outputs/mapping/release/resources.txt`，播放、暂停、上一首、下一首等 audio_service 图标均标记为不可达；这些资源名由 Dart 动态传入，原生仅通过 getIdentifier 查找，资源裁剪器无法追踪，按钮视图及 PendingIntent 则仍保留。

原生 getResourceId 对七个内置媒体操作图标改为显式 R.drawable 引用，自定义名称继续使用原查找方式；保留 Android 10 白色图标和封面取色方案。重新构建后的资源记录确认四个主要控制图标均从 R.drawable 引用可达。Android 三 ABI 与 Windows Release 编译 / 内部打包完成，日志为 `build/test_logs/android-media-icons-retention-build.log`，产物位于 `build/internal-review/`，版本保持 `1.0.3+15`。

未运行静态分析、测试或设备验证，实际 Android 10 通知显示待用户确认；未提交、推送或发布。

## 2026-10-29 播放器样式改为启动默认项

按用户补充，播放器外观中的 FAB / 横条仅保存每次启动的默认值；主界面运行时长按横条折叠、点击 FAB 展开只修改本次会话状态，不再写入外观设置。更改设置中的默认项会立即应用；其他外观变化及前后台切换保留本次手动选择。

Android 三 ABI 与 Windows Release 编译、内部打包完成，日志为 `build/test_logs/player-startup-default-build.log`，产物位于 `build/internal-review/`。未运行分析、测试或设备验证，未提交、推送或发布。

## 2026-10-29 歌单菜单、逐条移除与播放器控制偏好

歌单网格右上角更多按钮移除白色圆底，保留带阴影的白色图标；网格与详情共用按收藏 / 本地 / 云端及读写、同步状态生成的操作菜单。收藏不提供改名或删除，本地仅提供本地操作，只读云歌单隐藏改名、编辑、添加、移除曲目和服务器删除，不存在可写云端目标时隐藏复制云歌单。

歌单内单曲更多增加“从此歌单移除”，收藏中显示“从收藏移除”。通过独立 entry_id 删除当前条目，保留同曲其他重复条目及其身份；云歌单沿用待同步 / 冲突状态和既有同步流程。只读来源不显示移除，也排除在添加到歌单目标中。

外观 → 播放器外观新增“播放器控制”，可选择主界面横条或 FAB 悬浮按钮，使用既有 settings 保存 `ui_player_fab` 并在重启后恢复；长按折叠 / 点击展开与该偏好同步。未改变数据库 schema。

Android 三 ABI Release 与 Windows Release 编译、内部打包完成，版本保持 `1.0.3+15`，产物位于 `build/internal-review/`，日志为 `build/test_logs/playlist-player-controls-build.log`。按维护者约定未新增或运行静态分析、测试或设备验证；未提交、推送或发布，功能由用户验证。

## 2026-10-29 应用 Android 10 白色媒体按钮补丁

应用 `sylphymusic-android10-white-media-buttons.patch`：Android 10 / API 29 且有三个媒体操作时，使用 DecoratedMediaCustomViewStyle 和自定义 RemoteViews，将操作图标固定为白色，继续使用原有图标、无障碍说明和 PendingIntent，保留封面取色背景。其他系统版本及操作数量沿用原媒体样式。工程已有本地 audio_service 依赖，因此跳过重复的 pubspec 修改，并移除此前 `setColorized(false)` 的覆盖代码。原补丁缺少标准文件分隔头，归一化后应用 Java 与新增 XML 布局；同步本地依赖补丁说明。

最终 Android 三 ABI Release 与 Windows Release 编译和本地打包完成，版本保持 `1.0.3+15`，产物位于 `build/internal-review/`，日志为 `build/test_logs/android10-white-media-buttons-build.log`。未运行静态分析、测试或设备验证，Android 10 实际通知效果由用户验证；未提交、推送或发布。

## 2026-10-29 快速发布 1.0.3+15

按维护者要求直接运行一键发布，发布 [1.0.3+15](https://github.com/ymltsh/SylphyMusic/releases/tag/v1.0.3%2B15)，包含飞牛音乐首期接入、后台播放与下载取消隔离、本地代理探测 / 恢复、Android 10 通知配色及返回前台手势条恢复。Android 三 ABI Release、Windows 安装程序 / 便携 ZIP 和摘要文件共六个资产已发布，远端大小与 SHA-256 均匹配本地，正式更新清单已指向新版本。清单提交 `20b0273` 已推送；源码修改和本地版本号保留在工作区，未额外提交源码。

发布日志位于 `build/test_logs/release-1.0.3.log`，本地产物位于 `build/releases/1.0.3-15/`。按当前约定未运行静态分析、测试、启动或设备验证；实际功能由用户验证。Android 使用既有正式签名，Windows 未代码签名，Linux 不分发。

## 2026-10-29 应用后台播放 P0 补丁

应用 `sylphymusic-background-playback-p0.patch`：离线缓存任务暂停 / 取消仅终止所属下载，保留同曲播放 relay；下载注册时等待已有活动传输，避免覆盖取消令牌，取消操作保持幂等。本地媒体代理增加回环 `/health` 探测、串行 start / restart / dispose，重启清除旧票据并关闭旧上游连接；播放停滞恢复仅在本地代理不响应时尝试重启，并通过播放意图代际避免过期恢复继续执行。补充 Dart 计时器延迟与 Android Application / Activity 生命周期日志。

同步将新增 `gap_ms` 加入脱敏日志白名单，避免导出丢失延迟数值，并说明原生 logcat 与应用内诊断开关的区别。保留此前已有的后台播放学习、分块缓存分析文档及其索引 / 进度修改。

Android 三 ABI Release 与 Windows Release 编译和本地打包完成，版本保持 `1.0.2+14`，产物在 `build/internal-review/`，构建日志为 `build/test_logs/background-playback-p0-build.log`。按维护者要求未新增或运行静态分析、测试或设备验证；后台长期播放效果由用户验证。未连接私人音源、提交、推送或发布。

## 2026-10-29 分块缓存参考调查

继续分析棉花音乐 APK，追踪 fragment 的 span / hole 读取切换、范围锁及提交通知、模块外写入包装器的容量判断和滚动提交、片段索引与启动扫描、按访问时间淘汰，以及片段向完整文件迁移时的其他请求保护。整理 [分块缓存参考分析](FRAGMENT_CACHE_REFERENCE.md)，与当前强 ETag 内存前缀复用、完整 SHA-256 缓存及 TEMP 清理对照，提出阶段性升级清单。

明确分块落盘不等于每块独立 HTTP 请求或并行下载；未确认固定片段默认大小、参考软件的全部版本校验、摘要校验与崩溃恢复保证。此次仅修改分析文档与索引，未改业务代码、编译或执行功能测试，不将分块缓存描述为已解决系统后台限制。

## 2026-10-29 后台持续播放参考分析与学习清单

按用户要求继续分析本地棉花音乐 4.13.7 APK，确认播放器 `checkPing` 调用本地代理 ping，失败时调用带互斥保护的重启流程；重启包含先停止、延迟、再启动，播放错误处理具有曲目计数和重试 / 停止分支。结合当前代码整理 [后台持续播放学习清单](BACKGROUND_PLAYBACK_LEARNING.md)，区分 APK 已确认设计、尚不能确认的配置和我们自身的改进建议。

建议优先处理离线下载暂停与播放 relay 的取消所有权、代理健康检查与串行恢复、原生 open / 切歌卡住边界及跨原生 / Dart 的故障证据，随后考虑票据分类、Wi-Fi 和预取策略。仅新增分析文档与索引，未修改业务代码、安装参考应用、编译或运行功能测试；长期后台问题的根因仍待设备证据确认，所有实施项为待办。

## 2026-10-29 应用飞牛音乐首期接入补丁

应用 `sylphy_fnmusic_phase1.zip`，增加 `SourceKind.fnMusic` 和 `FnMusicAdapter`、来源入口与 `/music` 地址提示，接入应用独立账号认证、分页曲库、音频代理、封面、歌词和只读云歌单。云歌单读取与写入能力分离，飞牛来源不出现在新建 / 复制云歌单目标中；连接编辑沿用服务器与账号身份核对。未改变数据库结构。同步来源接入说明与架构文档。

首轮编译发现服务器地址输入框的 const InputDecoration 引用了动态来源类型，移除该 const 后，Android 三 ABI Release 与 Windows Release 编译、内部打包完成，产物位于 `build/internal-review/`，日志为 `build/test_logs/fnmusic-phase1-build.log`，版本保持 `1.0.2+14`。按维护者要求未新增或运行分析、测试和设备验证，未连接真实飞牛服务器；FN Connect 自动寻址与云歌单写入暂不支持。功能验证由用户负责，未提交、推送或发布。

## 2026-10-29 交付流程改为编译成功即可

按维护者要求取消默认验证修复流程：日常交付以相关平台编译成功为准，静态分析、测试、启动冒烟和设备验收由用户负责，代理不默认新增或执行验证测试，也不追修历史验证失败。AGENTS、开发指南、README、更新流程及验收参考同步说明此约定；此前的验证记录保留为历史证据，不构成当前交付前置条件。

初始化脚本和发布脚本移除 analyze/test，CI 仅保留各平台构建；旧 `--skip-checks` 参数兼容但不再需要。现有测试和 `tool/check_local.ps1` 保留供用户主动验证。本次仅调整流程文档与配置，未重新编译应用或执行测试，未提交、推送或发布。

## 2026-10-29 应用后台播放 / Android 10 通知补丁及手势条恢复修复

应用 `sylphymusic-android10-media-notification.patch` 与 `apply_sylphy_emby_background_fix_v2.py`。引入已锁定的 audio_service 0.18.19 运行源码与许可证作为本地依赖，仅在 Android 10 关闭通知封面取色。播放服务新增 45 秒无进度恢复检查、打开 / 切歌卡住诊断、恢复代际校验及自动传输取消；预取和媒体代理补充超时与脱敏阶段事件，预取版本不一致时直接关闭旧连接并重新请求。

根据用户提供的对话继续处理后台返回后底部手势条不再沉浸的问题：全局 AppSystemBars 在 resumed 时重新启用 edge-to-edge，并请求原生插件恢复已保存的系统栏样式，覆盖各路由；继续按主题和手势 Insets 设置图标明暗及三键对比度保护。本轮采用 Flutter 生命周期恢复，尚未增加 Activity 级恢复。

静态分析、改动文件格式检查和全量 244 项测试通过，5 项私密联调默认跳过；包括新增的卡住旧连接重试及 6 项系统栏生命周期 / 样式测试。日志为 `build/test_logs/two-patches-analyze.log`、`two-patches-tests-final.log` 和 `system-bars-resume-tests.log`。最初新增代理用例误用共享请求 gate，修正测试夹具后通过；并行运行 Windows 原生构建期间的一轮全量测试未完整结束，最终串行复测完整通过。

Android 普通主入口 Debug 与 Release 三 ABI 构建通过，Release 正式证书匹配通过。按 `tool/build_review.ps1` 生成本地验收包，版本保持当前 `1.0.2+14`。Windows 原生集成测试首次因系统临时目录权限失败，切到工程内临时目录重试后仍在 `mediaControls` 能力断言处失败，未标为通过。当前无连接的 Android 设备，Android 10 通知图标、锁屏 / 长时间后台播放及返回后的手势条效果、共享引擎 Activity 重建仍待用户设备验证。未连接私人音源，未提交、推送或发布。

## 2026-10-28 关于页更新与 1.0.1 发布准备

应用 `sylphy-about-page-bundle.zip`，设置入口改为独立关于页，包含项目介绍、官网 / 仓库 / 发布链接、实际安装版本和许可证；加入七连击天琴座星图。适配当前设置构造参数，修复彩蛋退出后不能再次打开和横屏大字体溢出；保留后台歌词预热修复。

关于页六项 Widget 测试和静态分析通过，Windows 原生主界面回归通过，覆盖设置入口、实际版本、许可证和星图横竖屏；截图位于 `build/test_logs/ui/about-*.png`，日志为 `about-page-tests.log`、`about-page-analyze.log`、`about-page-native.log`。后台歌词相关 46 项测试已通过。本次按用户授权发布 `1.0.1+13`，复用上述检查，使用 `--skip-checks` 直接构建和发布，不重复运行验收。

## 2026-10-28 应用后台歌词预热修复

应用 `SylphyMusic-background-lyrics.patch`：播放服务在选中 / 恢复曲目及临近下一首预取时，通过应用装配的 LyricsStore 回调后台加载歌词，不再依赖先打开歌词页。同一 TrackRef 会话内去重，来源失效清除对应记录；同步异常和异步失败均隔离，不阻塞音频打开。沿用歌词缓存、来源取消和退出等待边界，在线歌词补充保持默认关闭。

相关播放 / 歌词 / 在线补充 / 预览测试 46 项通过，包含真实 Windows libmpv 下的无歌词页面预热、慢加载不阻塞、去重与来源失效重试、同步 / 异步错误隔离，以及恢复队列后自动写入歌词缓存且保持暂停。静态分析与格式检查通过。日志为 `build/test_logs/background-lyrics-tests.log` 和 `background-lyrics-analyze.log`。仅用合成音频和本机服务器，未运行 Android 设备检查，未生成安装包、提交、推送或发布新版本。

## 2026-10-28 发布 1.0 正式版并对齐参考发布流程

已发布 [1.0.0+12](https://github.com/ymltsh/SylphyMusic/releases/tag/v1.0.0%2B12)，源码提交 `3041023`，正式清单提交 `f849ab2`。提供 Android 三个 ABI 的正式签名 APK、Windows 未签名安装 EXE / 便携 ZIP 和 SHA256SUMS.txt。六个远端资产的大小与 SHA-256 和本地一致，正式清单及默认加速清单均指向 1.0.0+12，旧正式版保留在 history，测试清单保持 0.2.8-beta+11。Android 包身份 / 构建号 / 正式证书、Windows 版本与运行依赖、包内容扫描通过；未执行本轮设备安装或人工验收，Linux 不分发。

随后按维护者指定的 `Mfuns-Flutter/update.md` 对齐：默认一条命令完成构建、打包、Release 上传和清单提交推送，源码单独处理；删除本地准备 / 发布分段、源码指纹、release-record 依赖、干净工作区要求和验收阻断。基础 analyze/test 按参考工具保留，`--skip-checks` 可跳过且允许发布；`--no-push` 仅停止清单提交推送。文档只保留更新接口、一键命令、构建产物、Release 和清单维护步骤。对应发布工具回归 9 项通过，未重发或改动已经发布的 1.0 资产。

## 2026-10-28 简化发布标准与 1.0 准备

维护者要求直接发布 1.0，并将流程简化为“能跑就行”，随后明确将验收从发布流程移除。发布仅处理版本、构建、正式 Android 证书验证、私密内容扫描、打包上传、摘要核对和清单更新；分析、测试、启动冒烟与设备验收独立执行，不作为发布前置条件。发布脚本不再运行分析 / 全量测试，也不读取验收文档中的未勾选项阻断正式发布。旧门槛仍作为独立验收待办保留，未标记为通过。同步 AGENTS、README、开发 / 更新流程及发布工具回归测试。

本次目标为 `1.0.0+12`，Android 三个 ABI、Windows 安装程序与便携包；Windows 未代码签名，Linux 暂缓，测试签名包不提供覆盖迁移。构建、启动与远端核验结果在完成后追加记录。

## 2026-10-28 签名准备提交与测试版迁移范围确认

用户确认测试版未实际安装使用，允许直接提交并推送签名准备改动；本次切换按全新安装处理，不再以测试版数据迁移作为阻碍。更新签名说明与对应发布门槛，不改变旧证书无法直接覆盖的约束，也不将其他未验收项目标记为通过。私钥、密码与本机恢复副本仍只保留在 Git 忽略路径。

## 2026-10-28 Android 正式签名准备

按用户要求仅准备 Android 正式签名，Windows 代码签名暂缓。生成独立 RSA-3072 / PKCS#12 私钥（有效期 10000 天），存于已忽略的 `.private/android-signing/`，配置 `android/key.properties`，目录和配置 ACL 限制为当前用户与 SYSTEM。公共证书及 SHA-256 指纹纳入源码，更新本地配置示例；增加 `tool/verify_android_signing.py` 并接入 `release.py` 本地准备流程，校验 APK 签名与固定正式证书。

三种 ABI 的普通主入口 Release APK 构建及实际证书匹配通过；旧 0.2.8-beta+11 测试签名 APK 被校验工具拒绝。签名密码、私钥 / 配置文件的源码与 APK 内容扫描通过，私密路径 Git 忽略及 ACL 核对通过；发布工具 11 项测试与静态分析通过。构建日志为 `build/test_logs/android-production-signing-build.log`。

产物保留当前 0.2.8-beta+11 版本，只用于签名链路核验，不替换同版本线上测试包。未安装、卸载或改动设备数据，未提交、推送或发布。私钥独立离线备份与恢复演练尚待维护者执行；旧测试证书不能直接覆盖升级，迁移方案仍待确定和验收。详见 [Android 正式签名](ANDROID_SIGNING.md)。

## 2026-10-28 发布 0.2.8-beta+11 Android / Windows 测试更新

已发布 https://github.com/ymltsh/SylphyMusic/releases/tag/v0.2.8-beta%2B11 ，源码提交 `ce2e694`，beta 清单提交 `72e4b6c`。包含 Emby SRT 结束时间兼容与旧缓存读取、默认关闭的 LrcApi 补充、API 设置弹窗生命周期修复、播放页艺术家 / 专辑跳转和引导后台同步期间继续导航。

发布前格式与静态分析通过；全量应用测试 224 项通过、5 项私密联调默认跳过，发布工具测试 11 项通过，Windows 原生界面 / LrcApi 设置、播放页布局 / 跳转和引导后台同步共 4 项通过。Android 三份 APK 身份 / 构建号 / 签名校验、与 0.2.7 测试证书一致性、Windows 文件版本 / ZIP 完整性及运行依赖、输入与安装产物凭据内容扫描均通过。Android 专用 API35 模拟器从 0.2.7-beta+10 直接覆盖安装 0.2.8-beta+11，未卸载，保留引导完成状态并进入首页。

发布后核对六个远端资产（含摘要文件）的大小与 GitHub SHA-256 均和本地一致；测试版清单与默认加速清单均指向 0.2.8-beta+11，历史保留 0.2.7-beta+10，正式渠道保持 0.2.3+5。安装资产位于 build/releases/0.2.8-beta-11/，核验记录为 published-verification.json，日志位于 build/test_logs/release-0.2.8-*。

Android arm64-v8a 31.58 MiB、armeabi-v7a 28.72 MiB、x86_64 33.77 MiB；Windows 安装 EXE 19.06 MiB、便携 ZIP 22.69 MiB。Android 沿用测试签名，Windows 未代码签名；Windows 安装器实际安装 / 卸载、Android 真机及 Linux 本轮未验收，未请求真实公共 LrcApi 或私人音源。

## 2026-10-28 SRT 结束时间修复与 0.2.8-beta+11 更新准备

核对 sylphymusic-srt-end-time-fix.patch：零时长 / 倒置结束时间的处理与旧 Emby 缓存归一化已由此前修复覆盖，本次新增补丁中的完整三段字幕用例，验证纯音乐提示在 12 秒时仍高亮，不生成错误清空标记。此次测试版更新同时包含上次发布后的引导后台同步导航、播放页艺术家 / 专辑跳转及默认关闭的 LrcApi 补充。

发布前原生回归发现 LrcApi 地址 / 密钥弹窗的输入控制器在关闭动画结束前被释放；API 设置统一改用由弹窗 State 管理的控制器，随 Widget 卸载释放。Windows 界面回归新增开关、地址保存、密钥显隐与清除断言。版本提升至 0.2.8-beta+11，沿用 Android 测试签名与 Windows 未签名测试包，仅推进 beta 清单，正式渠道保持 0.2.3+5。

发布前验证：静态分析和全工程格式检查通过，全量串行应用测试 224 项通过、5 项私密联调默认跳过，发布工具 11 项通过。Windows 原生主界面 / LrcApi 设置、播放页布局 / 元数据导航和两项引导后台同步共 4 项通过；已查看 settings-lrcapi-mobile.png。日志位于 build/test_logs/release-0.2.8-*。Android 专用模拟器已覆盖安装上一版 0.2.7-beta+10 并确认首页可用，作为下一步覆盖升级基线。

## 2026-10-28 应用 LrcApi 在线歌词补充补丁

应用 sylphymusic-lrcapi.patch：新增默认关闭的在线歌词补充、可持久化接口地址、系统安全存储鉴权密钥及设置入口；原歌词优先，无可用内容或原来源请求报错时尝试补充，结果复用逐曲歌词缓存。修正补丁的 BytesBuilder 导入和可空字段编译问题，补齐来源取消、配置变更和应用退出的请求关闭 / 等待边界，以及空 JSON 响应识别。设置开关注明会发送歌名、艺术家与专辑；继续保留此前 SRT 修复。

验证：flutter analyze 无问题；LrcApi、API 设置、歌词解析 / 缓存、Emby、歌词页及预览共 48 项测试通过（build/test_logs/lrcapi-tests.log），包括默认禁用、URL / 元数据编码、鉴权与重定向 / 响应大小限制、空 JSON、请求取消、配置重载、原歌词优先、本地缺词补充、缓存离线复用及原错误保留。使用合成数据、MockClient 和回环服务器；未请求真实公共 LrcApi 或私人音源，未运行设备原生验收、构建安装包或发布。

## 2026-10-28 应用 Emby SRT 异常结束时间修复

应用 sylphymusic-emby-srt-fix.patch：零时长或结束时间倒置的字幕保留起始时间与提示文字，不合成清空标记；LyricsStore 读取 Emby 自动缓存时归一化旧 SRT，手动导入保持原文与优先级。此前播放页艺术家 / 专辑跳转及其他未提交改动均保留。

验证：dart format、flutter analyze 和 35 项歌词解析 / 缓存 / Emby 请求 / 歌词页及预览测试通过，补充零时长与已缓存倒置 SRT 的离线读取断言，验证不发网络请求、不改写缓存原文、手动导入保持原文。本轮使用合成数据与本机服务器，未连接真实 Emby，未执行设备验收、打包或发布。

## 2026-10-28 播放页艺术家与专辑跳转

播放页「歌手 / 专辑」组件拆为独立点击区域，分别打开统一音乐库对应艺术家或专辑的歌曲列表；沿用 SQL 分组规则（专辑含专辑艺术家）、分页、播放全部和歌曲菜单。返回保留播放页，浏览不改变当前队列或播放状态。默认与自定义布局共用入口，编辑器预览禁用跳转，空元数据不跳转；短组件框继续缩放与省略显示。歌曲菜单操作提取为共享 UI 方法，保持云歌单来源约束。

验证：flutter analyze 无问题；元数据文本、布局和目录查询相关 23 项测试通过。Windows 原生 integration_test/player_layout_test.dart 通过，新增两类入口、分组参数、实际歌曲列表、返回及暂停状态断言，并通过既有编辑器 / 响应式回归，日志 build/test_logs/player-metadata-navigation.log。原生测试使用 .private/native-temp 避开系统临时目录权限限制。本轮未执行 Android / Linux 原生验收，未打包或发布更新。

## 2026-10-28 引导导航不等待后台来源同步

修复 QuickStartWizard 将来源操作与导航 / 保存共用 busy 条件的问题：连接 / 导入任务继续防重入，但下一步、完成设置和跳过 API 配置只受引导自身保存状态约束。开始后台处理后显示可继续提示；离开并销毁引导 Widget 不等待或取消来源同步，现有应用级任务持有、通知和退出清理保持原行为。

flutter analyze 和格式检查通过；Windows 原生 integration_test/welcome_background_sync_test.dart 两项回归通过（build/test_logs/welcome-background-sync.log）。测试从引导真实添加合成 WebDAV 来源，将首次目录扫描 HTTP 请求保持未完成，分别验证保存 API 和跳过 API 都能进入首页、持久化完成状态，同时扫描仍 active；随后释放请求，索引正常完成，无销毁后 setState 异常。本轮未追加安装验收或生成 / 发布新 Release 包。

## 2026-10-28 发布 0.2.7-beta+10 Android / Windows 测试更新

已发布 https://github.com/ymltsh/SylphyMusic/releases/tag/v0.2.7-beta%2B10 ，源码提交 `0890782`，beta 清单提交 `b1dde80`。包含音乐源卡片管理、独立连接表单、三步引导、首次扫描通知授权等待 / 立即显示、歌词预览行距和设置顺序调整。提供 Android 三个 ABI APK、Windows 安装 EXE、便携 ZIP 和摘要文件；正式渠道保持 0.2.3+5。

发布前静态分析、格式、209 项应用测试与 11 项发布工具测试通过；Windows 原生界面 / 歌词编辑器与 Android 通知权限回归证据见前述记录。本轮构建脚本增加 ReleaseVersion 参数，Windows 文件版本为 0.2.7-beta+10，并通过构建参数保留运行时 beta 标记。安装资产完成凭据内容扫描、SHA-256、应用身份与旧版测试证书一致性校验；Android 构建号为 2010 / 1010 / 4010。自建 API35 模拟器从 0.2.6-beta+9 覆盖安装 0.2.7-beta+10，无卸载，保留引导完成状态并进入首页。

发布后核对六个远端资产的大小和 GitHub digest 均与本地一致；测试版清单及默认加速清单均已指向 0.2.7-beta+10，历史保留 0.2.6-beta+9，正式渠道版本不变。核验记录为 build/releases/0.2.7-beta-10/published-verification.json。

arm64-v8a 31.51 MiB、armeabi-v7a 28.70 MiB、x86_64 33.77 MiB，Windows 安装 EXE 19.06 MiB、便携 ZIP 22.68 MiB。产物与发布记录位于 build/releases/0.2.7-beta-10/，构建 / 检查日志位于 build/test_logs/release-0.2.7-*。Android 仍使用测试证书，Windows 未代码签名；Windows 安装器实际安装 / 卸载、Android 真机和 Linux 本轮未验收。

## 2026-10-28 应用音乐源管理与三步引导 UI 修改

应用用户提供的 sylphy_ui_redesign.zip：新增 MusicSourcesPanel 圆角来源卡片与状态开关、MusicSourceConnectionPage 独立连接 / 编辑表单、共享协议图标和 QuickStartWizard 三步引导（标语 → 来源选择 → 公共 API 配置）。Shell 保留实际登录、前台同步、账号身份校验、本地导入、缓存清理与删除入口。可选端口覆盖保留 URL 路径与查询，密码独立传递；编辑锁定协议和账号。API 校验错误在用户改正输入后自动清除。

此前未提交的通知权限 / 立即显示修复、设置页「音乐与存储」置顶和歌词行距修改均已保留。压缩包应用脚本先检查基线再运行，只改动预期 Shell 方法并加入四个 UI 文件；输入包保留在已忽略的 .private/ 目录中，没有覆盖业务服务、数据库或平台 Runner。

验证：格式检查及 flutter analyze 无问题；全量串行测试 209 项通过、5 项私密联调默认跳过（build/test_logs/redesign-unit.log）。新增连接表单测试覆盖可选端口 / 反向代理路径 / 查询保留、错误地址与端口、密码显隐、账号只读和取消返回。Windows 原生界面回归通过（redesign-native-ui.log），覆盖三步引导、取消连接后返回、本地导入方式选择、API 无效时不写配置 / 改正后提示清除 / 保存并重开读取、再次启动不显示引导、音乐源管理 / 添加 / 查看曲库以及原有设置和播放流程。已查看 320×640 / 360×800 的连接表单、来源选择、API 页和音乐源管理截图，位于 build/test_logs/ui/。Android 普通 lib/main.dart 入口 Debug 编译通过（redesign-android-build.log）。

本轮未在 Android 设备执行新界面流程，未运行 Linux 验收；Debug APK 仅用于编译检查，未生成新的 Release 交付包，未提交、推送或发布更新。

## 2026-10-28 播放页歌词预览行距

编辑播放页选中「歌词预览」后新增「歌词行距」滑块：1.00～2.50 倍、步进 0.05，默认 1.50。渲染和文字测量共用此行高，长句换行同时生效，空间不足时优先保留当前句并减少邻句。参数按组件保存在布局 JSON，支持实时预览、撤销 / 重做、保存应用、导入导出和重启恢复；旧 v1 / v2 布局缺少此属性时维持原有 1.50 倍。完整歌词页与全局字号保持原行为，不涉及数据库迁移。

验证：格式与 flutter analyze 检查通过；歌词预览、歌词页、布局模型 / 存储相关 26 项测试通过（build/test_logs/lyric-spacing-unit.log），覆盖实际文字间距、窄高度保留当前句、旧属性兼容、非法数值拒绝及持久化重开。Windows 原生编辑器回归通过（lyric-spacing-native.log）：实际拖动滑块、撤销 / 重做、预览值同步、保存后播放页应用，并保留原有编辑 / 播放隔离和响应式布局检查。已查看 build/test_logs/layout/editor-lyrics-spacing-mobile.png。未运行 Android / Linux 原生验证或生成 / 发布新安装包。

## 2026-10-28 首次授权后同步通知不可见修复

针对添加音源后的首次扫描反馈，确认入口已走前台同步，但原生通知权限 Channel 发起弹窗后立即返回，可能在用户点允许前启动并完成扫描。改为等待 onRequestPermissionsResult，合并并发权限请求，Activity 解绑时结束等待。同步与缓存通知在 Android 12+ 设置立即显示，避免短任务被系统延迟展示；渠道保持静默，不覆盖用户关闭通知 / 渠道的选择。原生诊断补充通知总开关、渠道启用与对应通知是否已提交。

验证：flutter analyze 无问题；通知桥接 6 项测试通过，新增权限选择未结束时不启动同步的回归。Android API35 专用 AVD 两组原生测试通过：从 addSource 登录合成 WebDAV，未选择权限时只有登录请求、没有开始扫描；实际点击允许后展开通知栏确认「风灵音乐 · 同步索引」可见，结束后通知移除；实际点击拒绝后仍完成首次扫描并停服。日志为 build/test_logs/lease-notification-android.log 与 lease-notification-denied-android.log，已查看通知栏截图 lease-notification-android.png。专用 AVD 的临时时限已恢复。

本轮未运行全量套件、Windows / Linux 原生回归或真机验证，未重新生成 Release 包、提交、推送或发布；已发布版本仍为 0.2.6-beta+9。

## 2026-10-28 发布 0.2.6-beta+9 Android / Windows 测试更新

在 0.2.5-beta+8 之后发布测试渠道更新，包含专辑 / 歌单 Cover Flow、歌单页靠左圆角「新建歌单」、搜索胶囊筛选，以及此前已提交的 Android 前台同步与 WebDAV 标签改动。Android 沿用现有测试证书，Windows 未代码签名；正式渠道保持 0.2.3+5。

源码提交 `b17c244`，标签 `v0.2.6-beta+9`，beta 清单提交 `ab1b56d`；发布页：https://github.com/ymltsh/SylphyMusic/releases/tag/v0.2.6-beta%2B9 。发布源码上通过 `flutter analyze --no-pub`、完整 `flutter test --no-pub`（204 项通过、5 项私密测试跳过）以及两项 Windows 原生界面回归（`build/test_logs/coverflow-release-ui.log`、`coverflow-release-playlist.log`）。构建使用测试签名与 `SYLPHY_RELEASE_VERSION=0.2.6-beta`，三种 APK 构建号为 2009 / 1009 / 4009，证书与 0.2.5 测试包一致。

六个远端资产（含 SHA256SUMS）的大小与 GitHub `digest` 均与本地记录一致；Android arm64 31.51 MiB、armeabi-v7a 28.65 MiB、x86_64 33.71 MiB，Windows EXE 19.04 MiB、便携 ZIP 22.66 MiB。默认加速地址的 Android / Windows / 便携 HEAD 均返回 HTTP 200，测试版清单与默认加速清单均指向 0.2.6-beta+9，正式清单仍为 0.2.3+5。Windows 可执行文件版本为 0.2.6-beta+9，便携 ZIP 包含 `sylphy_music.exe`、`flutter_windows.dll`、`data/icudtl.dat` 与许可证，`testzip` 无错误。本地记录与核验结果在 `build/releases/0.2.6-beta-9/`。

未在 Android 设备安装 / 覆盖升级，未执行 Windows 安装器安装 / 卸载验证；Android 仍为测试签名、Windows 未代码签名，不作为正式发布。

## 2026-10-28 专辑与歌单封面流（Cover Flow）

应用用户提供的 `sylphymusic-coverflow.patch`，新增不依赖第三方库的 `CoverFlowView`：中央封面按距离缩放 / 旋转 / 淡化，只构建当前位置附近最多约 7 项；水平拖动和点击共用同一个 `PageController`，点击中央项打开详情，点击侧边项先移动选中。音乐库专辑视图的筛选栏右侧增加 Cover Flow 图标切换，歌单页头增加网格 / 封面流切换；两者只保留在当前会话，不写入设置。专辑封面流继续使用现有每批 100 行的 SQL 分页和最多六批缓存，歌单封面取首曲封面，空歌单显示类型图标。说明见 [封面流](COVER_FLOW.md)。

原补丁的筛选栏 `SegmentedButton` 与当前胶囊筛选栏、窄屏布局及“分类切换不抽动”回归冲突，因此改为筛选栏右侧 40 dp 图标按钮：高度与胶囊一致，选中时切换图标，Tooltip 提示目标视图；其余补丁按原结构应用。修正补丁测试中 `WidgetTester.drag` 不支持的 `duration` 参数，改用 `timedDrag`。

验证：`flutter analyze --no-pub` 无问题；`test/cover_flow_test.dart` 1 项通过；Windows 原生 `integration_test/ui_refresh_test.dart`、`integration_test/playlist_refresh_test.dart` 通过（`build/test_logs/coverflow-ui.log`、`build/test_logs/coverflow-playlist-ui.log`），新增断言覆盖专辑封面流开启 / 中央点击进入专辑 / 切回列表，以及歌单封面流开启 / 中央点击进入歌单 / 切回网格。已查看 360×800 截图 `build/test_logs/ui/library-albums-cover-flow-mobile.png`、`build/test_logs/ui/playlists-cover-flow-mobile.png`。未执行 Android 设备验证或重新打包 APK。

## 2026-10-28 歌单页新建按钮与搜索分类胶囊栏

按用户要求，歌单页「新建歌单」改为 12 dp 圆角矩形并靠左放置，云同步图标保留在同一行右侧；搜索页「歌曲 / 专辑 / 艺术家」的分类切换由连接式 `SegmentedButton` 改为音乐库同款胶囊标签栏。抽出共享 `CapsuleToggle` / `CapsuleOption`（`lib/ui/capsule_toggle.dart`），音乐库沿用 `library-filter-*` 键、8 dp 圆角、16 dp 左对齐和横向滚动；搜索页使用 `search-filter-*` 键，选中态、图标和半透明底色与音乐库一致。

验证：`flutter analyze --no-pub` 无问题；Windows 原生 `integration_test/ui_refresh_test.dart` 与 `integration_test/playlist_refresh_test.dart` 通过（`build/test_logs/playlist-search-capsule-ui.log`、`build/test_logs/playlist-header-capsule-ui.log`）。新增断言验证搜索页不再有 `SegmentedButton`、3 枚 8 dp 圆角胶囊标签默认选中歌曲；歌单页「新建歌单」左距 16 dp、12 dp 圆角，云同步图标位于其右侧。已查看 360×800 搜索结果与歌单页截图 `build/test_logs/ui/search-mobile.png`、`build/test_logs/ui/playlists-grid-mobile.png` 及 320×640 双倍字号 `playlists-grid-large-text.png`。未执行 Android 设备验证或重新打包 APK。

## 2026-10-28 更新检查与本地发布工具

参考用户提供的 Mfuns Flutter `update.md`，新增设置页手动检查更新、实际安装包版本读取、正式 / 测试版独立清单、更新说明和平台下载入口。仅点击检查时发请求，加速地址失败回退 GitHub，12 秒 / 次、1 MiB 上限、同版 / 旧版不提示更新，下载链接限于本项目 HTTPS GitHub Release。新增 package_info_plus / url_launcher 并锁定依赖，重新生成插件注册与 Dart 许可证清单。

根目录 `release.py` 默认只本地准备：版本 / 构建号、检查、三 ABI APK、Windows 便携 ZIP / Inno Setup 安装程序、凭据内容扫描、SHA-256 与源码指纹记录。显式 `--publish` 才操作 GitHub，先上传草稿再公开，最后仅更新所选渠道清单；不自动提交或推送源码。要求正式签名、干净工作区和可在 GitHub 访问的源码提交，正式版继续受原发布门槛约束；复用产物校验摘要 / 源码，恢复发布核对远程文件且不覆盖已有资产。使用方法见根目录 [update.md](../update.md)。两份清单初始 latest=null，没有虚构已发布包。

验证：`flutter analyze --no-pub` 无问题；`test/app_updates_test.dart` 7 项通过；Python 发布工具 11 项测试通过（模拟 GitHub，覆盖纯预览、构建号、清单历史、资产损坏、上传失败 / 恢复、凭据内容扫描与正式版门槛）。Windows 原生 `ui_refresh_test.dart` 最终通过（`build/test_logs/release-system-ui-final.log`），核对手动更新页不自动检查、实际安装包版本显示及既有设置 / 播放流程；已查看 `build/test_logs/ui/settings-update-mobile.png`。Android Debug 构建通过（`build/test_logs/release-system-android.log`），未安装到设备。

未执行 GitHub 发布 / tag / 清单推送，线上接口需另行授权推送后才可使用。本机没有 Inno Setup 编译器和 `android/key.properties`，尚未实测安装程序编译、正式签名 Release 构建、安装升级 / 卸载或真实 GitHub 事务；未重新生成内部 Release 验收包，未执行 Linux 验收。


## 2026-10-28 设置页分类与二级配置

按用户提供的设置页讨论，将原 `app_shell.dart` 长列表抽到 `lib/ui/settings_page.dart`：一级页为四组八项分类入口及实时摘要；二级页分别处理播放、歌词、主题、背景、播放器外观、下载与缓存、关于。沿用原音乐源管理、缓存任务与逐曲清理页面、外观 / 播放 / 缓存持久化。补充已有唱片旋转偏好的入口；滑块放在标题下方，桌面内容限宽居中。返回目录后刷新缓存上限等摘要。

首轮原生回归发现旧缓存预算弹窗在退出动画结束前释放 TextEditingController；改为表单输入，并验证 1–200 GiB 的整数。最终 `flutter analyze --no-pub` 无问题；`test/appearance_test.dart` 8 项通过；Windows 原生 `integration_test/ui_refresh_test.dart` 通过（`build/test_logs/settings-ui-final.log`），覆盖设置分类、二级跳转、速度调整、歌词字号独立性、主题 / 背景 / 唱片旋转、预算保存、清理取消、缓存空间 / 任务 / 许可证入口和既有来源 / 播放流程。已查看 360×800、320×640 和 1200×850 截图，位于 `build/test_logs/ui/settings-*.png`。未执行 Android 设备验证或重新打包 APK / Release 包。


## 2026-10-27 音乐库分类切换抽动修复

根因是 `LibraryBrowser` 查询等待 / 失败时的布局没有播放数量行，筛选栏会短暂上移。统一加载 / 成功 / 失败的外层布局，保留播放数量行及来源 / 排序操作，等待期间显示「—」并禁用播放；加载完成只更新数量和列表，空结果仍显示 0。数量单行显示，不随位数改变行高。

验证：`flutter analyze --no-pub` 无问题；Windows 原生 UI 回归通过（`build/test_logs/stable-library-header-ui.log`）。测试用受控 SQLite 事务延迟查询，等待期间连续切换艺术家 / 歌曲 / 专辑，逐帧核对筛选栏与数量行坐标不变，播放禁用且来源入口存在；查询完成后数量正确、播放恢复，实际数量 3→1 及空来源 0 的坐标也保持一致。未执行 Android 设备验证或重新打包 APK。

## 2026-10-27 迷你歌词长句两行显示

歌词预览由固定单行槽位改为按实际文字高度排版：每句最多两行自动换行，优先保留当前句，再按剩余高度显示邻近句（最多五句），避免长句在第一行就被省略或第二行被裁切。保留迷你字号、时间高亮、同时间戳主句规则；极小文字框缩放容纳当前句，完整歌词页仍可查看超过两行的极长内容及译文。

验证：`flutter analyze --no-pub` 无问题；`test/lyrics_preview_test.dart`、`test/lyrics_view_test.dart` 共 9 项通过，覆盖长句两行完整显示、两倍字号 / 矮框边界及原有时间高亮 / 歌词页行为；Windows 原生界面回归通过（`build/test_logs/wrapped-lyrics-ui.log`），实际 Seek 到合成长句并核对两行无截断。已查看截图 `build/test_logs/ui/player-lyrics-preview.png`。Android 实机效果尚未验证。

已按用户要求执行 `tool/build_review.ps1`，生成包含本次长句换行及此前圆角分类 / 三分类播放行 / 无顶栏四项快捷操作 / 睡眠定时的内部 Release 包。arm64-v8a APK 29.22 MB、armeabi-v7a 26.17 MB、x86_64 31.52 MB，Windows ZIP 21.70 MB，位于 `build/internal-review/`；三种 APK 签名与全部产物 SHA-256 核对通过，使用本机测试签名。构建日志 `build/test_logs/wrapped-lyrics-build.log`，未安装到 Android 设备验证。

## 2026-10-27 播放页无顶栏与四项快捷操作

移除播放页 56 dp 顶栏，画布与编辑器同步使用完整安全区。第一个可见进度条上方固定显示睡眠定时、歌词页、收藏、更多；更多仍仅含音质信息与编辑播放页，没有进度条时使用底部回退行，删空自定义组件也能进入编辑器。调整内置迷你歌词高度，旧自定义歌词区与快捷行相交时缩短显示边界，进度条最小上边距给快捷行留出空间；下滑收起、左滑歌词保留。

用户确认定时含义为倒计时停止。新增应用级 `PlaybackSleepTimer`：15 / 30 / 45 / 60 / 90 分钟与取消，到期调用当前播放器暂停，切页不丢失；恢复前台复核截止时间，更换定时取消旧任务，应用关闭前取消并等待正在执行的暂停任务。不跨进程保存，Android 后台精确到点未在实机验收。收藏组件抽为共用控件并监听收藏变更。

验证：静态分析无问题；定时、布局及长文字相关测试 21 项通过；Windows 原生 `player_layout_test.dart` 与 `ui_refresh_test.dart` 分别通过（`build/test_logs/quick-actions-layout-final.log`、`quick-actions-ui.log`）。实际验证快捷行顺序 / 位于进度条上方、无顶栏、睡眠预设 / 取消 / 跨歌词页保留 / 到期暂停、收藏写入及反馈、编辑与空布局恢复、既有手势和 320×640 / 360×800 / 1200×850 布局。最终回归捕获并修复收藏同步监听的 setState 回调误返回 Future。已查看手机截图 `build/test_logs/ui/player-lyrics-preview.png`。本轮未执行 Android 设备验证或重新打包 APK。

## 2026-10-27 圆角筛选栏与分组播放全部

按用户修正，将音乐库筛选按钮调整为 8 dp 圆角矩形。歌曲、专辑、艺术家均显示同一播放全部操作行，数量对应歌曲数 / 专辑数 / 艺术家数；来源过滤、排序与升降序统一位于该行右侧，筛选栏保持在其下方靠左。专辑和艺术家播放全部通过 `CatalogQuery.songs` 获取完整匹配歌曲身份，保留来源、搜索、组内范围、排序和黑名单边界，避免只播放分组代表曲目。空分类显示 0 并禁用播放。

验证：`flutter analyze --no-pub` 无问题；`test/library_catalog_test.dart` 4 项通过，新增分组播放全部覆盖完整曲目、来源 / 搜索 / 黑名单、时长 / 年份排序和空来源；Windows 原生 UI 回归通过（`build/test_logs/rounded-library-ui.log`），实际点击专辑 / 艺术家播放全部并核对三首队列，验证数量 3 / 1、空来源 0 与禁用、无重复筛选 / 排序入口及圆角形状。已查看 `build/test_logs/ui/library-albums-mobile.png`。本轮未执行 Android 设备验证或重新打包 APK。

## 2026-10-27 移除播放页迷你歌词缩放按钮

移除迷你歌词右下角缩放按钮及播放页内直接拖动尺寸、自动保存布局的逻辑，尺寸统一在编辑器「歌词预览」内调整。`PlayerScene` 简化为渲染已保存布局，同时移除播放页为缩放手势设置的冲突保护；歌词点击、左滑进入完整歌词及下滑收起继续保留。

验证：`flutter analyze --no-pub` 无问题；Windows 原生界面回归通过（`build/test_logs/remove-lyrics-handle-ui.log`），断言按钮和提示均不存在，保留迷你歌词显示、点击打开完整歌词与原有页面操作。已查看实际截图 `build/test_logs/ui/player-light-cover-blur.png`，确认右下角无缩放覆盖按钮。

已执行 `tool/build_review.ps1` 重新生成包含本次及前面菜单 / 音乐库调整的内部 Release 产物：arm64-v8a APK 29.15 MB、armeabi-v7a 26.16 MB、x86_64 31.46 MB，Windows ZIP 21.69 MB；三种 APK 签名验证和全部 SHA-256 核对通过。日志 `build/test_logs/remove-lyrics-handle-build.log`，文件位于 `build/internal-review/`。使用本机测试签名，未执行 Android 设备安装验证。

## 2026-10-27 播放页更多菜单迁移

按用户要求，播放页「更多」仅保留音质信息和编辑播放页。移除该菜单内的导入歌词、查看完整歌词和完整歌词字号入口；完整歌词仍可点击歌词区或左滑打开，字号由歌词页内入口调整。

编辑器「专辑封面」新增唱片样式、唱片旋转；「歌词预览」新增迷你歌词字号选择；「页面」新增封面模糊开关；「布局操作」提供使用系统默认布局。沿用全局外观偏好与自动保存，面板明确说明，修改即时刷新预览，关闭编辑器后仍保留；组件布局继续保存并应用，放弃提示区分这两类修改。

验证：`flutter analyze --no-pub` 无问题；Windows 原生布局编辑器测试通过，覆盖两项菜单、编辑器内封面切换、旋转预览和持久化、默认布局恢复及原有编辑流程（`build/test_logs/editor-settings-ui.log`）。同次运行的第二组界面测试启动调试连接失败，单独重跑 `integration_test/ui_refresh_test.dart` 通过（`build/test_logs/editor-settings-ui-retry.log`），验证迷你歌词字号 20→24、模糊背景、关闭编辑器后生效及原有导航 / 歌词手势。已查看编辑器手机截图；本轮未在 Android 设备验证或重新打包 APK。

## 2026-10-27 音乐库方形筛选栏位置调整

按用户要求将歌曲 / 专辑 / 艺术家筛选按钮改为直角矩形，将筛选栏移到歌曲列表播放全部操作行下方，左侧边距 16 dp。保留横向滚动、主题选中色及原有分类切换；加载 / 失败状态仍可切换分类，其他列表不增加筛选栏。

验证：`flutter analyze --no-pub` 无问题；Windows 原生 `integration_test/ui_refresh_test.dart` 通过，新增断言检查三个按钮的直角形状、筛选栏位于操作行下方及左侧对齐，原有分类切换 / 来源过滤 / 排序 / 搜索继续通过。已查看 360×800 截图 `build/test_logs/ui/library-sort-mobile.png`。首次测试因系统临时目录拒绝访问而失败，改用项目 `.private/ui-test-temp` 后通过；日志 `build/test_logs/square-filters-ui-retry.log`。未执行 Android 设备验证或重新打包 APK。

## 2026-10-27 播放页长标题与歌手信息

修复自由画布文字固定允许三行、却没有按组件高度限制完整行数的问题。播放页和编辑器共用 `PlayerMetadataText`：标题按实际字体 / 系统文字缩放测量，最多两行；歌手 / 专辑单行，超长末尾省略。极矮文字框缩放容纳完整一行，文字限制在组件内；长按或桌面悬停可查看完整内容。

验证：`flutter analyze --no-pub` 无问题；`flutter test --no-pub test/player_metadata_text_test.dart test/player_layout_test.dart` 共 16 项通过。新增 Widget 测试覆盖长中英标题、歌手 / 专辑、完整行与省略、长按提示、手机 / 宽屏布局、两倍文字缩放及极矮自定义文字框的实际绘制边界。本轮未执行原生设备验证或重新构建安装包。

随后按用户要求执行 `tool/build_review.ps1`，已生成包含此修复的内部 Release APK：arm64-v8a 29.22 MB、armeabi-v7a 26.16 MB、x86_64 31.52 MB，位于 `build/internal-review/`；脚本同步更新 Windows ZIP（21.70 MB）。三种 APK 的 apksigner 签名验证和全部产物 SHA-256 核对通过，使用本机测试签名。日志：`build/test_logs/metadata-review-build.log`。本次未安装到设备验证。

日期：2026-10-27（Asia/Shanghai）。完整首版目标仍有效；当前没有声明正式版完成或发布。

## 已执行的验证

| 验证 | 结果 / 边界 |
|---|---|
| Flutter 升级 | 3.47.8 stable / Dart 3.13.7；依赖已升级并锁定 |
| Windows Debug | 已构建并实际启动 |
| Windows 原生集成 | SMTC 与托盘创建、本地音频播放通过 |
| Android Debug | 已构建并安装到独立 API 35 模拟器 |
| Android 原生集成 | 本地 + BR1 播放、P2、Seek、完整缓存字节一致性、独立 dataSync 缓存服务与任务完成通过 |
| 真实 Emby 只读 | 登录、索引、歌单读取、原始音频 Range 通过；模拟器真实 Emby 播放 / Seek 通过；凭据未输出或打包 |
| Navidrome 0.64.2 | 隔离本机实服；登录、索引、原始流、封面、临时歌单 CRUD / 重复条目 / 重排 / 改名通过 |
| libmpv 核心 | 合成 WAV 加载、Seek、切歌、队列移除、真正关闭后恢复暂停通过 |
| 标签 | 合成 MP3 / 96 kHz FLAC、内嵌封面、增量扫描通过 |
| 小屏 UI | 360×800 主界面与队列无布局溢出 |
| BR1 / 缓存 | 回环 HTTP 集成测试：完整落盘、Range / 后缀 / HEAD、强版本 P2 复用、版本变化重取、来源停用 / 删除拒绝票据通过 |
| 云歌单状态机 | 写入后响应丢失不重复追加、只读刷新保留草稿、重排冲突停写、跨账号拒绝、改名基线通过 |
| 传输 | 安全读有限重试、写入不盲目重放、401 / 重定向不重试、URL 子路径与凭据排除通过 |
| 200 首缓存任务 | 原子快照 / 去重、下载中断、调度器重建恢复、全部 READY 与抽查字节一致、TEMP 清理通过；合成小文件，不等同于真机长时间压力结果 |
| Emby 分页 | 无 TotalRecordCount 时完整翻页、歌单重复曲目保留、无效 / 不前进页拒绝刷新通过 |
| Emby 真实写入 | 经用户授权，仅新建 Sylphy Test 临时歌单；重复条目添加、重排、改名、删除及删除后列表核对通过，未操作已有歌单 |
| 大库索引 | 50,000 首合成元数据、250 首逐页落 SQLite 暂存、完整原子切换；失败 / 取消保留旧索引；重启丢弃残页并记住未完成来源重新扫描通过 |
| 数据库分页浏览 | 歌曲 / 专辑 / 艺术家、来源 / 搜索 / 黑名单过滤均在 SQLite 执行，每页 100 条完整元数据；队列只取身份；Windows 原生分页和分组进入通过 |
| 来源生命周期 | 停用先拒绝新工作并关闭索引、BR1 上游、P2 / 完整缓存及封面读取；READY、索引、歌单与任务快照保留。重新启用先验证身份和认证，再同步，保持暂停，显式播放刷新旧票据。真实 Emby Android 完整流程与 Windows 停用缓存保留通过 |

单元测试最近一次全量通过 **159 项**，另外五项真实环境测试默认跳过（包括 Emby 封面实服验证）。真实 Emby 写入已获准并另行执行通过。Windows / Android 原生集成另行执行；两平台均已实际通过 50,000 条元数据的逐页索引、末页 SQL 读取、艺术家聚合与分页界面导航，以及 WebDAV 原生端到端测试。Android 同时通过新索引链路连接真实 Emby 后播放 / Seek。

原生播放回归本轮复现并捕获到恢复时间断言的 1 ms 差异（预期 2000 ms，实际 1999 ms）；原生时间断言已改为 2 ms 容差，队列身份与暂停状态仍严格断言。其他负载与时序压力继续验证，不据重复通过宣称所有时序风险已关闭。最新完整单元测试输出保存在本机忽略目录 `build/test_logs/assets-full-suite.log`；原生 WebDAV 结果见同目录 `webdav-native-windows.log` 与 `webdav-native-android.log`。

## 已接入但仍需进一步压力 / 平台验证

- PR1：缓冲不足时后台读取让步、播放期间后台限速、接近切歌且缓冲充足时 P2 机会、同一资源共享与取消保护。
- 完整缓存 SHA-256 复核、资源元数据版本校验与 SQLite v1→v5 迁移。
- 来源编辑重新认证使用临时凭据命名空间，不把原 token 发送给新端点；Emby 核对服务器和用户身份。
- 自动重连受次数限制；鉴权 / TLS 明确拒绝时停止重连。
- 三端 CI 配置已加入，但还没有远端 CI 执行结果。

## 完整首版剩余闸门

1. 真实 Emby 的只读账号 / 权限撤销与双客户端并发冲突场景还需补充实服验证；临时歌单基本 CRUD 已完成。
2. 用户要求先本地运行，不推送 GitHub。Linux 本机构建和原生运行环境尚不可用；当前无可用 WSL 发行版且进程不是管理员，用户已明确暂缓 Linux 验收，先继续 Windows / Android；不安装 WSL。
3. Android 物理设备的锁屏、来电、永久 / 短暂失焦、耳机 / 蓝牙、OEM 省电、强停与系统时限验证。
4. 更多 OpenSubsonic 实现的兼容性、服务端歌词差异，以及弱网 / 200 首任务 / Seek / 崩溃时序压力测试。
5. 正式应用标识、签名与安装升级验证、原生 libmpv / FFmpeg 对应源码与许可证分发义务、公开仓库和完整发布包。

原生依赖已记录运行时版本、Windows DLL 摘要及上游构建开关，见 [NATIVE_DEPENDENCIES.md](NATIVE_DEPENDENCIES.md)。尚未据此宣称分发许可验收完成。

下一轮代码审查还需逐项核对规格中的安全签名播放重定向、重定向相关凭据边界等行为；当前实现中的严格拒绝重定向不能代替规格要求的合法播放跳转兼容性。剩余工程工作不限于外部设备验收。

调试 APK 或 Windows Debug 可用于内部验收，不能用它们代替以上完整正式版门槛。

## 当前内部验收输出

2026-10-27 WebDAV：新增来源类型与添加入口，安全存储 Basic 认证密码；按 Depth: 1 递归扫描，每 250 首提交暂存页，失败保留旧索引。对 href 做同源及根目录范围校验，支持编码文件名，同名歌词与目录封面，播放 / Seek / 完整缓存 / 缓存任务复用现有通路，收藏和本地歌单可引用 WebDAV 曲目；隐藏不支持的云歌单目标。首次显示文件名与目录分组，不在扫描时下载远程文件解析内嵌标签；已有完整缓存可读取内嵌歌词。修改地址须建立独立来源。

WebDAV 测试账号已完成真实服务器只读登录、递归扫描与音频 Range 验证。新增 5 项回归测试覆盖编码路径、目录遍历、503 首分批、属性与认证错误、越界 URL / 重定向拒绝及只读歌单能力。全套 66 项通过，4 项私密测试默认跳过，静态分析无问题；Windows 与 API 35 Android 原生 WebDAV 端到端测试均通过（同步、实际播放、Seek、READY 字节一致、歌词、本地歌单、停用保留缓存、重启用验证）。账号只在 Git 忽略目录，服务器仅执行 PROPFIND / GET，不做写入。设置与限制见 [WEBDAV.md](WEBDAV.md)。

2026-10-27 歌词修复：补齐原先直接返回 null 的 Emby 歌词读取。每次首次获取刷新单曲 MediaSources / MediaStreams，按 Subtitle 流索引读取：内嵌 text 使用 Stream.txt，外置 lrc 使用 Stream.lrc；兼容旧版 Videos 路径。认证保持请求头及配置的服务器前缀，不下载整首音频提取歌词。真实测试服务器已验证内嵌 text 返回有效歌词；失败与无歌词分别提示，允许重试，成功内容沿用本地歌词缓存。新增 4 项模拟服务回归测试，完整测试 61 项通过、3 项私密联调默认跳过，静态分析无问题；真实 Emby 只读联调另行通过，测试输出不含歌词、曲目名称或服务器地址。

- `build/internal-review/SylphyMusic-windows-release-internal.zip`：**21.72 MB**，完整解压后运行其中的 `sylphy_music.exe`，保留同目录数据与 DLL；原 Debug ZIP 为 55.4 MB。
- `build/internal-review/SylphyMusic-android-release-internal-arm64-v8a.apk`：**29.28 MB**，64 位 ARM；另提供 armeabi-v7a 26.22 MB 与 x86_64 31.59 MB；原通用 Debug APK 为 207.5 MB。
- Android 使用 Release 优化 / R8 / 图标裁剪并按架构拆分，本轮明确使用本机原测试证书签名，已核对两版证书摘要相同。API 35 x86_64 模拟器已通过 Debug→Release 直接覆盖安装、冷启动、主界面与无运行时错误日志检查；arm64 真机仍待验收。Windows Release 已实际启动。
- 同目录 `SHA256SUMS-optimized.txt` 提供文件摘要。输出由普通 `lib/main.dart` 构建，已覆盖集成测试入口，并检查已知 Emby URL / 密码未出现在已跟踪源码和包内容中。`tool/build_review.ps1` 可重复构建较小的内部验收包；Release 构建保留 pub / 插件注册生成步骤，避免集成测试开发插件残留。

Windows 主界面与来源管理已实际打开检查。测试用 Navidrome 和独立模拟器在验证结束后停止，私密资料继续留在 Git 忽略目录；此记录不表示当前仍有应用窗口运行。

## 开发文档维护

2026-10-27 补齐仓库 `AGENTS.md`、`ARCH.md`、`CONTRIBUTING.md` 和文档索引，工作目录外层增加工程入口。架构更新至 WebDAV、SQL 分页索引、来源生命周期、歌单意图日志和 TEMP / READY 缓存的实际实现。统一最新测试数量与日志位置，保留 Linux、真机及正式发布的未完成闸门。本轮只修改文档，核对相对链接、命令及代码路径，不重新构建安装包。


## 2026-10-27 UI 调整

依据用户提供的界面参考，在原 Flutter 工程中完成四项导航（首页 / 音乐库 / 歌单 / 我的）、右上角设置与设置内音乐源管理、可跳过并保存选择的首次连接引导、Material 3 首页卡片和专辑区、最近播放 / 收藏 / 下载入口、单行迷你播放器，以及封面 / 唱片与滑动歌词视图。外观设置持久化主题、背景和默认关闭的实验性磨砂效果。最近播放只保存最多 50 个 TrackRef，监听已开始的播放，写入排队并在关闭数据库前收尾；暂停队列恢复不生成记录。不改来源协议、数据库版本和缓存 / 云歌单状态机。

静态分析无问题；全量单元 / Widget 测试 66 项通过，4 项私密环境测试默认跳过（日志 `build/test_logs/ui-unit-suite.log`）。新增 Windows 原生 UI 集成测试通过：360×800 与 1200×850、浅色 / 深色、引导跳过后再次进入、四项导航、来源跳转、样式保存、合成 WAV 的真实播放记录、唱片 / 封面切换和滑动歌词，未发现布局溢出（日志 `build/test_logs/ui-native-windows.log`）。测试补获并修复首页首次从空库导入后专辑区未刷新问题；截图保存在 `build/test_logs/ui/`，只含合成数据。

本轮未执行 Android 设备验证或重新生成内部 Release 安装包，Linux 仍暂缓。参考讨论中的新增协议、独立文件夹浏览、智能歌单、唱片旋转、图标 / 语言设置和封面取色主题不在本轮实现范围，见 [界面说明](UI_REFRESH.md)。原有内部验收 ZIP / APK 不包含本轮 UI 变化。

Windows 既有原生桌面回归另行通过（`build/test_logs/ui-desktop-regression.log`）：原生媒体控制、本地 / 回环音频、Seek、完整缓存和新音乐库入口分页导航。此验证使用合成数据，未连接私人服务器。

集成测试结束后已重新构建普通 `lib/main.dart` Windows Debug 入口（`build/test_logs/ui-windows-build.log`）；可运行 `build/windows/x64/runner/Debug/sylphy_music.exe`，需保留整个输出目录的依赖。未重打包 Release ZIP / APK。


## 2026-10-27 UI 版 APK 打包

按用户「打包apk」请求，使用 `tool/build_review.ps1` 完成普通 `lib/main.dart` 入口的 Android Release / split-per-ABI 构建及内部打包。此次输出已包含上文 UI 改动，替代此前不含新 UI 的同名安装包：arm64-v8a **28.69 MB**、armeabi-v7a **25.60 MB**、x86_64 **31.00 MB**，位于 `build/internal-review/`。现有脚本同时刷新 Windows Release ZIP（21.49 MB）。

三份 APK 均通过 apksigner 验证，签名证书与此前内部 arm64 APK 一致；未配置正式签名文件，沿用现有本机测试证书。核对包名 `music.sylphy.sylphy_music`、版本名 0.2.0、最低 Android API 24 与各 APK 单一目标 ABI。使用本机既有私密凭据文件进行已跟踪源码和安装包解压内容扫描，未输出凭据；打包成功且全部产物 SHA-256 与清单一致。日志为 `build/test_logs/ui-review-build.log`，摘要为 `build/internal-review/SHA256SUMS-optimized.txt`。本轮未安装到 Android 设备或重新执行 Android 运行验收；此为内部验收包，尚非正式发布。


## 2026-10-27 独立搜索与歌曲连续滚动

主界面原同步图标替换为搜索入口，进入独立 SearchPage；音乐库移除搜索框，来源与排序功能保留。「同步所有来源」移至设置中的音乐源管理页，沿用原操作及忙碌禁用行为。搜索支持分类、来源过滤、250 ms 输入防抖、提交立即执行、清空与无结果提示。

歌曲视图移除上一页 / 下一页与页码，改为虚拟连续滚动；底层仍按每批 100 行读取 SQLite，滚动缓存最多六批，切换查询或索引版本时丢弃旧代次异步结果。播放全部和点播仍按完整查询建立 TrackRef 队列，未改成仅播放已加载批次。专辑和艺术家的聚合列表保留原分页。

验证：flutter analyze 无问题，全套 66 项单元 / Widget 测试通过、4 项私密测试默认跳过（`build/test_logs/search-unit-suite.log`）。Windows 三项原生集成均通过：五万首曲库跨批次跳转、末尾、返回顶部和请求中改查（`continuous-large-library.log`）；独立搜索、无匹配 / 清空、新按钮位置与小屏布局（`search-ui-native.log`）；本地 / 回环播放、Seek、缓存及连续歌曲列表（`continuous-desktop.log`）。以上日志均在 `build/test_logs/`；新搜索和音乐源页截图在 `build/test_logs/ui/`，仅含合成数据。Android 本轮未安装验收。

已使用 `tool/build_review.ps1` 更新普通主入口 Release APK，包含此次搜索 / 同步入口和连续滚动改动：arm64 28.69 MB、32 位 ARM 25.63 MB、x86_64 31.00 MB，同目录 Windows ZIP 21.50 MB。已通过既有私密值内容扫描、三份 APK 签名验证（证书与旧内部包一致）及全部产物 SHA-256 核对。日志 `build/test_logs/search-review-build.log`；沿用本机测试签名，仍为内部验收包。


## 2026-10-27 歌曲数量行与排序位置

音乐库歌曲列表将来源过滤、排序和升降序按钮移至播放操作行右侧，移除分类下方原按钮行，保留播放图标，文字只显示歌曲数量数字。复用的搜索 / 分组歌曲列表和歌单曲目列表也移除「播放全部 · … 首」文案；播放动作保持不变，播放图标保留 Tooltip。专辑 / 艺术家聚合视图保留原排序入口。

静态分析通过，Windows 原生 UI 集成通过（`build/test_logs/sort-row-ui.log`），确认 360×800 下数量与排序同排、排序可操作且无溢出；3 项播放 / Widget 回归通过（`sort-row-playback.log`）。截图 `build/test_logs/ui/library-sort-mobile.png` 使用合成数据。未新增业务能力或更改曲库查询、音频和缓存逻辑。

数量行的过滤 / 排序调整已通过 `tool/build_review.ps1` 重建并打包普通入口 Release：arm64 28.69 MB、32 位 ARM 25.63 MB、x86_64 31.00 MB。内容扫描、三份 APK 签名及产物摘要核对通过，使用现有内部测试签名；日志 `build/test_logs/sort-row-review-build.log`。本轮未执行 Android 真机安装验证。

## 2026-10-27 Emby 封面修复

真实服务器抽样 250 首中 248 首声明歌曲自身的 Primary 图片，原实现却优先请求 AlbumId，实服复现专辑图片 404、单曲图片 200。现按图片所属对象选择 ID 与 tag，兼容旧索引行与带 / 不带反向代理前缀的配置；缺图 404 可回退专辑 / 继承图，鉴权失败不当作缺图回退。封面请求与磁盘缓存 key 加入图片版本，界面在 tag 更新时换图，失败结果不永久缓存；下载最多六路并发，并增加响应超时。

7 项新增回归通过，覆盖歌曲 / 专辑 / 继承图片身份与 tag、URL 前缀、404 与鉴权边界、失败重试、缓存重用、版本变化和并发限制。真实服务器随机 8 张图片下载与 Flutter 图片解码通过；未记录私有地址、图片身份或内容。完整回归 73 项通过、5 项私密环境测试默认跳过，静态分析通过，Windows 原生 UI 集成通过。日志位于忽略目录 build/test_logs/cover-fix-suite.log、emby-cover-live.log、cover-fix-windows-ui.log。本轮 Android 先做优化包构建，未据此声明真机封面验收。

封面修复已由 tool/build_review.ps1 重建普通入口优化包：arm64 28.69 MB、32 位 ARM 25.63 MB、x86_64 31.00 MB，Windows ZIP 21.50 MB。两组既有测试凭据的私密值内容扫描通过，三份 APK 签名及全部产物 SHA-256、Windows ZIP CRC 均通过；日志 build/test_logs/cover-fix-package.log。沿用本机内部测试签名，未进行远端推送。


## 2026-10-27 手势条、自定义外观与列表补充

查阅 Flutter / Android 官方 edge-to-edge、SystemUiOverlayStyle、SafeArea 与 NavigationBar 文档后，新增统一 AppSystemBars：Android 启动显式启用边到边，手势导航透明并按主题切换图标明暗；三键导航保留系统对比度保护。API 29+ 原生昼夜启动主题同步透明系统栏。首页导航栏只避让一次底部 Insets，全屏播放器、队列弹层、独立页面及列表补齐安全区。未隐藏手势条、未降低 targetSdk 或退出 Android 15 / 16 的 edge-to-edge。

新增主题色与背景图设置。默认实际主色 #5094B2，支持预设 / HEX 输入和恢复默认；背景图保持比例自适应铺满，**仅首页、音乐库、歌单、我的四个一级页面使用**，其他路由保持主题 Surface。图片在应用数据目录保存受管副本，最长边归一化到 2048，源文件上限 40 MB；替换失败保留原背景，清理不删除用户原始图片，关闭数据库前等待写入完成。颜色对话框控制器由自身生命周期管理，修复应用新主题时退场动画中使用已释放控制器的问题。

首页左上角仅显示应用名：系统为英文时 `Sylphy Music`，其他语言「风灵音乐」；另三个一级页面显示对应页名，移除原副标题，并监听系统语言变化。专辑、艺术家与歌曲统一采用虚拟连续滚动，保持每批 100 行与最多六批缓存，不再显示任何分页栏。

验证：静态分析无问题；77 项单元 / Widget 测试通过，5 项私密联调默认跳过（`build/test_logs/appearance-full-suite.log`，包含工作区封面相关回归）。新增 appearance_test 覆盖主色、偏好恢复、原文件独立、坏图失败保留、图片比例 / 尺寸与串行清理。Windows UI 原生集成通过中英文系统名称、一级页面名和 360×800 / 宽屏布局（`appearance-ui-windows.log`）；五万首歌曲及 200 组专辑 / 艺术家连续列表跨 100 行边界、末尾和返回顶部通过（`continuous-all-groups.log`）。日志均位于 build/test_logs。

独立 SylphyTest_API35 模拟器上的手势、三键导航原生测试均通过（`build/test_logs/edge/gesture.log`、`threebutton.log`）：浅色 / 深色、主题颜色应用 / 恢复、自定义背景和设置 / 搜索 / 播放等路由排除、原生软键盘、全屏播放和队列弹层。实测 Insets 及 NavigationBar 总高度，Seek 控件在安全区内；从 Android 合成器获取含系统栏的合成数据截图，未涉及私人音乐库。测试结束恢复原手势模式并关闭本轮启动的模拟器。物理设备、更多系统版本和厂商系统仍待验收。

说明与资料链接：[Android 系统栏](ANDROID_SYSTEM_BARS.md)、[自定义外观](APPEARANCE.md)。

补充：空来源的数量行现在显示 0，并保留过滤与排序入口，可直接切回全部来源；Windows UI 集成已覆盖。Appearance 关闭放在媒体 / 索引等生产任务停止之后、SQLite 关闭之前。Windows 构建曾因并行单元测试占用 sqlite3.dll 失败，已结束占用后串行重建并通过，未删除数据或重建 Runner。

最终补查后 7 项外观 / 原生播放回归通过（`appearance-final-regression.log`）；重新使用 `tool/build_review.ps1` 生成普通主入口 Release 包，三份 APK 均包含本轮所有外观、标题与列表改动：arm64 28.82 MB、32 位 ARM 25.68 MB、x86_64 31.06 MB，Windows ZIP 21.52 MB。安装包内容扫描、三份 APK 签名验证及 SHA-256 清单核对通过，证书与原内部包一致；日志 `build/test_logs/appearance-review-build.log`。沿用本机内部测试签名，未声明正式发布或物理设备验收完成。

## 2026-10-27 播放失败提示改为短暂吐司

移除迷你 / 完整播放栏的常驻错误文字和重试行，应用根页面统一显示浮动吐司，3 秒自动消失；播放恢复后提前收起，重复状态更新不续时或排队，不拦截点击，切换路由仍只有一个通知。通知使用概括文本，不显示含私人连接信息的原生错误明细。播放器在实际播放进度恢复时清空旧 error；失败后再次点击播放重新加载媒体，原有自动重连与连续失败停止规则保留。

4 项吐司 Widget 回归覆盖自动消失、恢复收起、重复与快速事件、路由 / 点击和卸载定时器清理，新增真实 libmpv 进度恢复清错回归；相关 8 项回归通过。完整测试 82 项通过、5 项私密环境测试默认跳过，静态分析通过。日志 build/test_logs/playback-toast-regression.log 与 playback-toast-suite.log。本轮未据桌面测试声明 Android 真机通知验收。

已重新生成普通入口优化包：arm64 28.82 MB、32 位 ARM 25.68 MB、x86_64 31.06 MB、Windows ZIP 21.52 MB。两组测试凭据私密值扫描、三份 APK 签名、产物 SHA-256 和 Windows ZIP CRC 验证通过；日志 build/test_logs/playback-toast-build.log。沿用内部测试签名。

## 2026-10-27 沉浸播放页与歌词完善

依据用户补充的 P2 设计说明，播放页改用全屏封面模糊背景、深色渐变与局部深色主题，大封面 / 唱片成为主视觉。移除全屏底部重复的歌曲信息条，仅保留进度、时间、五项播放控制与队列，音质信息移入更多菜单。手机支持点击与滑动切换封面 / 歌词，歌词视图顶部保留小封面与曲目信息；宽屏并排展示。沿用沉浸背景开关与用户主色，未新增调色板依赖、定时关闭或唱片旋转。

歌词改为按实际文本高度定位和完整换行，同时间戳原文 / 译文合并、空行间奏提示、小 / 标准 / 大字号、系统字体缩放与减少动画；手动滚动暂停跟随，通过「回到当前」恢复，点击歌词仍可 Seek。保留无时间轴文本阅读、错误重试及每曲导入；原生新增测试捕获并修复重试 setState 回调意外返回 Future 的问题。

验证：静态分析无问题；歌词解析 / Widget 与既有播放通知 9 项相关回归通过（build/test_logs/immersive-regression.log）。Windows 原生 UI 集成通过 360×800、1200×850、合成封面与双语歌词、无歌词重试、手动浏览 / 回到当前、单一队列入口与无布局异常（immersive-ui-windows.log）。已查看合成截图 build/test_logs/ui/player-lyrics-mobile.png 与 player-immersive-wide.png。随后重新构建普通 lib/main.dart Windows Debug 入口成功（immersive-windows-build.log）。本轮未执行 Android 设备测试、全量单元测试或重新生成 Release ZIP / APK；现有内部安装包尚不包含本轮变化。

## 2026-10-27 可视化播放页编辑器

按用户指定的共享设计说明实现组件注册表、版本化布局数据、渲染器与独立编辑草稿；不新增播放器实例或替换来源 / 缓存 / 云歌单通路。入口为播放页「更多 → 编辑播放页」。提供沉浸封面、歌词优先和个人模板；分区内拖动、右下角缩放、4 / 8 dp 网格开关、中心 / 边缘 / 等距参考线，最多 80 步撤销 / 重做。组件可添加、锁定、隐藏、删除，支持区域、宽高、透明度、字号、对齐、预设颜色、封面圆形 / 圆角及背景样式；手机与宽屏自适应分区，小窗口保留最小组件尺寸并滚动。

保存并应用、另存、改名、恢复默认、JSON 导入导出已接入；模板与当前选择在现有 SQLite settings 一次写入，不修改 schema，关闭数据库前等待队列完成。导入先到草稿，拒绝未知版本 / 组件、越界数值、重复 ID 和超过 128 KiB 的文件。坏的持久化数据不自动覆盖。固定顶栏不受布局删除影响，删空也能重新编辑或恢复系统默认。编辑和预览均屏蔽组件指针操作，避免误触播放 / Seek。配置不包含曲目身份、音乐源、文件路径和凭据。

补测发现本地旁挂 LRC 会被 mpv 重复作为外部字幕自动加载，在 Windows 扩展路径上报「无法打开外部文件」，触发已有错误处理并暂停播放。现关闭 mpv 的 sub-auto，歌词继续由应用解析；同一合成 WAV + LRC 的原生测试已覆盖正在播放时进入编辑器、保存切换模板与暂停后进度保留。另修复浅色主界面进入深色播放页后图标继承黑色的问题，背景配置统一覆盖到顶栏与内容区。

本轮使用现有 ChangeNotifier、SQLite 和 Flutter 手势能力，不新增布局拖动 / 状态管理依赖。解除分区自由画布、复杂图层、逐字歌词、圆形进度、旋转封面、在线主题分享等后续阶段尚未实现。详见 [播放页布局编辑器](PLAYER_LAYOUT_EDITOR.md)。

本轮最终验证：静态分析无问题；全量单元 / Widget 测试 **93 项通过、5 项私密环境测试默认跳过**（build/test_logs/layout-full-suite.log）。Windows 原生编辑器集成通过：360×800、1200×850、320×640，拖动 / 缩放、撤销重做、编辑与预览不误触播放 / Seek、自定义控件正常开始播放、播放中编辑并切换模板不中断、模板恢复、删空组件后恢复入口及歌词显示（layout-native.log，最终运行未启用 headless）。既有 Windows UI 集成也通过（layout-ui-regression.log）。检查了合成截图 build/test_logs/layout/editor-selected-mobile.png、editor-wide.png 与 custom-lyrics-mobile.png；截图无私人曲库内容。已成功重建普通 lib/main.dart Windows Debug 入口（layout-windows-build.log），格式和 diff 空白检查通过。

初次播放中编辑测试揭示的旁挂 LRC 原生加载错误已修复并由最终同一用例通过验证；不把早期失败或 headless 排查运行计为最终通过。JSON 模型 / 存储的往返、非法文件拒绝及保留旧数据已有自动化覆盖；系统文件选择器的完整人工导入导出流程与 Android 设备尚未验收。未重新生成 Release ZIP / APK，现有内部安装包不含本轮编辑器。

按用户明确要求执行 `flutter build apk`：普通 `lib/main.dart` Release 通用 APK 构建成功，输出 `build/app/outputs/flutter-apk/app-release.apk`，84,967,215 字节（Flutter 显示 81.0 MB），包含本轮播放页编辑器与歌词 / 播放修复。缺少正式 key.properties，沿用既有 SYLPHY_INTERNAL_DEBUG_SIGNING 本机测试签名；进程内临时启用后恢复。apksigner 验证通过、ZIP CRC 完整性通过，包含 arm64-v8a / armeabi-v7a / x86_64 三种 ABI，未发现私密目录、签名配置或密钥文件被打包。日志 build/test_logs/layout-apk-build.log。本次未安装到设备，也未覆盖 build/internal-review 的旧分架构 APK。

## 2026-10-27 合并随机与循环模式

用户要求将随机播放、列表循环、单曲循环合并。迷你播放器、默认全屏与自定义布局统一使用 PlaybackModeButton，一个按钮依次切换列表循环 → 单曲循环 → 随机播放 → 列表循环，图标和 Tooltip 随状态更新。全屏主播放按钮保留居中，原独立随机 / 循环两个入口移除，编辑预览仍不可操作播放。

PlaybackCoordinator 一次更新 repeat / shuffle / order，三种状态互斥，随机模式循环整个队列；切换不加载新媒体，不改变歌曲、进度和暂停状态，保留历史。退出随机恢复自然顺序。旧顺序模式和缺省配置读取为列表循环，旧随机 + 单曲循环组合按单曲循环恢复；队列身份、当前索引、进度与历史继续保留，保存随机排列并在重启后恢复，无数据库 schema 变更。

验证：静态分析无问题，完整单元 / Widget 测试 98 项通过、5 项私密环境测试默认跳过（build/test_logs/mode-full-suite.log），新增覆盖三态循环、旧配置兼容、模式切换期间音频身份 / 进度 / 暂停状态保持、随机排列重启恢复及列表末尾回到第一首。Windows 原生编辑器 / 播放页交互通过（mode-native.log），验证默认与自定义布局共用单一入口、三态切换、保存和播放中编辑。主界面原生回归首次进程提前退出、未完成；独立重新运行通过 360×800 与宽屏布局及迷你播放器（mode-ui-regression-retry.log），不把首次中断计作通过。

已更新普通主入口通用 Release APK：build/app/outputs/flutter-apk/app-release.apk，约 81.0 MiB，包含合并后的模式按钮。沿用本机内部测试签名，签名验证及 ZIP 完整性检查通过；未发现私密目录或签名密钥文件被打包。普通 Windows Debug 主入口同步重建成功。日志 mode-apk-build.log 与 mode-windows-build.log。Android 本轮仅构建、未在设备上安装验证；旧 build/internal-review 分架构包未刷新。

## 2026-10-27 Emby 歌词时间轴修复

按用户提供的 API 与指定凭据执行只读排查：内嵌 Codec=text、IsTextSubtitleStream=true，Stream.txt 返回纯文本而无时间轴，Stream.srt 返回 55 条带起止时间的字幕；该样本的 LRC / VTT 转换为空、JSON 格式返回 404。实际响应仅保存在 Git 忽略的 .private，未把地址、账号、Token、媒体身份或歌词加入源码、公开日志和安装包。

EmbyAdapter 改为文本流优先 SRT 转换，外置 LRC 仍优先原格式；兼容原 Items / Videos 路径，不支持格式回退 TXT，保留认证头、前缀、禁止重定向与 1 MiB 上限。统一转换小时 / 分钟 / 秒 / 毫秒为 LRC，保留同时间译文顺序，间奏按字幕结束时间解除上一句高亮。旧 Emby 纯文本缓存尝试升级至 emby-timed-v2，旧文件保留为失败 / 无新内容时的回退；新手动导入独立保存并优先使用。旧版无来源标记的手动纯文本仍保留原件，但若需继续覆盖服务器时间轴，需重新导入一次。详情见 [Emby 歌词](EMBY_LYRICS.md)。

验证：格式和静态分析通过；109 项单元 / Widget 测试通过、5 项私密环境测试默认跳过（build/test_logs/emby-timing-full-suite.log）。包括 15 项歌词协议 / 解析 / Widget 回归和 5 项缓存迁移 / 导入 / 失败保留测试；私密实服 SRT 快照逐条验证 55 个起始时间全部保留，规范化后 62 行（含间奏空行），不输出实际歌词（emby-timing-snapshot.log）。Windows 原生编辑器 / 播放页回归通过（emby-timing-native.log）。实服验证为实际响应抓取加本地快照对照，不宣称在 Android 上完成真实服务器播放验收。

已重新生成普通 lib/main.dart 通用 Release APK（build/app/outputs/flutter-apk/app-release.apk，约 81.0 MiB），三个 ABI 的 libapp.so 均核对包含本轮时间轴缓存版本。沿用本机内部测试签名，apksigner、ZIP CRC 和指定凭据的源码 / 包内私密值扫描通过，凭据未输出。Windows Debug 普通入口同步构建成功。日志 emby-timing-apk-build.log、emby-timing-windows-build.log。本轮未在 Android 设备安装验收，也未刷新 build/internal-review 旧分架构包。

## 2026-10-27 播放控件、唱片旋转与自定义歌词分页

播放 / 暂停按钮改为支持圆角矩形，自定义布局的「播放控制」面板可调圆角与按钮宽度。队列入口移入模式、上一首、播放 / 暂停、下一首同一排控制区，保留主按钮居中；默认布局移除原下方重复队列按钮。内置模板删除独立队列元素，旧版内置 bottom/queue 元素读取时合并，另行插入或移动到其他区域的用户元素保留。

圆形封面新增「播放时旋转」属性并随模板保存；系统默认唱片样式可在更多菜单设置旋转，偏好持久化。统一 RotatingCover 按播放状态约 20 秒一圈，暂停保持角度、继续后接着旋转，切歌重置；编辑预览、方形封面、隐藏页面及减少动画模式不转。此实现不驱动或重建播放内核。

修复自定义布局直接进入 Renderer 而失去封面 / 歌词 PageView 的问题：正常展示始终支持从右向左进入独立歌词页，反向返回。两页共享一个固定控制区，横向滑动不移动进度与播放按钮，也不影响歌曲或播放进度。是否能进入歌词页不再取决于模板里有没有歌词组件。独立歌词页复用既有获取和时间轴逻辑。

当前验证：静态分析无问题；113 项单元 / Widget 测试通过、5 项私密环境测试默认跳过（build/test_logs/player-polish-full-suite.log）。新增测试覆盖旋转 / 暂停 / 恢复 / 隐藏 / 减少动画、旋转偏好恢复、按钮样式保存和旧布局兼容。Windows 原生播放页编辑器集成通过圆角和宽度实际渲染、保存后右向左滑动进歌词及返回、控制区固定不动、队列打开、播放和编辑恢复（player-polish-native.log）。本轮未做真实服务器联调，未读取私人曲库或凭据。

既有 Windows 主界面 / 默认播放器原生回归也通过（player-polish-ui.log），合成数据截图已查看 build/test_logs/layout/custom-swiped-lyrics.png。已重建普通 lib/main.dart Windows Debug 与通用 Release APK（约 81.0 MiB），APK 三种 ABI 均包含本轮按钮宽度和自定义分页实现，测试签名、ZIP 完整性与私密目录 / 密钥文件排除检查通过；日志 player-polish-apk-build.log、player-polish-windows-build.log。保留此前 Emby 时间轴和合并播放模式修复。Android 仅构建，未进行设备安装 / 手势 / 旋转验收，旧 build/internal-review 分架构包未刷新。


## 2026-10-27 播放页视觉审计落地与控制尺寸

按用户确认的审计方案统一默认与自定义播放页：顶栏保留收起 / 更多，将封面切换、歌词导入和字号移到更多；共用 PlayerBackdrop、PlayerProgress、PlayerControls，统一主题强调色、遮罩、时间与滑轨边界及主按钮默认尺寸。手机使用双圆点提示，保留右向左歌词手势、固定控制区和队列；歌词页统一小封面信息，隐藏常驻状态工具栏与定时歌词桌面滚动条。

同时间戳第一行为主句，后续行按约 65% 字号、较低字重和亮度显示，不自动推断语言；TextPainter 与富文本渲染使用相同度量，焦点调整至可用高度约 43%，保留长句换行、大字体、手动浏览 / 回到当前及 Seek。新模板收拢信息间距；旧自定义竖屏坐标保留。宽屏将封面与信息集中到左侧，右侧歌词、左下控制，内容最大宽度 1200；可选 wideFrame / wideRegion 使宽屏编辑独立保存，旧 v1 文件无需重写。编辑器仅突出所选区域，缩放手柄保持约 36 dp 屏幕尺寸。

按追加要求，播放控制组件新增按钮间距 0–32 dp、主播放按钮高度 48–96 dp，保留独立宽度 56–96 dp 和圆角；图标随主按钮高度变化，两侧按钮尺寸保持稳定。控件不随外框整体缩放，窄屏只限制实际间距而保留保存值，较大主按钮增加控制区最小高度。props.playHeight / controlSpacing 随模板保存，旧布局默认高 64 / 间距 12，不改数据库 schema。

验证：静态分析无问题（audit-analyze.log）；115 项单元 / Widget 测试通过、5 项私密环境测试默认跳过（audit-full-suite.log）。覆盖双语层级、实际文字高度与大字体焦点、模板旧值兼容 / 非法值拒绝、宽屏分组及独立坐标保存。Windows 编辑器原生回归通过 360×800、1200×850、320×640，验证主按钮实际 88×80 尺寸、间距变化和窄屏限制、96×96 按钮、固定队列位置、滑动歌词、播放中编辑与保存（audit-layout-native.log）。已检查合成截图 custom-lyrics-wide.png、custom-swiped-lyrics.png、custom-controls-small.png 和编辑器截图。

默认播放器 / 主界面原生回归首次测试进程提前退出、未完成（audit-ui-native.log）；独立重跑通过（audit-ui-native-retry.log），包括方形 / 唱片菜单、双语歌词、回到当前、手机 / 宽屏和单一队列入口；不将首次中断计作通过。检查了新的 player-lyrics-mobile.png 与 player-immersive-wide.png。随后普通 lib/main.dart Windows Debug 构建成功（audit-windows-build.log）。本轮未访问真实服务器或凭据，未做 Android 设备验证，未重新生成 APK / Release ZIP；现有 APK 不含此次视觉收敛与间距 / 高度配置。

## 2026-10-27 播放页区块与歌词预览

播放页默认布局改为封面、歌词信息、播放控制三个可切换顺序的区块，移除封面 / 歌词指示点。歌词信息区按可用高度显示最多三句当前歌词，点击打开完整歌词；歌词字号 20 / 24 / 28 和区块顺序写入 settings 持久化，可在设置和播放页「更多」调整。播放页按钮、进度和歌词高亮从当前封面提取色板，失败时回退主题色；播放页支持下滑退出。外观新增纯色背景，未设置背景图时默认启用，浅色 / 深色模式分别使用白 / 黑；已有背景图保持显示，重新选择背景图会关闭纯色模式。

验证结果：\dart format\ 与 \lutter analyze\ 通过；\lutter test --no-pub test/appearance_test.dart test/lyrics_preview_test.dart test/cover_palette_test.dart test/lyrics_view_test.dart test/player_layout_test.dart\ 通过；\lutter test integration_test/ui_refresh_test.dart -d windows\ 与 \lutter test integration_test/player_layout_test.dart -d windows\ 通过。截图输出到 \uild/test_logs/ui/player-disc-mobile.png\、\player-zones-mobile.png\、\player-lyrics-preview.png\、\player-immersive-wide.png\。本轮未重新构建 Android / Windows 发布包，正式签名与真机验收门槛不变。

## 2026-10-27 播放页全画布收敛、统一唱片与唯一歌词页

按用户反馈解决播放页审计问题，并把编辑方式收敛为整页自由画布：

- 播放页不再划分封面区、歌词信息区、播放控制区，也不再提供区块顺序。系统默认页和自定义模板共用同一个 `PlayerLayoutRenderer`；编辑器直接载入当前实际页面，按当前安全区、顶栏和最大 1200 dp 内容宽度计算画布，使用封面取色主题、当前封面和真实歌词。
- 编辑器提供 9 宫格（3×3）与 16 宫格（4×4）辅助线及吸附，移除了 4 / 8 dp、区域边框、分区比例和所在区域选项。封面只保留「大小」，圆形边界、选择框和缩放手柄使用同一正方形。
- 唱片形状与旋转改为 `Appearance` 的全局设置；新增共享 `PlayerCover`，播放页、编辑器预览、歌词页头图和折叠迷你播放器共用同一封面组件与形状。唱片模式统一使用黑胶纹路、中心孔、阴影和旋转；编辑器不再显示与播放页不一致的独立圆形开关。
- 完整歌词收敛为唯一的 `LyricsPage`：歌词预览或「更多 → 查看完整歌词」打开同一页面，带返回键、字号菜单、播放进度和控制；删除了底部弹层与自定义布局 PageView。歌词预览最多显示五行，只取每个时间戳的主行，不再把原文 / 译文用 `·` 拼成一行后截断。
- 修复播放键对比度：移除页面级 `iconTheme`，播放 / 暂停按钮显式使用 `primary / onPrimary`，自定义背景色按亮度选择前景。
- 布局数据升级为 v2 全画布格式，存储 key 仍为 `player_layouts_v1`，容器版本 2。v1 区域坐标在读取时按旧公式迁移为整页坐标，并生成宽屏坐标；旧文件在用户保存或选中模板前不覆盖。逐元素 `circle` / `rotate` 不迁移，统一由全局外观控制。
- 设置不再把全局歌词字号写回模板逐元素字号；全局面板只更新歌词预览、完整歌词页和布局中的歌词预览。

验证：

- `flutter analyze` 无问题（`build/test_logs/refactor-analyze-final.log`）。
- 全量单元 / Widget 测试 **127 项通过、5 项私密环境测试默认跳过**（`build/test_logs/refactor-full-suite-final.log`）。
- Windows 原生 UI 集成通过 360×800 / 1200×850：统一完整歌词页、返回、预览与重试、方形 / 唱片切换、主播放键前景为 `onPrimary`、封面取色和下滑退出（`build/test_logs/refactor-ui-final.log`）。
- Windows 原生布局 / 编辑器集成通过 360×800 / 1200×850 / 320×640：从当前唱片页进入编辑器仍为唱片、保存后保持、封面与圆形选择边界重合、9 宫格显示、拖动 / 缩放 / 撤销重做、保存切换模板不中断播放、320 小窗完整歌词页无溢出（`build/test_logs/refactor-layout-native-final.log`）。
- 合成截图：`build/test_logs/layout/editor-mobile.png`、`editor-selected-mobile.png`、`custom-player-mobile.png`、`build/test_logs/ui/player-lyrics-mobile.png`、`player-immersive-wide.png`；均只含合成曲目和封面。
- 已重新构建普通 `lib/main.dart` Windows Debug 入口（`build/test_logs/refactor-windows-build.log`）。正式签名、真机与发布门槛不变。

## 2026-10-27 内部验收打包

按用户「打包」请求，使用 `tool/build_review.ps1` 从普通 `lib/main.dart` 入口重新构建 Android Release / split-per-ABI 与 Windows Release，并通过 `tool/package_review.py --mode optimized` 打包。使用现有私密测试凭据文件做内容扫描，未输出文件内容；扫描通过，未发现凭据进入已跟踪源码或包内容。

- `build/internal-review/SylphyMusic-android-release-internal-arm64-v8a.apk`：**29.43 MB**，versionCode 2002，仅 arm64-v8a。
- `build/internal-review/SylphyMusic-android-release-internal-armeabi-v7a.apk`：**26.40 MB**，versionCode 1002，仅 armeabi-v7a。
- `build/internal-review/SylphyMusic-android-release-internal-x86_64.apk`：**31.74 MB**，versionCode 4002，仅 x86_64。
- `build/internal-review/SylphyMusic-windows-release-internal.zip`：**21.84 MB**，完整解压后运行 `SylphyMusic/sylphy_music.exe`。
- 追加的右向左滑动歌词、迷你歌词缩放手柄、浅深色跟随、可选封面模糊、54 dp 底栏、独立迷你歌词字号与音乐库胶囊筛选已重新打入上述四份产物；包内容重新扫描、签名和 SHA-256 核对通过。
- 包名 `com.ymltsh.sylphymusic`，versionName 0.2.0，minSdk 24，targetSdk 36；三份 APK 均由本机 Android Debug 测试证书签名，签名方案 v2，三份证书 SHA-256 一致。没有正式 `key.properties`，因此仍不是正式发布包。
- 三份 APK 与 ZIP 的 SHA-256 均与 `SHA256SUMS-optimized.txt` 一致；Windows ZIP 与 APK ZIP 完整性检查通过，APK 的 ABI、包名、版本和 SDK 信息已核对。

本轮完成的是内部验收打包，未在 Android 设备安装运行，也未执行 Windows Release 启动或真机发布验收；APK / ZIP 使用合成数据与本地构建，正式签名、物理设备、Linux 和完整发布闸门仍按 [RELEASE_GATES](RELEASE_GATES.md) 执行。打包日志：`build/test_logs/review-build.log`。

## 2026-10-27 播放页滑动歌词与迷你歌词缩放

按追加需求补齐两个交互：

- 播放页内容区域支持从右向左滑动进入完整歌词页。该手势调用唯一的 `LyricsPage`，与点击歌词预览、菜单「查看完整歌词」共用同一页面，不恢复 PageView 或第二套歌词实现。滑动与页面下滑退出、控件点击和迷你歌词缩放手柄分开处理。
- 播放页的「歌词预览」作为独立 mini 歌词控件保留，右下角增加尺寸手柄；直接拖动可同时调整宽高，松手后保存。系统默认布局首次调整会创建一份自定义模板，避免把只读默认模板变成隐式全局偏好；已有自定义模板则直接更新。手柄使用原始指针事件，与页面横滑 / 下滑手势互斥，避免拖动手柄时误开歌词页或退出播放器。
- 迷你歌词区仍是布局组件，9 / 16 宫格编辑器和手柄两种调整方式都写入同一套全画布坐标；完整歌词页仍是独立路由。

验证：

- `flutter analyze` 无问题（`build/test_logs/swipe-analyze-final.log`）。
- 全量单元 / Widget 测试 **127 项通过、5 项私密环境测试默认跳过**（`build/test_logs/refactor-full-suite-final.log`）。
- Windows 原生 UI 集成通过：播放页右向左滑动进入歌词、返回；迷你歌词手柄拖动后歌词预览尺寸改变并创建自定义布局；主播放键、封面和下滑退出保持正常（`build/test_logs/swipe-ui-final.log`）。
- Windows 原生布局 / 编辑器集成继续通过 360×800 / 1200×850 / 320×640（`build/test_logs/swipe-layout-final.log`）。
- 合成截图：`build/test_logs/ui/player-mini-lyrics-resized.png`，只含合成数据。
- 已重新使用 `tool/build_review.ps1` 打包：arm64-v8a 29.22 MB、armeabi-v7a 26.16 MB、x86_64 31.46 MB、Windows ZIP 21.69 MB；四份产物 SHA-256 与签名复核通过（`build/test_logs/review-build.log`）。
- 集成测试后已重新构建普通 `lib/main.dart` Windows Debug 入口（`build/test_logs/swipe-windows-build.log`）。
- 尚未在 Android 设备验证滑动和直接缩放。正式签名与发布门槛不变。

## 2026-10-27 播放页跟随系统深浅色与可选封面模糊

按用户要求修正播放页主题：

- 播放页不再强制局部深色主题；它使用应用当前 `Theme.brightness`，因此跟随系统浅色 / 深色，也跟随用户手动选择的浅 / 深模式。封面取色同样按当前明暗提取并缓存。
- `PlayerBackdrop` 以纯色背景设置（白 / 黑）或主题 Surface 为基础；封面模糊改为默认关闭的可选层，可在设置或播放页「更多 → 封面模糊背景」开启。浅色模式使用白色系遮罩、深色模式使用黑色系遮罩。
- 纯色背景设置现在同时作用于一级页面和播放页基础底色，不再是只有一级页面才生效的设置；播放页局部布局仍可选择主题渐变、纯色或封面模糊。
- 播放页、完整歌词页和布局编辑器预览共享当前明暗、封面取色和背景规则；歌词页在浅色模式下验证了返回、字号、进度和播放控制的对比度。
- 「沉浸背景」设置更名为「封面模糊背景」，默认关闭；未显式保存过的旧安装按新默认值处理。布局编辑器的「封面模糊」选项提示它受该总开关控制。

验证：

- `flutter analyze` 无问题（`build/test_logs/theme-analyze-final.log`）。
- 全量单元 / Widget 测试 **127 项通过、5 项私密环境测试默认跳过**（`build/test_logs/theme-full-suite-final.log`）。
- Windows 原生 UI 集成通过：深色播放页、切到浅色后的白色纯色底、封面模糊菜单开关、浅色封面模糊、浅色完整歌词页、迷你歌词缩放、右向左滑动、下滑退出（`build/test_logs/theme-ui-final.log`）。
- Windows 原生布局 / 编辑器集成继续通过 360×800 / 1200×850 / 320×640（`build/test_logs/theme-layout-final.log`）。
- 合成截图：`build/test_logs/ui/player-light-solid.png`、`player-light-cover-blur.png`、`player-lyrics-light.png`；播放页深色对比截图仍为 `player-disc-mobile.png` 与 `player-immersive-wide.png`。
- 已重新打包内部产物：arm64-v8a 29.22 MB、armeabi-v7a 26.16 MB、x86_64 31.46 MB、Windows ZIP 21.69 MB；SHA-256、签名和 ZIP 完整性复核通过（`build/test_logs/review-build.log`）。
- 集成测试后已重新构建普通 `lib/main.dart` Windows Debug 入口（`build/test_logs/theme-windows-build.log`）。
- 尚未在 Android 设备验证系统深浅色切换与封面模糊；正式签名与发布门槛不变。

## 2026-10-27 底栏高度调整

按用户要求，将手机底部 `NavigationBar` 高度从 72 dp 调整为 **54 dp**（减少 1/4）：

- 只调整底栏总高度，保留 `maintainBottomViewPadding`，继续由 NavigationBar 自身安全区避让系统手势条 / 三键导航，不额外叠加底部 Insets。
- 图标、文字、选择指示和迷你播放器位置随高度自然上移，没有新增溢出。
- 宽屏 NavigationRail 不受影响。
- 更新 Android 系统栏原生测试的期望高度为 `54 + 底部 inset`。
- `integration_test/ui_refresh_test.dart` 在 360×800 实际断言 NavigationBar 高度为 54，并完成原有导航 / 播放页流程。

验证：`flutter analyze` 无问题（`build/test_logs/navbar-analyze.log`）；全量单元 / Widget 测试 127 项通过、5 项默认跳过（`build/test_logs/navbar-full-suite.log`）；Windows 原生 UI 集成通过并实际断言底栏高度 54（`build/test_logs/navbar-ui.log`）；Windows Debug 重新构建（`build/test_logs/navbar-windows-build.log`）。Android 系统栏测试已同步为 `54 + inset`，但本轮未连接 Android 设备执行。内部包已按 `review-build.log` 重新生成并通过 SHA-256 / 签名 / ZIP 完整性核对。文件：`lib/ui/app_shell.dart`。

## 2026-10-27 迷你歌词字号独立设置

播放页的迷你歌词区现在有独立字号，不再跟随完整歌词页：

- `Appearance` 新增 `miniLyricFontSize`（16 / 20 / 24，默认 20）和 settings key `ui_mini_lyrics_font_size`；完整歌词继续使用 `lyricFontSize`（20 / 24 / 28），两者分别持久化。
- 播放页「更多 → 迷你歌词字号」打开选择面板；设置 → 外观与体验新增「迷你歌词字号」，原「歌词字号」更名为「完整歌词字号」。
- 迷你歌词区、布局编辑器预览使用迷你字号；完整歌词页和其顶部字号菜单继续使用完整歌词字号。
- 布局编辑器歌词组件说明已更新，不再声称预览与完整歌词共用字号。

验证：`flutter analyze` 无问题（`build/test_logs/minilyrics-analyze-final.log`）；全量单元 / Widget 测试 127 项通过、5 项默认跳过（`build/test_logs/minilyrics-full-suite.log`）；Windows 原生 UI 集成通过，实际把迷你字号从 20 切到 24 并断言 `LyricsPreview.fontSize` 更新（`build/test_logs/minilyrics-ui-1.log`）；Windows 布局 / 编辑器集成继续通过（`build/test_logs/minilyrics-layout.log`）。已重新打包内部产物（arm64-v8a 29.22 MB、armeabi-v7a 26.16 MB、x86_64 31.46 MB、Windows ZIP 21.70 MB），SHA-256、签名与 ZIP 完整性复核通过（`build/test_logs/review-build.log`）；集成测试后重新构建普通 Windows Debug（`build/test_logs/minilyrics-windows-build.log`）。尚未在 Android 设备验证字号设置。

## 2026-10-27 音乐库胶囊筛选栏

按用户要求，将音乐库的「歌曲 / 专辑 / 艺术家」连接式分段控制器改为胶囊筛选栏：

- 使用 3 枚独立 `ChoiceChip`，`StadiumBorder` 胶囊形；选中项为主题主色 + onPrimary 图标 / 文字，未选中项为 `surfaceContainerHighest` 半透明底 + onSurfaceVariant。
- 保留图标、横向滚动、单选手感和原有 `libraryView` 状态；窄屏可横向滚动，不再出现连接式分段边界。
- 未改动独立搜索页的分类控件及其测试语义。
- 集成测试断言 3 枚 `ChoiceChip` 存在、初始「歌曲」选中、切换「专辑」后对应选中；使用 `library-filter-*` key，避免点到其他同名文字。

验证：`flutter analyze` 无问题（`build/test_logs/chips-analyze-final.log`）；Windows 原生 UI 集成通过（`build/test_logs/chips-ui-final.log`，含 360×800 视觉截图 `build/test_logs/ui/library-sort-mobile.png`）；全量单元 / Widget 测试 127 项通过、5 项默认跳过（`build/test_logs/chips-full-suite.log`）。尚未在 Android 设备验证横向滚动与触摸手感。

## 2026-10-27 媒体资源持久化实现

实现 MediaAssetStore 与 LyricsStore，数据库升级 v6，远程封面 / 歌词统一记录身份、版本、文件、摘要、时效和访问时间。不可变内容文件经唯一 TEMP / flush / rename，再事务提交索引；启动对账清除残片、缺文件记录和无索引对象。封面按实际图片身份与 tag 复用，避免歌曲修改时间误失效；支持 HTTP 条件请求。远程歌词有效期内直接命中，过期先展示本地再刷新，同源同 key 请求合并，后台更新通知页面，不再每次重复拉取纯文本。显式重试强刷，手动导入优先且不参加普通淘汰。

按来源隔离和内容去重复用；封面 200 MiB、远程歌词 20 MiB 配额由 SQL 分批 LRU 管理，读取租约保护旧文件；元数据采用 64 MiB 加本次写入量预留，磁盘不足保留旧版本。来源停用和删除阻止晚到写入，退出等待资源任务。保留旧未区分手动 / 下载歌词作为恢复副本，迁移标记避免清理后重复导回。具体边界见 MEDIA_ASSETS.md。

存储、服务和页面测试覆盖迁移、重开离线命中、SWR、并发合并、版本竞态、损坏 / 磁盘不足、配额、手动保护和页面自动更新。Windows 与 API 35 Android 原生测试均通过：使用本机模拟 Emby 和合成图片，关闭服务器，重建应用服务及 SQLite，以空凭据库再次读取、解码和显示封面 / 歌词。Windows 受执行环境目录写入限制，使用工程内独立测试目录及进程 TEMP / TMP，通过后未修改系统权限。原生日志为 assets-native-windows.log 和 assets-native-android.log；不以服务重建代替物理设备强杀验收。

最终完整测试 159 项通过、5 项私密环境测试默认跳过，静态分析与 Dart 格式检查通过。重建普通入口 Release 优化包：arm64 29.28 MB、32 位 ARM 26.22 MB、x86_64 31.59 MB、Windows ZIP 21.72 MB。两组测试凭据内容扫描、APK 签名、产物摘要及 ZIP CRC 验证通过；API 35 模拟器已成功覆盖安装 x86_64 优化包并冷启动。日志 assets-full-suite.log、assets-review-build.log 位于 build/test_logs。仍使用本机内部测试签名，未推送远端。

## 2026-10-28 Android applicationId 修改

按用户要求，将 Android 包名从 `music.sylphy.sylphy_music` 改为 **`com.ymltsh.sylphymusic`**，并重新打包 APK：

- `android/app/build.gradle.kts` 的 `namespace` 与 `applicationId` 同步修改。
- Kotlin 源文件移动至 `android/app/src/main/kotlin/com/ymltsh/sylphymusic/`，`MainActivity.kt` 与 `CacheForegroundService.kt` 的 package 声明同步更新。
- `tool/bootstrap_platforms.py` 的原生 runner 校验路径同步更新。
- Android Manifest 仍使用相对 Activity / Service 名称，构建后的清单已解析为 `com.ymltsh.sylphymusic.MainActivity` 与 `com.ymltsh.sylphymusic.CacheForegroundService`。
- Linux APPLICATION_ID、Windows 桌面标识和 Dart package 名称 `sylphy_music` 未改变；本轮只变更 Android 应用身份。

验证：`flutter analyze` 无问题；使用 `tool/build_review.ps1` 重新构建并打包成功。三份 APK 经 `aapt dump badging` 核对：包名均为 `com.ymltsh.sylphymusic`、versionName 0.2.0、minSdk 24、targetSdk 36，versionCode 分别为 2002 / 1002 / 4002，ABI 分别为 arm64-v8a / armeabi-v7a / x86_64；启动 Activity 为新包名。`apksigner` 验证 APK Signature Scheme v2 通过，三份均使用同一本机 Android Debug 测试证书。SHA-256 与清单一致，APK ZIP 完整性和内容扫描通过（205 个已跟踪文件）。

产物：arm64-v8a 29.43 MB、armeabi-v7a 26.40 MB、x86_64 31.74 MB；Windows ZIP 21.84 MB。日志 `build/test_logs/package-rename-review-build.log`。未在 Android 设备安装运行。由于 applicationId 改变，新包是独立的 Android 应用身份，旧包数据不会自动迁移；尚未配置正式签名，因此仍不是正式发布包。

## 2026-10-28 应用显示名本地化

按用户澄清，不显示双语名称，也不建立第二个桌面名称；同一应用按系统语言显示单一名称：

- Android Manifest 的 `android:label` 改为 `@string/app_name`。默认资源为 `Sylphy Music`，新增 `values-zh/strings.xml` 为「风灵音乐」。
- 首页标题与 MaterialApp 标题统一通过 `lib/ui/app_identity.dart` 获取名称：英文系统为 `Sylphy Music`，中文及其他非英文系统为「风灵音乐」。MaterialApp 的原双语 title 已移除。
- Android 包名仍为 `com.ymltsh.sylphymusic`，未新增第二个应用身份；三份 APK 只是 ABI 拆分。

验证：`flutter analyze` 无问题；Windows UI 集成测试切换英文 / 中文系统并分别断言 `Sylphy Music` 与「风灵音乐」，测试通过。重新打包后 `aapt dump badging` 显示 `application-label:'Sylphy Music'`、`application-label-zh:'风灵音乐'`；包名、versionCode、SDK、ABI 与 v2 签名均保持通过，SHA-256 / ZIP 完整性检查通过。产物尺寸保持不变：arm64-v8a 29.43 MB、armeabi-v7a 26.40 MB、x86_64 31.74 MB；Windows ZIP 21.84 MB。尚未在 Android 真机切换语言安装验证。

## 2026-10-28 Android 后台播放前台服务修复

应用 `SylphyMusic-android-background-playback.patch`。补丁与当前 `playback.dart` 的上下文已有差异，`git apply --check` 不能直接通过，因此按补丁逻辑逐处合并到现有实现：

- 新增 `_playRequested`，让“用户想播放”的意图独立于底层播放器在切歌间隙短暂上报的 `playing=false`；`audio_service` 的 `PlaybackState.playing` 改用该意图，避免 Android 在换曲时退出前台服务。
- 新增 `_finishingTrack`，完成回调期间上报 buffering，并防止同一完成事件重复触发切歌。
- `_loadCurrent` 在打开下一首和申请音频焦点前先发布状态；打开期间收到暂停则不再自动播放，并在 finally 重新发布最终状态。
- `play` / `pause` / 自动 `next` / `_finished` / `_failed` / 重连 / 清空队列 / shutdown 均同步维护播放意图；移除当前曲目时用播放意图决定是否继续。
- 用户暂停仍然立即把 `PlaybackState.playing` 置为 false，不会因为过渡保护而继续占用前台服务。

验证：`flutter analyze` 无问题；全量单元 / Widget 测试 **166 项通过、5 项默认跳过**（`build/test_logs/background-playback-full-suite.log`），包含真实 libmpv 播放、暂停、切歌、队列移除与恢复测试。日志 `build/test_logs/background-playback-analyze.log`。由于没有连接 Android 真机，尚未实测锁屏跨曲和 FGS 存活的系统行为；本轮未重新打包 APK。

## 2026-10-28 测试签名 0.2.1+3 首次发布

按用户「测试签名即可」的明确授权，完成首个可更新版本的本地构建和 GitHub Release：

- `pubspec.yaml` 版本从 0.2.0+2 提升到 **0.2.1+3**，提交 `54b5f84`，标签 `v0.2.1+3` 已推送。
- 使用 `tool/build_review.ps1` 以本机 Android Debug 测试证书构建三 ABI APK；`aapt` 核对包名 `com.ymltsh.sylphymusic`、versionName 0.2.1、versionCode 2003 / 1003 / 4003、minSdk 24、targetSdk 36，`apksigner` v2 验签通过。
- GitHub Release：https://github.com/ymltsh/SylphyMusic/releases/tag/v0.2.1%2B3
  - `sylphy-music-0.2.1-3-arm64-v8a.apk` 29.43 MB
  - `sylphy-music-0.2.1-3-armeabi-v7a.apk` 26.40 MB
  - `sylphy-music-0.2.1-3-x86_64.apk` 31.74 MB
  - `SHA256SUMS.txt`
- `version.json` 已更新为 stable 0.2.1+3 并指向上述资产；`version-beta.json` 保持 `latest: null`。
- 应用内更新入口保持手动检查；未接入自动下载 / 静默安装。

限制：这是**测试签名**的 stable 清单，不是正式签名发布；17 项正式发布门槛仍未通过。由于 applicationId 从旧包名变更，旧包用户不会自动升级且旧数据不会迁移。尚未在 Android 真机安装验证锁屏后台播放、覆盖安装和更新检查。发布脚本因生产签名 / 正式门槛被明确绕过，改由内部构建和 GitHub API 上传；后续正式发布应恢复 `release.py` 流程。

## 2026-10-28 用户主动启用的诊断日志

应用 `SylphyMusic-diagnostic-logging.zip`。原安装脚本因播放器暂停保护和设置页拆分，无法通过当前代码的锚点预检；已按同一逻辑合并到当前结构：

- 新增 `DiagnosticLogs`：默认关闭，状态持久化在既有 settings 表；3 × 512 KiB JSON Lines 轮转、串行写队列、导出前等待队列、清除与关闭；只接受白名单 scope / event / detail 字段，不写曲名、来源 ID、URL、路径、异常正文或堆栈。
- 应用装配：创建 `diagnostics` 目录并恢复开关；注入播放器与媒体代理；退出时先停生产任务、再 flush / 关闭诊断。设置页新增「诊断与反馈」：记录开关、导出、系统分享和清除；Linux 分享转为导出。应用生命周期与播放、缓冲、完成、恢复、代理请求结果写入安全事件。
- 依赖新增 `share_plus` / `cross_file`，重新生成 Windows 插件注册并更新 Dart 许可证清单；Android 原生 Debug 构建通过。
- 新增服务测试 6 项；全量测试 **172 项通过、5 项私密测试默认跳过**（`build/test_logs/diagnostics-full-suite.log`）；Windows UI 集成通过，实际开启诊断、写入日志文件、关闭并截图（`build/test_logs/diagnostics-ui-2.log`、`build/test_logs/ui/settings-diagnostics-mobile.png`）。`flutter analyze` 无问题。
- 本轮未提交、未推送、未重新打包正式版本；已发布的 0.2.1+3 不包含此功能。后续发布需要使用新版本号和新的构建号。
- 未连接 Android 真机验证锁屏长时记录、系统分享附件接收和清除后的真实文件行为。

## 2026-10-28 Android 系统媒体封面修复

应用 `apply_sylphy_media_artwork.py`。脚本因当前播放器已加入诊断日志导入，无法通过锚点预检；已按同一逻辑合并：

- 新增 `mediaItemForTrack`，Android 媒体通知的 `MediaItem.artUri` 使用实际存在的本机封面文件 URI。
- `PlaybackCoordinator` 连接 `ArtworkStore`，对当前曲目封面保留租约并在切歌 / 退出时释放；监听封面缓存更新，重新加载并发布通知元数据。
- 媒体元数据只在曲目、可见元数据或封面 URI 变化时发送，避免播放进度更新造成重复通知刷新。
- Android 启动媒体服务前接入封面仓库；非 Android 不注册该逻辑。
- 保留现有播放意图、诊断日志和播放状态发布路径。

验证：`flutter analyze` 无问题；`test/artwork_test.dart` **10 项通过**（含新增的封面 URI 可读测试）；全量测试 **173 项通过、5 项私密测试默认跳过**；Android Debug APK 构建成功。

限制：尚未在 Android 真机验证锁屏 / 通知栏 / 蓝牙媒体面板能否读取该 `file://` 封面 URI；Android SystemUI 对应用私有文件 URI 的实际访问行为必须真机确认。当前工作树仍未提交、未推送，版本仍为已发布的 0.2.1+3；该发布包不包含本次诊断日志和媒体封面修改，下一次发布需要新版本号与构建号。

## 2026-10-28 Android 备用桌面图标方案

应用 `SylphyMusic_launcher_icon_switch.zip`，并接入用户提供的 7 张图标（`logo/1.png` 至 `logo/7.png`）：

- Android Manifest 改为 `LauncherIconDefault` 启动别名；备用图标使用生成脚本创建的 `activity-alias`，默认只启用默认图标。
- 新增原生 `LauncherIconManager` 与 Flutter `LauncherIconPicker`：设置 → 外观与个性化 → 应用图标（仅 Android 显示），由 PackageManager 保存所选组件状态，不写数据库。
- 7 张源图转换为真实 PNG（其中 3–6 原文件实际为 WebP）并命名为：线形蓝、实心蓝、青绿线形、青绿实心、黑底圆点、白底圆点、银发精灵；默认图标仍为 `assets/icon.png`。
- 生成 7 个备用 alias、`mipmap-nodpi` 资源和 `android/app/src/main/assets/launcher_icons.json`；预览资源加入 Flutter assets。
- Android 13+ 使用原子组件状态切换；旧版本先启用新入口再禁用其余入口，`DONT_KILL_APP` 降低中断风险。

验证：`flutter analyze` 无问题；`test/launcher_icon_service_test.dart` 2 项通过；全量测试 **175 项通过、5 项默认跳过**；Android Debug APK 构建成功，`aapt` 确认 8 个 alias（1 个默认 + 7 个备用）和对应 mipmap，启动器资源打包。未在 Android 真机验证图标切换、启动器刷新、播放中切换和重启保持；桌面平台图标不变。

这些修改已随 `0.2.2+4` 测试签名版本发布；已发布 0.2.1+3 不包含诊断日志、媒体通知封面和本图标方案。

## 2026-10-28 测试签名 0.2.2+4 发布

- 版本提交 `5584814`，标签 `v0.2.2+4`；GitHub Release：https://github.com/ymltsh/SylphyMusic/releases/tag/v0.2.2%2B4
- 三份 APK 使用本机 Android Debug 测试证书：arm64-v8a 32.94 MB、armeabi-v7a 29.94 MB、x86_64 35.25 MB；versionName 0.2.2，versionCode 2004 / 1004 / 4004。
- `aapt` 核对包名 `com.ymltsh.sylphymusic`、本地化应用名、8 个 launcher alias 与 mipmap；`apksigner` v2 验签通过。
- `version.json` 更新为 stable 0.2.2+4，历史保留 0.2.1+3；`version-beta.json` 保持 `latest: null`。
- 仍为测试签名，非正式发布；正式发布门槛尚未通过。尚未在 Android 真机验证图标切换、诊断日志、媒体通知封面、后台播放和覆盖安装。

## 2026-10-28 默认图标改为线条蓝

按用户要求移除旧的绿色音符默认图标：`assets/icon.png` 与 Android `mipmap-*/ic_launcher.png` 全部替换为 `logo/1793130613776.png` 的线条蓝缩放版本（此前曾使用 `logo/1.png`，现由该图替代）；备用图标目录移除重复的「线形蓝」，当前为 6 个备用图标 + 1 个线条蓝默认图标。原生默认选项标签保持「线条蓝（默认）」，launcher alias 与 mipmap 资源已同步。该变更已随 0.2.3+5 测试签名版本发布；0.2.2+4 仍是旧的默认图标方案。

验证：`flutter analyze` 无问题；`test/launcher_icon_service_test.dart` 2 项通过；全量测试串行运行 **175 项通过、5 项默认跳过**；Android Debug APK 构建成功，`aapt` 确认 7 个 alias（线条蓝默认 + 6 个备用）和对应 mipmap。并行全量测试曾出现一次 `media_proxy_test` 未完成，单独及 `--concurrency=1` 重跑均通过。未在 Android 真机验证默认图标是否立即刷新；Windows 桌面图标未改动。

## 2026-10-28 首页每日一言、随机探索与 API 设置

按 `SylphyMusic-r.zip` 应用首页、歌单与 API 设置修改：

- 歌单页移除「我的歌单」标题，同步云歌单图标移至「新建歌单」左侧。
- 首页横幅副标题接入每日一言，默认 `https://v1.hitokoto.cn/?encode=json`；同一自然日成功获取后写入 SQLite 缓存，失败保留旧内容或默认文案。
- 首页「探索音乐库」改为读取完整目录队列、随机打乱后开始播放并切换音乐库；空库和错误分别提示。
- 设置 → 网络与接口 → API 设置：可修改每日一言 API 与 GitHub 加速前缀；留空保存恢复默认，仅接受 HTTPS。
- 更新检查、APK / Windows 下载按钮和发布页链接统一使用已配置的 GitHub 加速前缀；清单本身仍只允许本项目 GitHub Release 资源。加速请求失败不再回退 GitHub 原始地址。
- 新增 `ApiSettings` 服务及测试；更新检查测试改为验证自定义 gateway 和无回退行为。

验证：`flutter analyze` 无问题；全量测试串行 **180 项通过、5 项默认跳过**；Windows UI 集成通过；Android Debug APK 构建成功。默认 GitHub 加速清单返回 200，默认每日一言接口返回 200。修复了生成补丁中 API 测试未声明 UTF-8 响应头导致的失败，并把设置页 UI 测试的懒加载滚动改为先回顶再定位。

上述修改已随 0.2.3+5 测试签名版本发布。未在 Android 真机验证每日一言、加速下载和随机播放。

## 2026-10-28 测试签名 0.2.3+5 发布

- 版本提交 `dd19777`，标签 `v0.2.3+5`；GitHub Release：https://github.com/ymltsh/SylphyMusic/releases/tag/v0.2.3%2B5
- 三份 APK 使用本机 Android Debug 测试证书：arm64-v8a 32.91 MB、armeabi-v7a 29.95 MB、x86_64 35.22 MB；versionName 0.2.3，versionCode 2005 / 1005 / 4005。
- `aapt` 核对包名 `com.ymltsh.sylphymusic`、本地化应用名、7 个 launcher alias 与 mipmap；`apksigner` v2 验签通过。
- `version.json` 更新为 stable 0.2.3+5，历史保留 0.2.2+4 与 0.2.1+3；`version-beta.json` 保持 `latest: null`。
- 仍为测试签名，非正式发布；正式发布门槛尚未通过。尚未在 Android 真机验证首页每日一言、随机播放、加速下载、默认图标、诊断日志、媒体通知封面、后台播放和覆盖安装。


## 2026-10-28 WebDAV 主动读取内嵌封面与歌词

- 新增共享 WebDavTags：显示封面 / 读取歌词时主动请求有界音频标签区，支持 MP3 ID3v2、FLAC 评论 / 图片及 M4A / MP4 moov；MP4 可跳过音频数据定位末尾标签。目录同步仍不逐首下载音频。
- 修复 USLT 中文、UTF-8 / UTF-16 LE / BE 歌词解码，支持毫秒 SYLT 转 LRC；内嵌图片优先正面封面。缺失或损坏时回退旁置文件，手动导入歌词始终优先。
- 封面和歌词按资源版本持久化，目录共用图片不再导致不同曲目内嵌封面串用；完整音频缓存可离线提取。读取最多三个并发、累计 12 MiB / 64 请求，校验 Range / 长度 / 版本，来源停用和退出取消任务。
- 验证：flutter analyze 无问题；全量串行测试 192 项通过、5 项私密测试默认跳过；提供的 WebDAV 测试源完成只读 Range、内嵌歌词及图片解码验证；Windows / Android API35 模拟器原生测试均验证提取前无 READY、封面显示与服务 / 数据库重启后离线复用。
- 按用户最新授权已发布 0.2.4-beta+6 Android 测试签名更新，使用 beta 清单；正式渠道保持 0.2.3+5。未做 Android 真机验收；Linux 继续暂缓。

发布证据：源码提交 `5f14e0f`，测试版标签 `v0.2.4-beta+6`；beta 清单提交 `ac48377`。Release 提供三份 APK 和 SHA256SUMS.txt，远端四个资产的大小 / SHA-256 与本地一致；arm64 原始及配置加速下载链接均返回 HTTP 200。arm64-v8a 31.45 MiB、armeabi-v7a 28.59 MiB、x86_64 33.71 MiB，三个 APK 验签通过，证书与 0.2.3+5 相同；versionName 0.2.4-beta，versionCode 分别为 2006 / 1006 / 4006。x86_64 Release 在自建模拟器覆盖安装并启动成功。发布页：https://github.com/ymltsh/SylphyMusic/releases/tag/v0.2.4-beta%2B6 。

## 2026-10-28 应用 WebDAV Artist / Album 元数据补丁

应用用户提供的 SylphyMusic-WebDAV-metadata.patch，并适配现有测试与格式规范：提取 ID3 / FLAC / MP4 文本标签，SQLite 升级至 v7，按资源版本持久化并在重扫时合并；新增进程内分页渐进补全及可见曲目优先调度，分组刷新使用两秒节流。

补充修复：旧版数据库测试正确构造 v1 / v5 结构；退出时先停止补全生产并等待可见任务，异步查询后复核取消代次。增加真实 v6→v7 迁移、来源停用 / 删除后拒绝过期标签、可见任务退出等待的回归覆盖。

验证：flutter analyze 无问题；全量串行测试 197 项通过、5 项私密测试默认跳过；Windows 原生集成验证内嵌标题 / 艺术家 / 专辑落库、封面 / 歌词与离线重启复用。此次未重新运行 Android / Linux 原生测试，未生成或发布新版本安装包；当前发布包仍为 0.2.4-beta+6。

## 2026-10-28 WebDAV 元数据测试更新准备

按用户授权准备 0.2.4-beta2+7，发布到 beta 渠道，Android 使用已有测试签名及三个 ABI 的 Release 包。包含本节前的元数据补丁与 v7 迁移修复；正式渠道保持 0.2.3+5。

本轮复核：flutter analyze 无问题，全量测试 197 项通过、5 项默认跳过；Android API35 模拟器原生集成通过，验证内嵌标题 / 艺术家 / 专辑持久化与离线重启复用。模拟器安装集成测试 Debug 包时因版本号低于上轮按 ABI Release 包，由 Flutter 工具卸载重装自建 AVD 内的测试应用；不涉及真机或用户数据目录。

## 2026-10-28 发布 0.2.4-beta2+7 Android 测试更新

源码提交 `fa59a50`，测试版标签 `v0.2.4-beta2+7`，beta 清单提交 `ba33bc4`。发布页：https://github.com/ymltsh/SylphyMusic/releases/tag/v0.2.4-beta2%2B7 。正式渠道保持 0.2.3+5，beta 历史保留 0.2.4-beta+6。

三份 APK 与 SHA256SUMS.txt 已公开，远端四个资产的大小与 SHA-256 均与本地一致；arm64 原始和配置加速下载链接返回 HTTP 200。arm64-v8a 31.51 MiB、armeabi-v7a 28.62 MiB、x86_64 33.71 MiB；versionName 0.2.4-beta2，versionCode 分别为 2007 / 1007 / 4007。签名与现有测试版本相同，凭据扫描通过。自建 Android API35 模拟器从 beta+6 Release 覆盖安装 beta2+7 并启动成功。仍为测试签名，尚待 Android 真机验收，Linux 验收继续暂缓。

## 2026-10-28 Android 前台同步补丁及双端测试更新准备

应用用户提供的 Android FGS sync 补丁，适配当前控制器上下文；新增手动同步通知、进度 / 暂停、WebDAV 只补全入口和 Application 引擎持有。补充 audio_service 缓存身份与引擎释放兼容、服务启动确认、取消在线读取和退出等待。准备 0.2.5-beta+8 Android / Windows 测试渠道更新。Android API35 模拟器已验证移除 Activity 后继续同步、系统短时限终止服务、重开 Activity 继续标签补全并跳过已完成网络读取；模拟器设置已恢复。真机 / 厂商后台策略仍待验证。

本轮验证：flutter analyze 无问题；全量串行 201 项测试通过、5 项私密测试默认跳过；Android API35 同步前台服务集成与 Windows 全界面原生集成通过。新桥接测试覆盖启动失败 / 重试、进度节流、原生暂停 / 超时事件与桌面空实现。

## 2026-10-28 发布 0.2.5-beta+8 Android / Windows 测试更新

源码提交 `a4c7b96`，标签 `v0.2.5-beta+8`，beta 清单提交 `7d4c105`；发布页：https://github.com/ymltsh/SylphyMusic/releases/tag/v0.2.5-beta%2B8 。测试渠道同时提供 Android 三个 ABI、Windows 安装程序及便携 ZIP，正式渠道保持 0.2.3+5。

六个资产（含摘要）远端大小和 SHA-256 均与本地一致，Android arm64、Windows EXE / ZIP 加速下载均返回 HTTP 200，默认加速 beta 清单已指向新版本。Android arm64 31.51 MiB、32 位 ARM 28.64 MiB、x86_64 33.71 MiB；Windows 安装 EXE 19.03 MiB、便携 ZIP 22.65 MiB。APK 证书与旧测试版一致，构建号为 2008 / 1008 / 4008；从 beta2+7 Release 覆盖安装并启动成功。Windows 可执行文件版本为 0.2.5-beta+8，ZIP 完整性、主程序与 flutter_windows / libmpv 运行依赖校验通过。

全部安装资产和输入完成凭据扫描；仍是测试版本，Android 使用测试证书、Windows 未代码签名。Windows 安装 / 卸载未在用户环境实际执行；Android 真机及厂商电源策略、Linux 验收仍待完成。

## 2026-10-28 按讨论修正 audio_service / dataSync 生命周期兼容

参考用户提供的共享讨论及此前 patch/3 兼容性资料，替换 0.2.5-beta+8 的销毁拦截 / 异步恢复缓存实现。SylphyApplication 只取得 audio_service 创建的引擎；同步与缓存通过 EngineLeaseManager 共享媒体服务绑定，各服务实例独立持有租约，等待连接及引擎身份确认后开始工作，最后租约释放后允许插件正常销毁引擎。绑定失败 / 断开有取消及停止兜底，不创建第二个 Dart main。

普通暂停等待索引、标签遍历、可见行读取或缓存 worker 与数据库状态清理完成，经 Dart 回执后停服；清理过程中的 stop 调用不提前释放租约，避免回执死锁。系统超时立即停止服务，保留已提交记录供恢复。补充每引擎 Dart 启动计数、引擎身份 / 缓存一致性、绑定 / 租约及 Dart 心跳诊断。标签进度区分成功、失败、已缓存跳过，并取消已缓存行的逐首延迟。

验证：格式检查及 flutter analyze 无问题；全量串行测试 203 项通过、5 项私密联调默认跳过（build/test_logs/lease-unit-suite.log）。新增异步暂停回执等待、按来源取消可见任务并等待，以及成功 / 失败 / 缓存跳过与真实数据库记录一致性测试。

Android API35 专用 AVD 两组原生集成通过：系统短时限回调及时停止，恢复时保留并跳过已完成标签（lease-timeout-android.log）；真实慢速缓存与同步并行，播放 / 暂停、Home / 熄屏 / 移除最近任务后 Dart 心跳及 SQLite 写入继续，双方分别暂停不释放另一租约，重新打开 Activity 保持同一引擎且 Dart 仅启动一次，最终全部释放（lease-overlap-android.log）。可复跑工具 tool/check_android_fgs.py 仅允许 SylphyTest_API35，临时时限已恢复为原值 null。Windows 原生 WebDAV 标签 / 封面 / 歌词持久化及离线重启通过（lease-windows-webdav.log）。

本轮仅修改并验证本地源码，未提交、推送、发布或重新生成 Release 安装包；线上仍为 0.2.5-beta+8。真机厂商后台策略、强停后恢复及 Linux 未在本轮验收。普通暂停仍有 60 秒无回执兜底；系统超时 / 进程死亡不承诺清理代码一定执行，恢复依靠原子索引和已提交标签。

## 2026-10-28 更换 7 个应用图标与关于页 Logo

按用户新提供的 `logo/` 素材替换全部 7 个图标：默认改为「微风与低音」（`assets/icon.png`），备用图标改为高气压、春风拂面、杨柳依依、点阵白、点阵黑、风精灵（`assets/launcher_icons/`）。源图按最长边缩放到 512×512（两张点阵原图 384×384 保持原尺寸）；关于页 Logo 改用透明底的 `assets/about.png`，不再复用桌面默认图标。原生默认选项标签同步为「微风与低音（默认）」，旧 alias、旧 nodpi 资源和旧预览图已移除。

生成链路保持零第三方依赖：新增 `tool/png_raster.py`（8 位 PNG 读写、三角滤波缩放、多尺寸 ICO），`tool/generate_icons.py` 改为从 `assets/icon.png` 派生 Android 五档 mipmap 与 Windows `app_icon.ico`（16–256 px 共 9 档）；`tool/generate_launcher_variants.py` 新增文件名数字前缀排序（显示时去掉前缀）与标签唯一性校验。

验证：`dart format` 全仓库无改动；`flutter analyze --no-pub` 无问题；全量单元 / Widget 测试 **235 项通过、5 项私密联调默认跳过**（`build/test_logs/icon-refresh-full-suite.log`）；新增 `test/test_icon_tools.py` 7 项 Python 测试通过；`test/about_page_test.dart` 新增关于页 Logo 资源断言。Android Debug APK 构建成功，`aapt` 确认 7 个 launcher alias（默认 + 6 备用）、五档 mipmap 与 6 张 nodpi 备用图标，APK 内含 `assets/about.png`；Windows Debug 构建成功，`app_icon.ico` 经 `rc.exe` 编译通过，生成的 EXE 内嵌新图标。Windows 原生 UI 集成测试通过，关于页截图 `build/test_logs/ui/about-mobile.png` 确认透明 Logo 正常显示。未在 Android 真机 / 模拟器验证图标切换和关于页渲染，未重新生成 Release 安装包；Linux 验收继续暂缓。

## 2026-10-28 应用歌词预览系统深浅色补丁

应用用户提供的 `sylphymusic-lyrics-preview-system-color.patch`：`PlayerElement` 新增 `lyricFollowSystemColor`（默认 `true`，仅在歌词预览的 props 中序列化，旧模板按 `true` 读取）；编辑器歌词颜色新增「默认」选项，与「主题」及预设色互斥，并显示颜色说明。`PlayerWidgetRegistry.lyricHighlightColor` 统一加载指示器与歌词高亮取色：显式颜色优先，其次按 `MediaQuery.platformBrightness` 使用黑 / 白，未启用默认模式时回退主题主色。

文档补充默认 / 主题 / 预设色行为与 `props.lyricFollowSystemColor` 兼容规则。验证：`dart format` 仅调整补丁排版；`flutter analyze --no-pub` 无问题；全量测试 **237 项通过、5 项私密联调默认跳过**（`build/test_logs/lyrics-system-color-full-suite.log`）；补丁新增 2 项测试覆盖序列化往返、旧模板回读、非法值拒绝，以及系统浅 / 深色、关闭默认模式和显式颜色的取色结果。Windows 原生 UI 集成测试与播放器布局集成测试通过（`build/test_logs/lyrics-system-color-windows-ui.log`、`build/test_logs/lyrics-system-color-layout-ui.log`），编辑器截图 `build/test_logs/layout/editor-lyrics-spacing-mobile.png` 确认「默认 / 主题 / 预设色」和说明文字布局正常。

注意：默认模式按系统 `platformBrightness` 取色，而播放页底色跟随应用内浅 / 深色设置；在应用内强制深浅色与系统相反时，默认歌词颜色可能与底色同色，可改用「主题」或预设色。未在 Android 真机 / 模拟器验证；未重新生成 Release 安装包。

## 2026-10-28 应用欢迎页重设计补丁

应用用户提供的 `sylphymusic-welcome-redesign.patch`：首次引导第 1 步改为浅色留白欢迎页（浅色主题使用 `#F7F9FE` 背景，深色沿用主题底色），包含风形图标、标语、三行简介和圆形箭头按钮，移除底部「开始使用」按钮；`LayoutBuilder` 按可用高度切换图标、字号与间距，320×640 与 360×800 均无溢出。第 2、3 步的进度头、底部按钮和原有流程不变。

同步适配 `integration_test/welcome_background_sync_test.dart`，改用 `find.byTooltip('开始使用')` 触发（旧文字按钮已移除）；`ui_refresh_test.dart` 增加简介、箭头按钮和 320×640 截图断言。文档更新首次引导描述。

验证：`dart format` 通过；`flutter analyze --no-pub` 无问题；全量测试 **237 项通过、5 项私密联调默认跳过**（`build/test_logs/welcome-redesign-full-suite.log`）；Windows 原生 `ui_refresh_test.dart` 与 `welcome_background_sync_test.dart`（保存 / 跳过 API 两条路径）通过（`build/test_logs/welcome-redesign-ui.log`、`build/test_logs/welcome-redesign-sync.log`）；截图 `build/test_logs/ui/welcome-mobile.png`、`welcome-small.png` 确认布局与按钮位置。深色欢迎页仅核对主题取色路径，未单独截图；未在 Android 真机 / 模拟器验证。相关变更已随 1.0.2 正式版发布，见下节。

## 2026-10-28 发布 1.0.2 正式更新

源码提交 `438aa40`，标签 `v1.0.2+14`，清单提交 `a0e0ab3`。发布页：https://github.com/ymltsh/SylphyMusic/releases/tag/v1.0.2%2B14

- 包含全套新图标（默认「微风与低音」+ 6 款备用）、关于页透明 Logo、歌词预览系统深浅色「默认」选项和欢迎页重设计。
- 六个资产已公开：arm64-v8a 29.80 MiB、armeabi-v7a 26.98 MiB、x86_64 32.05 MiB；Windows 安装 EXE 18.18 MiB、便携 ZIP 21.81 MiB；SHA256SUMS.txt。远端资产大小和 SHA-256 与本地一致，三个 APK 签名校验通过且证书摘要一致，凭据扫描通过。
- `aapt` 核对 versionName 1.0.2、versionCode 2014 / 1014 / 4014；Windows EXE FileVersion 1.0.2+14，安装程序 1.0.2.14。
- 正式清单 `version.json` 的 latest 为 1.0.2+14，history 保留 1.0.1+13、1.0.0+12、0.2.3+5；GitHub raw 与加速地址均返回新版本，五个下载链接 HTTP 200。
- 发布过程：`flutter analyze` 无问题，全量测试 237 项通过、5 项私密默认跳过；本轮仅设置 HTTPS 代理并排除 127.0.0.1，避免 Flutter 测试本地服务被代理拦截。
- 仍待完成：Android 真机 / 模拟器验收（图标切换、关于页、欢迎页）；Windows 安装 / 卸载未在用户环境执行；Windows 未代码签名。

## 2026-10-30 应用自动同步、云端收藏与路由播放栏补丁

按用户要求，将 `sylphymusic-sync-stars-player.patch` 同时应用到 main 与 feature/android-openlist-lite。适配两处界面上下文，歌单详情保留既有播放栏，避免重复参数；退出时等待自动同步任务结束再关闭数据库。OpenList 分支三个 ABI Android Release 编译成功，本轮不运行 analyze、测试或设备验证；既有 OpenList 未提交工作保留，不推送或发布该分支。主分支准备 1.0.14+27 Android / Windows 正式更新，发布结果另记。
