# 飞牛音乐（fnOS Music）源接入：首期

本补丁针对 **NAS 上的官方「飞牛音乐」应用**，而不是将 Sylphy Music 安装成 fnOS 应用（`.fpk`）。

1. 在 NAS 上安装「飞牛音乐」，扫描曲库，在其管理页面内创建/启用**飞牛音乐独立账号**。
2. 在 Sylphy Music 中添加「飞牛音乐（fnOS）」源，服务器填 `https://NAS_HOST:PORT/music`（反向代理需要保留 `/music` 路由），填写飞牛音乐应用账号和密码。
3. 首期支持：认证、逐页曲库索引、歌曲 / 专辑 / 歌手聚合、音频播放（基础直连）、专辑封面、歌词、已有本地缓存、只读浏览飞牛云歌单（保留重复曲目）。
4. 暂未支持：FN Connect 的 FNID 自动寻址、中继专用 Cookie、网盘流跨源 302 跳转、服务端收藏与歌单写入、CUE 细粒度曲目定位和飞牛特殊音频转码。

安全设计：登录使用 SHA-256 密码摘要，令牌仅写入原有 SecureStorage；通过 `Cookie: music-token=...` 认证，不把令牌放进媒体 URL、SQL、日志；沿用 StrictTransport 严格 TLS 校验和禁止认证跳转的策略。不同服务器/账号以独立 SourceProfile 隔离。

**兼容性提示**：相关 `/music/api/v1/*` 接口来自社区逆向、并非由本补丁核实的稳定官方 SDK。工程编译记录见 [进度](PROGRESS.md)，实际 fnOS 设备的兼容性与功能验证由用户负责。

## 修改边界

- `lib/core/models.dart`：增加 `SourceKind.fnMusic`，并将云歌单可读与可写能力分离；不修改现有持久化来源值。
- `lib/services/sources.dart`：注册 `FnMusicAdapter`。
- `lib/services/fn_music.dart`：实现官方音乐应用协议客户端。
- `lib/core/app_controller.dart`：禁止编辑连接时悄然切换服务器；采用与 Emby 相同的 serverGUID / userGUID 稳定性核对。
- `lib/ui/music_source_ui.dart` / `lib/ui/music_source_connection_page.dart`：来源入口和使用提示。
- `lib/ui/app_shell.dart`：飞牛只读歌单不出现在新建云歌单/复制目标里。

所有更改不涉及数据库结构迁移和现有其他来源数据。

## 用户自主验证参考

登录、错误密码、凭据失效、服务器身份变化、账号更换；零曲目曲库、多页曲库、索引中断回滚；FLAC / MP3 Range / HEAD 播放；封面、LRC 歌词、缓存与断网恢复；NAS 代理、网盘源及 FN Connect 中继（这两者当前未实现，应给出提示而非不安全地转发 Cookie）。
