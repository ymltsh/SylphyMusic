# 风灵音乐 · Sylphy Music

Flutter / Material 3 多音源播放器，支持 Android、Windows、Linux。主工程、原生 Runner、依赖锁文件和自动化测试均在本目录。

正式发布仅处理构建、签名、私密信息扫描、打包上传和清单更新；分析、测试与验收独立执行，不作为发布前置条件。当前分发 Android / Windows，Linux 暂缓。最新证据与剩余工作见 [docs/PROGRESS.md](docs/PROGRESS.md)，发布标准见 [docs/RELEASE_GATES.md](docs/RELEASE_GATES.md)。

应用内「设置 → 检查更新」提供手动更新检查。Android / Windows 发布工具及版本清单维护见 [更新与发布流程](update.md)；默认仅准备本地包，远程发布需显式授权。

## 构建与运行

开发入口：[AGENTS.md](AGENTS.md) · [ARCH.md](ARCH.md) · [CONTRIBUTING.md](CONTRIBUTING.md) · [文档索引](docs/README.md)。

已验证工具链：Flutter **3.47.8 stable** / Dart **3.13.7**。Android 使用 Gradle 9.3.1、AGP 9.1.0、内建 Kotlin、JDK 17；Windows 需要 Visual Studio C++ 工具；Linux 需要 GTK3、libsecret、libmpv 及 Flutter 的桌面构建依赖。

```powershell
# 在本项目目录执行
./tool/bootstrap.ps1
flutter run -d windows
flutter build apk --debug
# 生成体积较小的本机验收包（Release 优化、Android 按架构拆分）
./tool/build_review.ps1 -CredentialFile ../emby测试账密.txt
# 本机完整检查、原生测试与内部打包；AndroidDevice 可省略
./tool/check_local.ps1 -AndroidDevice emulator-5580 -CredentialFile ../emby测试账密.txt
```

```sh
./tool/bootstrap.sh
flutter run -d linux
```

平台 Runner 已包含自定义媒体会话、托盘和缓存服务，**不要运行 flutter create 覆盖它们**。`tool/bootstrap_platforms.py` 现在只检查必要文件。`pubspec.lock` 与 CI 固定构建输入。

首次启动，通过独立引导连接 Emby / Navidrome / OpenSubsonic / WebDAV 或导入本地音乐，也可以跳过。之后在右上角「设置 → 音乐源管理」中添加服务器、本地文件和音乐文件夹。底部导航为首页、音乐库、歌单、我的，桌面宽屏使用侧栏；UI 范围见 [界面说明](docs/UI_REFRESH.md)。默认主题色为 #5094B2，可在设置中选择主色及四个主页面的自适应背景图；Android 支持透明手势条，歌曲 / 专辑 / 艺术家使用连续滚动。凭据由系统安全存储管理，独立于 SQLite。Android 文件选择器的临时副本会复制到应用管理目录；桌面文件夹来源引用原始文件，重新扫描按大小与修改时间增量更新。WebDAV 的支持范围和设置见 [docs/WEBDAV.md](docs/WEBDAV.md)。

## 实现范围

- 多账号独立来源身份、逐页暂存并原子提交的全量索引、取消 / 进度 / 中断后重新扫描；统一歌曲 / 专辑 / 艺术家由 SQLite 搜索、过滤、聚合和分页，启动不一次性读取全库元数据。
- 统一歌单、常用排序、来源筛选、歌曲黑名单及撤销。
- 本地收藏和歌单、单来源云歌单、重复条目、增删和重排、离线编辑 / 改名、保守三方合并、冲突备份、只读保全，以及写入意图日志防止超时后重复追加。
- media_kit / libmpv 原始音频播放、队列操作、随机历史、循环、Seek、暂停恢复、速度、ReplayGain、音量；Android 音频焦点与媒体通知，Windows SMTC / 媒体键 / 托盘。
- BR1 仅监听 127.0.0.1，短期随机票据，每次校验来源；Range / HEAD / 后缀读取、强 ETag 验证后的 P2 字节复用、完整长度与 SHA-256 校验、原子 READY、重启丢弃 TEMP、资源版本失效、统一 LRU 与逐曲清理。
- 歌单缓存快照与任务恢复、暂停 / 继续 / 取消 / 重试。Android 独立 dataSync 前台服务、通知暂停和系统时限回调；进程被强停后不承诺继续执行。
- MP3 / FLAC 等本地标签、内嵌封面 / 歌词、封面缓存、LRC 高亮 / 跟随 / 点击 Seek、动态背景及每曲手动导入 UTF-8 歌词。

黑名单默认只隐藏统一库 / 搜索 / 来源浏览中的歌曲，不改写已有歌单、收藏或队列。云歌单不跨来源自动替换歌曲。

停用来源会终止该来源的在线读取并暂停当前播放，保留索引、完整缓存和个人引用；受影响的缓存任务保留快照并提示手动重试。重新启用先验证服务器 / 账号认证，再同步索引；用户显式继续播放时重新打开媒体连接。

## 验证

```sh
flutter analyze
flutter test
flutter test integration_test/desktop_test.dart -d windows
flutter test integration_test/desktop_test.dart -d emulator-5580
flutter test integration_test/large_library_test.dart -d windows
flutter test integration_test/large_library_test.dart -d emulator-5580
```

原生测试会创建临时数据目录，使用自行生成的音频；默认不连接私人服务器。纯单元测试中的 libmpv 用例需要先构建 Windows Debug，或设置 `SYLPHY_MPV_LIBRARY` 指向本机 libmpv。Linux 无显示环境的集成测试使用 Xvfb 和 `--dart-define=SYLPHY_HEADLESS_AUDIO=true`。

集成测试会覆盖构建输出。内部验收打包使用 `tool/build_review.ps1`：重新构建普通入口的 Windows Release 与 Android Release / 分架构 APK，调用 `tool/package_review.py --mode optimized` 检查已跟踪源码和包内容中的已知私密值，输出到 `build/internal-review/`。脚本在本机显式启用测试签名；若有正式 `android/key.properties` 则优先使用其配置。正式发布另用 `release.py`，不要求先执行内部验收。

当前 Android arm64 内部包 **32.9 MB**（原通用 Debug **207.5 MB**），Windows Release 压缩包 **23.7 MB**（原 Debug **55.4 MB**）。旧版 32 位 ARM 手机选 `armeabi-v7a`，x86_64 用于对应设备 / 模拟器。Windows 完整解压后运行 `sylphy_music.exe`。同目录 `README-optimized.txt` 与 `SHA256SUMS-optimized.txt` 提供说明及摘要。

真实服务器测试默认跳过。私密测试凭据由环境变量指定文件路径，不把密码放入命令行或源码：

- `SYLPHY_EMBY_CREDENTIAL_FILE`：URL、用户名、密码三行，只读测试。
- `SYLPHY_WEBDAV_CREDENTIAL_FILE`：URL、用户名、密码三行，WebDAV 只读测试。
- `SYLPHY_ALLOW_TEST_PLAYLIST_WRITES=1`：仅在用户明确批准后启用临时 Emby 歌单写入测试。
- `SYLPHY_SUBSONIC_TEST_FILE`：同样三行；此写入测试严格只允许隔离的 loopback 测试服务器。

测试文件：`test/live_emby_test.dart`、`test/live_emby_write_test.dart`、`test/live_subsonic_test.dart`。Android 私密测试可用 `tool/private_fixture_server.py` 提供一次性本机读取，原始密码不编入 APK。

## 持续验收

Linux 真实构建与运行、Android 实机来电 / 蓝牙 / 耳机与后台限制、更多只读 / 权限撤销 / 并发冲突场景，以及原生媒体依赖的完整分发许可证审计继续跟进，见 [验收记录](docs/RELEASE_GATES.md)。Android 正式签名已配置；真实 Emby 临时歌单 CRUD 已通过。是否推送或发布以维护者当前指令为准。

Emby 内嵌文本歌词优先获取保留时间轴的 SRT，转换为毫秒精度 LRC；外置 LRC 优先读取原格式，不支持时间轴转换时回退纯文本。旧 Emby 纯文本缓存会尝试升级，手动导入独立保存；详见 [Emby 歌词](docs/EMBY_LYRICS.md)。不同服务端版本的转换兼容性仍需继续验证。OpenSubsonic 支持结构化歌词接口并兼容传统文本接口。服务器不提供稳定身份时，不允许在旧来源身份下更换 OpenSubsonic 地址；需添加独立来源来隔离旧缓存和歌单。

自有代码使用 MIT。原生 libmpv / FFmpeg 等依赖的许可须分别核实；MIT 不覆盖它们的分发义务。不要把测试凭据、私有服务器地址、原始音乐、签名密钥或 `.private/` 内容提交到公共仓库。
