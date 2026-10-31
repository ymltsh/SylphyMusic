# 开发与构建指南

先读 [AGENTS](AGENTS.md) 和 [架构说明](docs/ARCHITECTURE.md)。按维护者要求，编译成功即可交付，功能验证和设备验收由用户负责。默认不运行静态分析、测试、启动冒烟或设备检查，也不追修历史验证失败；用户明确要求时才执行验证。

面向用户的功能、下载与使用说明维护在 [README](README.md)。本文承接环境、运行、编译、验证与打包事宜。

## 环境

已验证 Flutter 3.47.8 stable / Dart 3.13.7。Android 使用 JDK 17、Gradle 9.3.1、AGP 9.1.0 与内建 Kotlin；Windows 需要 Visual Studio C++ 工具；Linux 需要 GTK3、libsecret、libmpv 及 Flutter 的桌面构建依赖。以锁文件和构建配置为准。

Android、Windows、Linux 三个平台的 Runner 已包含自定义媒体会话、托盘和缓存服务，**不要运行 `flutter create` 覆盖它们**；`tool/bootstrap_platforms.py` 只检查必要文件是否齐全，不生成 Runner。`pubspec.lock` 与 CI 固定构建输入；有意更新依赖时同步修改锁文件并说明原因，不为消除升级提示无差别更新。

## 运行

在仓库根目录执行：

```powershell
./tool/bootstrap.ps1
flutter pub get --enforce-lockfile
flutter run -d windows
```

```sh
./tool/bootstrap.sh
flutter run -d linux
```

Linux 真实构建与运行仍暂缓，不以配置准备完成宣称通过。首次启动可连接 Emby / Navidrome / OpenSubsonic / WebDAV 来源、导入本地音乐，或跳过引导；之后在右上角「设置 → 音乐源管理」中增删来源。

## 构建与交付

修改代码后按涉及的平台编译，修复编译错误直至构建成功，然后交付产物供用户测试：

```powershell
flutter build apk --release --split-per-abi
flutter build windows --release
# 一次构建并打包 Android / Windows
./tool/build_review.ps1
```

使用 `dart format` 保持改动文件的风格。仅文档或流程配置变更不重建应用。默认不新增验证测试或运行 analyze/test；编译成功不代表功能或设备验证通过。

已有 `test/`、`integration_test/` 和 `tool/check_local.ps1` 保留为用户主动验证工具，不属于日常开发、交付或发布流程；历史结果见 [PROGRESS](docs/PROGRESS.md)。

## 用户自主验证（可选）

以下命令仅供用户主动验证，开发、交付与发布流程默认不执行，也不因历史验证失败追加修复：

```sh
flutter analyze
flutter test
flutter test integration_test/desktop_test.dart -d windows
flutter test integration_test/desktop_test.dart -d emulator-5580
flutter test integration_test/large_library_test.dart -d windows
flutter test integration_test/large_library_test.dart -d emulator-5580
```

原生测试会创建临时数据目录，使用自行生成的音频，默认不连接私人服务器。纯单元测试中的 libmpv 用例需要先构建 Windows Debug，或设置 `SYLPHY_MPV_LIBRARY` 指向本机 libmpv。Linux 无显示环境的集成测试使用 Xvfb 和 `--dart-define=SYLPHY_HEADLESS_AUDIO=true`。集成测试会覆盖构建输出，完整验收清单见 [TEST_PLAN](docs/TEST_PLAN.md)。

### Windows 测试进程的原生指针隔离

项目根目录 `flutter_test_config.dart` 在每个 Windows 测试工作进程启动前、结束后清理仅属于当前 PID 的 media_kit 调试指针文件。media_kit 1.2.6 的 NativeReferenceHolder 文件名只包含 PID；Windows 复用旧进程号时，残留地址不属于新进程，曾导致 flutter_tester 原生访问违规并出现 `did not complete`。清理发生在测试 main / MediaKit 初始化之前，不删除其他进程的文件，不跳过原生播放或歌词测试；正常 Release 不使用这一调试指针文件。升级 media_kit 后应复核其文件命名 / 生命周期。

`test/native_test_config_test.dart` 覆盖陈旧指针、异常退出清理及无关文件保留。若原生集成测试默认应用目录或 TEMP 遭遇本机 ACL 拒绝访问，按媒体资源文档将当前命令的 TEMP / TMP 和 `SYLPHY_ASSET_TEST_ROOT` 指向项目内独立目录，无需修改系统权限。

## 私密联调

以下仅供用户主动联调时参考，默认不执行。真实服务器测试默认跳过；凭据由环境变量指向私密三行文件（URL、用户名、密码），不把密码放入命令行、`--dart-define` 或源码，也不输出文件内容。

| 环境变量 | 用途 |
|---|---|
| `SYLPHY_EMBY_CREDENTIAL_FILE` | Emby 只读测试与歌词验证 |
| `SYLPHY_WEBDAV_CREDENTIAL_FILE` | WebDAV 只读测试 |
| `SYLPHY_SUBSONIC_TEST_FILE` | 隔离的本机 Navidrome：包含临时歌单 CRUD，测试仅接受回环地址 |
| `SYLPHY_ALLOW_TEST_PLAYLIST_WRITES=1` | 仅在用户明确批准后启用临时 Emby 歌单写入测试 |

```powershell
$env:SYLPHY_WEBDAV_CREDENTIAL_FILE = '.private/webdav-credentials.txt'
flutter test test/live_webdav_test.dart
Remove-Item Env:SYLPHY_WEBDAV_CREDENTIAL_FILE
```

Emby 写测试还要求 `SYLPHY_ALLOW_TEST_PLAYLIST_WRITES=1`，且须在用户授权范围内，只操作脚本新建、以 `Sylphy Test` 开头的临时歌单并最终清理。参阅 [Emby 测试说明](docs/EMBY_TEST_SETUP.md)。

真实服务器测试文件：`test/live_emby_test.dart`、`test/live_emby_write_test.dart`、`test/live_subsonic_test.dart`。Android 私密联调可用 `tool/private_fixture_server.py` 提供一次性本机读取，原始密码不编入 APK。

## 内部打包

```powershell
./tool/build_review.ps1
# 本轮使用过私密联调时，传入全部对应凭据文件做内容扫描
./tool/build_review.ps1 -CredentialFile @('.private/emby-credentials.txt', '.private/webdav-credentials.txt')
```

脚本重新构建普通入口的 Windows Release 与 Android Release / 分架构 APK，调用 `tool/package_review.py --mode optimized` 检查已跟踪源码和包内容中的已知私密值，输出到 `build/internal-review/`。无正式密钥时明确使用本机测试签名，有 `android/key.properties` 时优先采用其配置。它不是正式发布流程，正式发布另用 `release.py`，不要求先执行内部验收。

当前 Android arm64 内部包 **32.9 MB**（原通用 Debug **207.5 MB**），Windows Release 压缩包 **23.7 MB**（原 Debug **55.4 MB**）。旧版 32 位 ARM 手机选 `armeabi-v7a`，x86_64 用于对应设备 / 模拟器。Windows ZIP 完整解压后运行 `sylphy_music.exe`，同目录 `README-optimized.txt` 与 `SHA256SUMS-optimized.txt` 提供说明及摘要。

集成测试会覆盖构建输出，打包保留正常 pub / 插件注册生成过程，不手改生成文件。修改原生依赖或发布范围时复核 [原生依赖记录](docs/NATIVE_DEPENDENCIES.md)，需要时执行 `python tool/collect_licenses.py`。

## 验收与发布边界

- 持续跟进：Linux 真实构建与运行、Android 实机来电 / 蓝牙 / 耳机与后台限制、更多只读 / 权限撤销 / 并发冲突场景，以及原生媒体依赖的完整分发许可证审计，见 [验收记录](docs/RELEASE_GATES.md)。
- Android 正式签名已配置；真实 Emby 临时歌单 CRUD 已通过。是否推送或发布以维护者当前指令为准。
- Emby 歌词的格式转换、旧缓存升级与手动导入优先级见 [Emby 歌词](docs/EMBY_LYRICS.md)，不同服务端版本的转换兼容性仍需继续验证。服务器不提供稳定身份时，不允许在旧来源身份下更换 OpenSubsonic 地址，需添加独立来源来隔离旧缓存和歌单。
- 更新检查与发布流程见 [更新与发布](update.md)：App 启动不主动检查，用户在「设置 → 检查更新」触发；构建、打包、发布和清单推送由一条命令完成，源码提交单独处理。
- 自有代码使用 MIT。原生 libmpv / FFmpeg 等依赖的许可须分别核实，MIT 不覆盖它们的分发义务。
- 不要把测试凭据、私有服务器地址、原始音乐、签名密钥或 `.private/` 内容提交到公共仓库。

编译失败保留脱敏日志并修复编译问题；成功后报告改动、编译结果和产物位置，交给用户验证。
