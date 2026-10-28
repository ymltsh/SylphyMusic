# 更新与发布

发布与验收独立。`release.py` 只处理版本、构建、签名、私密内容扫描、打包上传和清单更新；不执行分析、测试、启动冒烟或设备验收，也不读取验收复选框阻断发布。验证命令见 [CONTRIBUTING](CONTRIBUTING.md)，后续事项见 [独立验收待办](docs/RELEASE_GATES.md)，历史证据见 [PROGRESS](docs/PROGRESS.md)。

1.0 分发 Android 三种 ABI APK、Windows 安装 EXE 和便携 ZIP，Linux 暂缓。Android 使用固定正式证书，Windows 暂未代码签名。维护者确认测试版未实装，本次按全新安装处理；旧测试签名与正式证书不同，不能直接覆盖安装。

## 发布三步

在工程根目录执行。先装好 Flutter、Python 3.11+、Android SDK / JDK、Visual Studio C++ 工具和 Inno Setup 6，并配置 Git 作者及 GitHub 凭据。退出运行中的播放器，脚本不会强行结束用户进程。Android 本机密钥配置见 [正式签名与备份](docs/ANDROID_SIGNING.md)；密钥、密码和 `.private/` 内容不要加入 Git。

```powershell
# 1. 构建、签名核验、扫描、打包；替换本次版本、构建号和说明文件
python release.py --version 1.0.0 --build 12 --notes-file .private/release-1.0-notes.txt
# 2. 提交推送；新增源码 / 文档也须显式 git add
git add -u
git commit -m "release: prepare 1.0.0"
git push origin main
# 3. 复用产物，发布正式 Release 并更新正式清单
python release.py --version 1.0.0 --build 12 --skip-build --publish --notes-file .private/release-1.0-notes.txt
```

默认只准备本地包，`--publish` 才写 GitHub。已有本次发布授权时直接完成，不重复确认。`--dry-run` 纯预览；无参数则交互输入。测试版在准备与发布命令中均增加 `--beta` 或 `--beta2`。新版本构建号必须递增，版本分量和 build 上限为 65535。

## 产物与上传

输出为 `build/releases/<version>-<build>/`：三份 APK、EXE、ZIP、`SHA256SUMS.txt`、本地 record 和候选清单。只上传五个安装资产和摘要文件。record 记录源码指纹、文件摘要和构建输入检查，不能代表功能验收通过。`--skip-build` 仅复用完全匹配的产物；源码变化须重新准备。`--skip-checks` 仅供跳过依赖检查 / 许可收集作本地排查，这类包不能发布。

使用过测试凭据时，准备和发布均为每份文件增加 `--credentials-file 文件路径`，仅做源码与包内容扫描，不输出或打包凭据。不要把密码放进参数或 `--dart-define`。Android 必须通过公共证书匹配，拒绝测试签名 / unsigned 环境开关。Windows ZIP 保留运行依赖；安装目录为 `%LOCALAPPDATA%\Programs\Sylphy Music`，卸载不删除应用数据。

发布要求工作区干净、源码已推送；脚本不自动提交源码。Token 从 `GH_TOKEN` / `GITHUB_TOKEN` 或已有 Git 凭据读取，不接受命令行 Token。Tag 如 `v1.0.0+12`：先草稿上传，全部成功后公开，再更新所选渠道清单。发布后核对六个远端资产的大小 / SHA-256 和清单，再 `git pull --ff-only` 同步清单提交。

失败不盲目重试；核对草稿和本地产物后恢复，只补缺失资产，不覆盖已有文件：

```powershell
python release.py --version 1.0.0 --build 12 --skip-build --publish --resume --notes-file .private/release-1.0-notes.txt
```

源码、标签、资产摘要或清单冲突会停止。`--no-push-manifest` 只发布资产，不推进 App 更新提示。

## App 手动更新

设置 → 应用与支持 → 检查更新；启动和进入页面不主动检查。清单分别为 [正式版](https://raw.githubusercontent.com/ymltsh/SylphyMusic/main/version.json) 与 [测试版](https://raw.githubusercontent.com/ymltsh/SylphyMusic/main/version-beta.json)，历史记录由工具保留。版本来自安装包，按三段数字、beta → beta2 → 正式版、构建号比较；Windows 预发布通过 `SYLPHY_RELEASE_VERSION` 保留后缀。

清单和下载使用 API 设置中的 GitHub 加速前缀，默认 `https://hub.wgen.top/`，失败不回退原始地址。请求限时 12 秒、清单上限 1 MiB，不发送音源凭据；下载打开浏览器，不静默安装。下载和发布页仅接受本项目 GitHub Release 下的 HTTPS 地址。
