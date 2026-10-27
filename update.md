# 风灵音乐更新与发布流程

参考 Mfuns Flutter 的发布体系，接入手动检查更新、分渠道清单、Android 分 ABI APK、Windows 安装程序 / 便携 ZIP、SHA-256 与 GitHub Release。发布工具为根目录 `release.py`，Python 部分仅依赖标准库。

**首个测试签名版本 0.2.1+3 已于 2026-10-28 发布到 GitHub Release。** `version.json` 指向该版本的三个 Android APK；`version-beta.json` 的 `latest` 仍为 `null`。该版本使用本机 Android Debug 测试证书，仅用于内部测试和自用更新，不是正式签名发布。正式发布仍需生产签名并通过发布门槛；后续切换到生产签名可能需要卸载重装。现有内部验收继续用 `tool/build_review.ps1`。

## App 手动检查更新

设置 → 应用与支持 → 检查更新。启动和进入此页均不主动访问更新服务器，点击按钮后才请求；可切换测试版渠道。应用版本从实际安装包读取，不维护第二套硬编码版本常量。Windows 预发布包另由构建参数 `SYLPHY_RELEASE_VERSION` 保留 beta 后缀，构建号仍读安装包。

| 用途 | 地址 |
|---|---|
| 正式版源清单 | https://raw.githubusercontent.com/ymltsh/SylphyMusic/main/version.json |
| 正式版加速清单 | https://hub.wgen.top/https://raw.githubusercontent.com/ymltsh/SylphyMusic/main/version.json |
| 测试版清单 | 上述两种地址的文件名换为 `version-beta.json` |
| 发布页 | https://github.com/ymltsh/SylphyMusic/releases/latest |

优先使用加速清单，读取失败回退 GitHub 原始地址；每次请求限时 12 秒，清单最大 1 MiB。不发送音乐源信息或凭据。版本比较先按三段数字，再按 beta → beta2 → 正式版，最后比较构建号。旧版本不会被作为更新提供；正式渠道拒绝预发布清单。下载按钮按当前平台显示，打开浏览器后由用户下载 / 安装，不在应用内静默安装。下载与发布页链接仅接受本项目 GitHub releases 下的 HTTPS 地址。

## 清单格式

```json
{
  "latest": {
    "version": "0.2.1",
    "build": 3,
    "name": "风灵音乐 v0.2.1",
    "date": "2026-10-28",
    "notes": "更新说明\n第二行",
    "urls": {
      "android_arm64": "https://github.com/ymltsh/SylphyMusic/releases/download/v0.2.1%2B3/sylphy-music-0.2.1-3-arm64-v8a.apk",
      "android_armv7": "https://github.com/ymltsh/SylphyMusic/releases/download/v0.2.1%2B3/sylphy-music-0.2.1-3-armeabi-v7a.apk",
      "android_x64": "https://github.com/ymltsh/SylphyMusic/releases/download/v0.2.1%2B3/sylphy-music-0.2.1-3-x86_64.apk",
      "windows": "https://github.com/ymltsh/SylphyMusic/releases/download/v0.2.1%2B3/sylphy-music-setup-0.2.1-3.exe",
      "windows_portable": "https://github.com/ymltsh/SylphyMusic/releases/download/v0.2.1%2B3/sylphy-music-windows-0.2.1-3.zip"
    },
    "page": "https://github.com/ymltsh/SylphyMusic/releases/tag/v0.2.1+3"
  },
  "history": []
}
```

以上只是格式示例，不代表这些包已存在。`latest` 也可为 `null`；`version` / `build` / `name` 必填，`date` / `notes` / `urls` / `page` 可省略。App 兼容单一 APK 的 `urls.android`，本项目发布工具生成三种 ABI 链接。测试版的 version 分别为 `0.2.1-beta` / `0.2.1-beta2`，写入独立测试版清单。历史保留完整旧条目，去重后由新到旧保存。

## 本地准备

前提：Flutter、Python 3.11+、Visual Studio C++ 构建工具、Android SDK / JDK 17、Inno Setup 6。可设置 `FLUTTER_BIN` 和 `INNO_SETUP_COMPILER` 指向工具。Windows 编译前手动退出运行中的播放器；脚本不会强行结束用户进程。

Android Release 必须已有 `android/key.properties` 与对应私有签名密钥；脚本拒绝测试签名 / unsigned 环境开关，不生成或记录密钥。签名文件继续由 `.gitignore` 排除。Windows 安装程序定义在 `installer/windows/SylphyMusic.iss`，按当前用户安装到 `%LOCALAPPDATA%\Programs\Sylphy Music`，提供开始菜单、可选桌面快捷方式和卸载项；安装 / 卸载不删除应用数据目录。便携 ZIP 保留全部运行依赖。

```powershell
# 纯预览，不改版本、不构建、不访问 GitHub
python release.py --version 0.2.1 --build 3 --dry-run

# 仅本地：同步 pubspec 版本，analyze/test，构建，扫描，打包
python release.py --version 0.2.1 --build 3 --notes-file .private/release-notes.txt
python release.py --version 0.2.1 --build 3 --beta --notes "测试版说明"
python release.py --version 0.2.1 --build 3 --beta2 --notes "第二轮测试说明"

# 无参数时交互输入，仍仅准备本地包
python release.py
```

构建号建议始终显式指定。未指定时：版本完全相同沿用当前号，切换版本 / 渠道则使用当前号 +1，避免重复运行漂移。新版本不能复用旧版本构建号或倒退；版本各段和 build 最大 65535，满足 Windows 资源字段限制。

如本轮使用过真实测试凭据，添加每一份 `--credentials-file .private/文件名.txt` 做源码、APK 内部文件及 Windows 内容扫描，不会输出或打包该文件。不要将凭据内容写到参数中。

产物位于 `build/releases/<version>-<build>/`，包含三种 APK、安装 EXE、便携 ZIP、`SHA256SUMS.txt`、本地 `release-record.json` 和对应渠道的候选清单。普通发布仅上传五个安装资产和摘要文件。record 保存源码指纹、产物摘要与检查结果；`--skip-build` 只复用版本 / 构建号 / 源码 / 文件摘要均匹配的产物。`--skip-checks` 仅用于本地排查，这类包不能发布。签名和许可证仍须满足[发布门槛](docs/RELEASE_GATES.md)，有未完成项目时正式版发布会被拒绝。

## 经授权后发布 GitHub

源码提交和推送由开发者单独处理；发布工具不自动提交源码。先准备本地包、审阅结果，再将对应源码和 pubspec 版本提交并推送到 GitHub。提交前后文件内容一致即可复用已准备产物；提交后另改源码则必须重新构建。

Token 从 `GH_TOKEN` / `GITHUB_TOKEN` 或已有 Git 凭据读取，不接受命令行 Token 参数，不输出 Token。需要目标仓库 Contents 写权限。脚本要求工作区干净且当前 HEAD 已可从 GitHub 访问，确保 Release tag 对应实际源码。初始两份清单须已在 `main` 上。

```powershell
# 仅在已获发布授权、源码已提交推送之后执行
python release.py --version 0.2.1 --build 3 --skip-build --publish --notes-file .private/release-notes.txt

# 测试版发布
python release.py --version 0.2.1 --build 3 --beta --skip-build --publish --notes-file .private/release-notes.txt
```

Tag 包含构建号，例如 `v0.2.1+3` / `v0.2.1-beta+3`，同语义版本的不同构建不会覆盖。工具先创建草稿并上传、全部成功后公开 Release，最后通过 GitHub Contents API 创建只修改所选渠道清单的提交；不会推送本地其他提交或文件。调用顺序基于 [GitHub Release API](https://docs.github.com/en/rest/releases/releases) 和 [Contents API](https://docs.github.com/en/rest/repos/contents)。`--no-push-manifest` 可仅发布资产并保留候选清单供手动维护，App 不会收到这次更新。

远程写入失败不会盲目重试：上传失败保留草稿且不推进更新清单。核对现状后可继续同一批产物：

```powershell
python release.py --version 0.2.1 --build 3 --beta --skip-build --publish --resume --notes-file .private/release-notes.txt
```

恢复要求源码提交和 tag 匹配，已有资产的 GitHub SHA-256 / 大小必须匹配；只补传草稿中缺少的资产，不覆盖现有文件。已公开且文件完整时只补清单提交。遇到并发更新，清单 blob SHA 冲突会停止，不覆盖别人提交；若同版清单已更新则恢复命令直接结束。发布后本地仓库不会被强制重置；开发者自行拉取 `main` 上新生成的清单提交。

## 验证

```powershell
flutter analyze --no-pub
flutter test --no-pub test/app_updates_test.dart
python -m unittest discover -s test -p test_release_tool.py -v
flutter test integration_test/ui_refresh_test.dart -d windows
flutter build apk --debug
```

正式对外发布前，还需验证旧版能发现新版本、同版不提示更新、断网可重试、五个资产链接 / 摘要 / 签名正确、安装升级和卸载均保留用户数据。此文档描述流程，不构成执行发布、推送、登录或安装软件的授权。
