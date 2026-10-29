# 原生媒体依赖记录

2026-10-29：`audio_service` 0.18.19 改为仓库内 `third_party/audio_service` 路径依赖，保留上游运行源码及 MIT 许可证。唯一原生改动是 Android 10 / API 29 的媒体通知调用 `setColorized(false)`，用于避免封面取色导致操作图标对比度不足；其他系统版本沿用上游行为。来源摘要和维护说明见 [本地补丁记录](../third_party/audio_service/SYLPHY_PATCHES.md)。

记录日期：2026-10-27。以下为当前调试构建实际加载的库及上游构建配置证据，不能代替完整的分发许可验收。

| 平台 | 运行时版本 | 已观察配置 |
|---|---|---|
| Windows x64 | mpv `v0.36.0-403-g652a1dd907`，FFmpeg `n6.0` | mpv `-Dgpl=false` |
| Android API 35 x86_64 | mpv `0.35.1-dirty`，FFmpeg `n6.0` | mpv `--enable-lgpl --disable-cplayer` |
| Linux | 尚未执行本机构建 | 使用系统 libmpv，实际版本需由发行构建补录 |

Windows 当前 `libmpv-2.dll` SHA-256：

```text
0A5A0B476866C91A639A4E511E8153968F8FA23564461B0AA09ACDBA816164A4
```

运行时记录由 `integration_test/desktop_test.dart` 的 `SYLPHY_NATIVE_AUDIT=true` 开关读取，只输出组件版本与配置，不输出服务器地址或凭据。

已检查上游源代码：

- [media-kit/libmpv-win32-audio-build](https://github.com/media-kit/libmpv-win32-audio-build)：`packages/mpv.cmake` 使用 `-Dgpl=false`；`packages/ffmpeg.cmake` 使用 `--disable-gpl --enable-version3`，FFmpeg 引用提交 `ea3d24bbe3c58b171e55fe2151fc7ffaca3ab3d2`。
- [media-kit/libmpv-android-audio-build](https://github.com/media-kit/libmpv-android-audio-build)：`buildscripts/scripts/mpv.sh` 使用 `--enable-lgpl`；`buildscripts/scripts/ffmpeg.sh` 使用 `--disable-gpl --disable-nonfree --enable-version3`；`buildscripts/include/depinfo.sh` 标明 FFmpeg 6.0、mpv 0.35.1。

尚需核对最终二进制与对应源码 / 构建补丁、全部传递依赖、许可证和告知文件，以及可替换 / 重链接要求。配置中的 GPL 开关本身不足以完成这些核对。Android arm64 真机库也需补录；当前模拟器结果不能替代所有 ABI 的验收。

`tool/collect_licenses.py` 已收集 117 个已解析 Dart / Flutter 包的许可证，见 `THIRD_PARTY_LICENSES.txt`；这份清单与原生依赖审计分开维护。

已补入 mpv、FFmpeg、Android libxml2 / mbedTLS 的上游许可与版权文本，具体引用见 [native_licenses/README.md](native_licenses/README.md)，内部 Windows 验收包同步包含这些文本。

进一步追溯发现：Windows 二进制发布标签 `2023-09-24` 对应的仓库提交 `f0f6ac7483396f345820660176cc84e2dd6ba220` **只有 version 文件**，并非完整构建输入快照。发布页标明 mpv 提交 `652a1dd90711839acdccc08004056d25514ef2d8`，但不能据此还原全部静态依赖。当前 master 配方仅作调查线索，不能视为该历史二进制的对应源码证明。正式分发前需要获得完整可核对的历史构建输入，或自行从固定源码和补丁重建；现有机器还缺少该交叉构建所需的 Linux 环境。

Android 发布标签 `v1.1.8` 对应构建仓库提交 `87744be8b337c50ed54961249b7a97c5e8cc37c9`；该引用可直接读取脚本和补丁，版本表标明 mbedTLS 3.6.1、libxml2 2.10.3、FFmpeg 6.0、mpv 0.35.1。仍需对实际各 ABI 库与构建输入逐一核对。
