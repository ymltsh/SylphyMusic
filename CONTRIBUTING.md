# 开发与验证指南

先读 [AGENTS](AGENTS.md) 和 [架构说明](docs/ARCHITECTURE.md)。人工与设备验收独立进行；[发布工具](update.md) 只保留可用 `--skip-checks` 跳过的基础 analyze/test，不设置额外验收阻断。

## 环境

已验证 Flutter 3.47.8 stable / Dart 3.13.7；Android 使用 JDK 17、Gradle 9.3.1、AGP 9.1.0；Windows 需要 Visual Studio C++ 工具。以锁文件和构建配置为准，不用 `flutter create` 重建已有 Runner。

在仓库根目录执行：

```powershell
./tool/bootstrap.ps1
flutter pub get --enforce-lockfile
flutter run -d windows
```

有意更新依赖时同步修改锁文件并说明原因，不为消除升级提示无差别更新。Linux 依赖见 README 和 CI；本机验收暂缓，不以配置准备完成宣称通过。

## 相关验证

| 修改范围 | 检查 |
|---|---|
| 仅文档 | 链接、路径、命令与代码一致，不重建安装包 |
| Dart / UI | 格式、静态分析、相关单元 / Widget 测试 |
| 数据库 / 索引 | 迁移、失败 / 取消保留旧快照、分页 |
| 网络 / 来源 | 本机模拟服务、认证、错误和凭据边界；授权范围内真实联调 |
| 播放 / 缓存 / Runner | 原生测试、对应平台构建和设备验证 |

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --no-pub
# 首次先构建，以便 libmpv 单元测试加载本机原生库
flutter build windows --debug
flutter test --no-pub
flutter test integration_test/desktop_test.dart -d windows
flutter test integration_test/webdav_test.dart -d windows
flutter test integration_test/large_library_test.dart -d windows
```

Android 用 `flutter devices` 中明确选择的设备 ID 替换 `windows`，不要默认操作全部设备。无音频设备环境可为原生集成测试添加 `--dart-define=SYLPHY_HEADLESS_AUDIO=true`。保留已有微小原生时间舍入容差，身份、暂停和缓存完整性仍严格断言。

`./tool/check_local.ps1` 运行完整本地验收并重新打包；加 `-AndroidDevice <device-id>` 验证指定 Android 设备，耗时较长。最新证据见 [PROGRESS](docs/PROGRESS.md)，[TEST_PLAN](docs/TEST_PLAN.md) 是完整验收范围，未勾选不代表从未执行局部检查。

## 私密联调

真实服务器测试默认跳过。环境变量指向私密三行文件：URL、用户名、密码。不要输出内容或把真实密码作为命令参数。

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

失败保留脱敏日志，区分代码缺陷与环境不可用。交付说明记录实际变更、已执行检查和限制，不将模拟器结果写成物理设备验收。
