# 开发与构建指南

先读 [AGENTS](AGENTS.md) 和 [架构说明](docs/ARCHITECTURE.md)。按维护者要求，编译成功即可交付，功能验证和设备验收由用户负责。默认不运行静态分析、测试、启动冒烟或设备检查，也不追修历史验证失败；用户明确要求时才执行验证。

## 环境

已验证 Flutter 3.47.8 stable / Dart 3.13.7；Android 使用 JDK 17、Gradle 9.3.1、AGP 9.1.0；Windows 需要 Visual Studio C++ 工具。以锁文件和构建配置为准，不用 `flutter create` 重建已有 Runner。

在仓库根目录执行：

```powershell
./tool/bootstrap.ps1
flutter pub get --enforce-lockfile
flutter run -d windows
```

有意更新依赖时同步修改锁文件并说明原因，不为消除升级提示无差别更新。Linux 依赖见 README 和 CI；本机验收暂缓，不以配置准备完成宣称通过。

## 构建与交付

修改代码后按涉及的平台编译，修复编译错误直至构建成功，然后交付产物供用户测试：

```powershell
flutter build apk --release --split-per-abi
flutter build windows --release
# 一次构建并打包 Android / Windows
./tool/build_review.ps1
```

使用 `dart format` 保持改动文件的风格。仅文档或流程配置变更不重建应用。默认不新增验证测试或运行 analyze/test；编译成功不代表功能或设备验证通过。

已有 `test/`、`integration_test/` 和 `tool/check_local.ps1` 保留为用户主动验证工具，不属于日常开发、交付或发布流程。验收参考见 [TEST_PLAN](docs/TEST_PLAN.md)，历史结果见 [PROGRESS](docs/PROGRESS.md)。

## 私密联调

以下仅供用户主动联调时参考，默认不执行。环境变量指向私密三行文件：URL、用户名、密码。不要输出内容或把真实密码作为命令参数。

| 环境变量 | 用途 |
|---|---|
| `SYLPHY_EMBY_CREDENTIAL_FILE` | Emby 只读和歌词验证 |
| `SYLPHY_SUBSONIC_TEST_FILE` | 隔离的本机 Navidrome：包含临时歌单 CRUD，测试仅接受回环地址 |
| `SYLPHY_WEBDAV_CREDENTIAL_FILE` | WebDAV 只读验证 |

```powershell
$env:SYLPHY_WEBDAV_CREDENTIAL_FILE = '.private/webdav-credentials.txt'
flutter test test/live_webdav_test.dart
Remove-Item Env:SYLPHY_WEBDAV_CREDENTIAL_FILE
```

Emby 写测试还要求 `SYLPHY_ALLOW_TEST_PLAYLIST_WRITES=1`，且须在用户授权范围内，只操作脚本新建的临时歌单。参阅 [Emby 测试说明](docs/EMBY_TEST_SETUP.md)。

## 内部打包

```powershell
./tool/build_review.ps1
# 本轮使用过私密联调时，传入全部对应凭据文件做内容扫描
./tool/build_review.ps1 -CredentialFile @('.private/emby-credentials.txt', '.private/webdav-credentials.txt')
```

脚本重建主入口的 Android Release / split-per-ABI 和 Windows Release，输出到 `build/internal-review/`。无正式密钥时明确使用本机测试签名，有正式配置时优先采用。它不是正式发布流程。

集成测试会覆盖构建输出，打包保留正常 pub / 插件注册生成过程，不手改生成文件。Windows ZIP 完整解压，保留 DLL 和 data。修改原生依赖或发布范围时复核 [原生依赖记录](docs/NATIVE_DEPENDENCIES.md)，需要时执行 `python tool/collect_licenses.py`。

编译失败保留脱敏日志并修复编译问题；成功后报告改动、编译结果和产物位置，交给用户验证。
