# 更新发布流程

默认构建 Android APK、Windows 安装程序和便携包，创建 GitHub Release，更新并只提交推送对应的版本清单。源码提交单独处理。

## 一、检查更新接口

| 项目 | 地址 |
| --- | --- |
| 正式清单 | https://raw.githubusercontent.com/ymltsh/SylphyMusic/main/version.json |
| 加速地址（默认） | https://hub.wgen.top/https://raw.githubusercontent.com/ymltsh/SylphyMusic/main/version.json |
| OpenList 清单 | https://raw.githubusercontent.com/ymltsh/SylphyMusic/main/version-openlist.json |
| OpenList 加速地址 | https://hub.wgen.top/https://raw.githubusercontent.com/ymltsh/SylphyMusic/main/version-openlist.json |
| 测试清单 | 将文件名换为 version-beta.json |
| 发布页 | https://github.com/ymltsh/SylphyMusic/releases/latest |

App 启动不主动检查；用户在“设置 → 关于风灵音乐 → 检查更新”读取清单，比较安装包版本号和构建号，展示更新说明和下载按钮。加速前缀可在 API 设置修改，失败不回退原始地址。

清单包含 `latest` 和 `history`。`latest` 使用 `version`、`build`、`name`、`date`、`notes`、`urls`、`page`；下载字段为 `android_arm64`、`android_armv7`、`android_x64`、`windows`、`windows_portable`。旧版 latest 自动进入 history。

## 二、版本发布流程

前提：Git 能推送 main；Flutter、Android SDK / JDK、Visual Studio C++ 和 Inno Setup 6 已安装；Android 正式签名已配置。签名文件按 [ANDROID_SIGNING](docs/ANDROID_SIGNING.md) 保留在本机。

### 0. 一键发布

普通版和 OpenList 特别版共用工作区根目录的 `release.py`。

更新版本 → 构建 Android / Windows → 打包 EXE / ZIP → 上传 GitHub Release → 更新版本清单 → 只提交并推送清单。

脚本上传时核对附件大小与 SHA-256，发布后核对 Release 状态、标题、正文和全部附件。正式版确认 GitHub Latest，OpenList 确认普通版 Latest。清单推送后，脚本核对原始和加速入口的 `latest` 完整内容。

发布并推送清单后，脚本分别报告两项进度。如果清单入口在重试期间仍未返回目标版本，脚本列出待核对的地址，输出可直接执行的 `--verify-only` 命令，退出码为 2。该命令只读取公开清单，可在缓存刷新后再次执行。全部核对通过时退出码为 0，发布步骤发生错误时退出码为 1。使用 `--no-push` 时，发布结果以 Release 已发布、本地清单已更新为准。

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
| --openlist | 发布 Android ARM64 OpenList 特别版 |
| --name / --notes | 标题 / 发布说明；--notes-file 可读取多行说明 |
| --dry-run | 只预览 |
| --skip-build | 复用本版本目录中已准备的附件 |
| --openlist-source-archive | 指定与 APK 内置 OpenList 库对应的后端及前端源码 ZIP |
| --verify-only | 只核对选定频道的远程清单，可用版本号和构建号限定目标 |
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

Tag 如 `v1.0.1+13`，上传上述资产。Android 使用正式签名，Windows 当前未代码签名。上传失败时草稿会保留，可按日志中的 Release ID 查看当前状态。

#### Release 描述规范

Release 标题和正文面向使用应用的用户，说明本版本新增了什么、修复了什么、体验有哪些变化，以及必要的使用或升级提示。使用直白的用户语言，描述可感知的行为与影响；不把实现细节或内部工作记录当作更新内容，也不将未经验证的效果写成已确认事实。普通版与 OpenList 特别版均遵守此规范，版本清单中的更新说明同步采用面向用户的文案。

Release 描述不得出现开发性描述，包括编译 / 打包 / 上传过程、签名配置、静态分析 / 测试 / 设备验收的执行情况、补丁合入 / 分支同步 / 提交记录，以及“按要求完成”等内部协作措辞。这些信息仅记录在本地交付汇报、构建日志或 `docs/PROGRESS.md` 中。

例如，不得写“Android 使用既有正式签名。本轮按要求完成编译、打包与发布，未运行静态分析、测试或设备验收。”；后台播放恢复的更新说明可写为“改进后台播放的异常恢复，减少歌曲加载或切换时长时间停滞的情况。”。发布前检查最终标题、正文和清单更新说明，删除开发过程描述。

### 4. 更新版本清单

正式版更新 `version.json`，Beta / Beta2 更新 `version-beta.json`；旧 latest 放入 history 头部。工具仅提交并推送该清单，不提交源码、签名文件或其他改动。

### 5. 查看更新接口

```powershell
Invoke-RestMethod "https://hub.wgen.top/https://raw.githubusercontent.com/ymltsh/SylphyMusic/main/version.json"
```

确认 latest 是新版本、下载链接对应已上传资产即可。

## OpenList 独立清单

`main/version-openlist.json` 是 OpenList 独立更新入口，结构与 `version.json` 相同，保存特别版的 latest / history，仅指向特别版附件。普通版仍读取 main/version.json。OpenList 客户端正式更新读取新入口；测试更新仍使用 feature/android-openlist-lite/version-beta.json。

两分支均保存 version-openlist.json。旧 feature/android-openlist-lite/version.json 继续保留，供既有安装包使用。后续发布 OpenList 时，将其更新后的 version.json 同步到两分支的 version-openlist.json，并只提交、推送对应清单；普通版发布不覆盖 OpenList 清单。新增接口本身不改变版本号或已发布附件。

从 `sylphy_music_feature` 运行以下命令。脚本会构建并检查正式签名的 ARM64 APK，打包对应源码，以 GitHub 预发布形式上传附件，并同步三个 OpenList 清单。与所属远程分支同步的工作区可以只推送本次生成的清单提交。

```powershell
python release.py --openlist --version 1.0.78-openlist.59 --build 91 --dry-run
python release.py --openlist --version 1.0.78-openlist.59 --build 91 --notes-file .private/openlist-notes.md
python release.py --openlist --verify-only
```

脚本在本地上一次发布目录查找 APK 和 OpenList 源码 ZIP。若两版 APK 内的 OpenList 原生库一致，就复用上版 ZIP 中的 OpenList 后端和前端源码，并打包当前应用源码。若缺少上版附件或原生库已更新，传入 `--openlist-source-archive` 指定对应源码 ZIP，其中应包含 `OpenList/` 后端及 `OpenList-Frontend-*-source.tar.gz`。若当前版本的 APK 和完整源码 ZIP 都已准备好，可用 `--skip-build` 直接复用。

普通版可在 `sylphy_music` 执行 `python release.py --verify-only` 核对当前正式版清单，或加 `--beta` 核对测试清单。
