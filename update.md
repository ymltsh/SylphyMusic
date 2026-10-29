# 更新发布流程

默认构建 Android APK、Windows 安装程序和便携包，创建 GitHub Release，更新并只提交推送对应的版本清单。源码提交单独处理。

## 一、检查更新接口

| 项目 | 地址 |
| --- | --- |
| 正式清单 | https://raw.githubusercontent.com/ymltsh/SylphyMusic/main/version.json |
| 加速地址（默认） | https://hub.wgen.top/https://raw.githubusercontent.com/ymltsh/SylphyMusic/main/version.json |
| 测试清单 | 将文件名换为 version-beta.json |
| 发布页 | https://github.com/ymltsh/SylphyMusic/releases/latest |

App 启动不主动检查；用户在“设置 → 检查更新”读取清单，比较安装包版本号和构建号，展示更新说明和下载按钮。加速前缀可在 API 设置修改，失败不回退原始地址。

清单包含 `latest` 和 `history`。`latest` 使用 `version`、`build`、`name`、`date`、`notes`、`urls`、`page`；下载字段为 `android_arm64`、`android_armv7`、`android_x64`、`windows`、`windows_portable`。旧版 latest 自动进入 history。

## 二、版本发布流程

前提：Git 能推送 main；Flutter、Android SDK / JDK、Visual Studio C++ 和 Inno Setup 6 已安装；Android 正式签名已配置。签名文件按 [ANDROID_SIGNING](docs/ANDROID_SIGNING.md) 保留在本机。

### 0. 一键发布

根目录 `release.py` 自动执行：

更新版本 → 构建 Android / Windows → 打包 EXE / ZIP → 上传 GitHub Release → 更新版本清单 → 只提交并推送清单。

编译成功即可交付；流程不运行静态分析或测试，也不因历史验证失败追加修复。功能与设备验证由用户负责。

```powershell
# 引导模式
python release.py

# CLI 模式
python release.py --version 1.0.1 --build 13 --notes "更新说明"
python release.py --version 1.0.1 --build 13 --beta --notes "测试版"
python release.py --version 1.0.1 --build 13 --dry-run
```

| 参数 | 说明 |
| --- | --- |
| --version / --build | 版本号和构建号，建议显式指定 build |
| --beta / --beta2 | 预发布，更新 version-beta.json |
| --name / --notes | 标题 / 发布说明；--notes-file 可读取多行说明 |
| --dry-run | 只预览 |
| --skip-build | 复用本版本已生成的 APK / EXE / ZIP |
| --no-push | 发布资产并更新本地清单，不提交推送清单 |

Flutter 或 Inno 不在 PATH 时可设置 `FLUTTER_BIN` / `INNO_SETUP_COMPILER`。Token 自动使用 Git 凭据或 `GH_TOKEN` / `GITHUB_TOKEN`。关闭运行中的播放器，避免 Windows EXE 被占用。旧命令的 `--skip-checks` 参数仍兼容，但已无需传入；测试和验收由用户独立进行。

### 1. 更新版本号

工具更新 `pubspec.yaml`，如 `version: 1.0.1+13`。App 直接读取安装包版本，不维护第二套常量。新版本使用递增构建号。

### 2. 构建和打包

```powershell
flutter build apk --release --split-per-abi
flutter build windows --release
```

工具随后打包便携 ZIP，并调用 `installer/windows/SylphyMusic.iss` 生成安装程序。产物在 `build/releases/<version>-<build>/`：三个 ABI APK、Windows 安装 EXE、便携 ZIP 和 SHA256SUMS.txt。`--skip-build` 复用这些文件，不重新打包。

各版本目录和 Release Tag 继续保留版本号，上传附件统一使用固定名称：

| 平台 | 附件名称 |
| --- | --- |
| Android ARM64 | `sylphy-music-arm64-v8a.apk` |
| Android ARMv7 | `sylphy-music-armeabi-v7a.apk` |
| Android x86_64 | `sylphy-music-x86_64.apk` |
| Windows 安装版 | `sylphy-music-setup.exe` |
| Windows 便携版 | `sylphy-music-windows.zip` |

网站可使用 [Android ARM64 最新版](https://github.com/ymltsh/SylphyMusic/releases/latest/download/sylphy-music-arm64-v8a.apk) 和 [Windows 安装版最新版](https://github.com/ymltsh/SylphyMusic/releases/latest/download/sylphy-music-setup.exe) 的固定下载链接；需先发布包含这些附件的新正式 Release。现有历史附件不重命名。应用版本清单仍使用各自 Tag 下的固定文件名地址，避免历史版本链接跟随最新版变化；摘要文件记录实际固定名称。`--skip-build` 同样要求该版本目录下已有上述固定文件名。

### 3. 创建 GitHub Release

Tag 如 `v1.0.1+13`，上传上述资产。Android 使用正式签名，Windows 当前未代码签名。上传失败保留草稿，不推进清单。

### 4. 更新版本清单

正式版更新 `version.json`，Beta / Beta2 更新 `version-beta.json`；旧 latest 放入 history 头部。工具仅提交并推送该清单，不提交源码、签名文件或其他改动。

### 5. 查看更新接口

```powershell
Invoke-RestMethod "https://hub.wgen.top/https://raw.githubusercontent.com/ymltsh/SylphyMusic/main/version.json"
```

确认 latest 是新版本、下载链接对应已上传资产即可。
