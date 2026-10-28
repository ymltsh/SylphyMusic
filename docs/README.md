# 文档索引

新增：[封面与歌词持久化](MEDIA_ASSETS.md)，包含 SQLite v6、缓存身份、后台刷新、手动歌词保护和旧文件迁移。

| 文档 | 用途 |
|---|---|
| [更新与发布流程](../update.md) | 手动更新、正式 / 测试版清单、本地打包与显式 GitHub 发布 |
| [项目 README](../README.md) | 运行、构建、功能与内部验收包 |
| [AGENTS](../AGENTS.md) | 协作约定、工程边界与私密数据 |
| [ARCH 入口](../ARCH.md) / [架构正文](ARCHITECTURE.md) | 模块、来源能力、数据流与生命周期 |
| [CONTRIBUTING](../CONTRIBUTING.md) | 环境、相关验证、私密联调和打包 |
| [PROJECT_SPEC_v3.8](PROJECT_SPEC_v3.8.md) | 产品目标，不代表全部实现或验收完成 |
| [IMPLEMENTATION_PLAN](IMPLEMENTATION_PLAN.md) | 实施计划与决策背景 |
| [PROGRESS](PROGRESS.md) | 最新证据、剩余工作和验收输出 |
| [TEST_PLAN](TEST_PLAN.md) | 完整真实环境验收清单 |
| [RELEASE_GATES](RELEASE_GATES.md) | 首次正式发布门槛 |
| [APPEARANCE](APPEARANCE.md) | 一级页自定义背景、可选主色、页面标题与连续列表 |
| [ANDROID_SYNC_FGS](ANDROID_SYNC_FGS.md) | 手动同步通知、引擎生命周期、暂停与系统时限 |
| [ANDROID_SYSTEM_BARS](ANDROID_SYSTEM_BARS.md) | Android 手势条透明沉浸、系统图标明暗与安全边距 |
| [UI_REFRESH](UI_REFRESH.md) | 本轮导航、首次引导、首页、播放器与外观调整范围 |
| [COVER_FLOW](COVER_FLOW.md) | 专辑 / 歌单封面流、分批数据接入与会话内视图切换 |
| [PLAYER_LAYOUT_EDITOR](PLAYER_LAYOUT_EDITOR.md) | 播放页全画布组件、9 / 16 宫格编辑、统一封面与歌词页、模板与迁移 |
| [DIAGNOSTIC_LOGGING](DIAGNOSTIC_LOGGING.md) | 用户主动启用的诊断日志、导出 / 分享与隐私边界 |
| [LAUNCHER_ICONS](LAUNCHER_ICONS.md) | Android 备用桌面图标、activity-alias 切换与资源生成 |
| [WEBDAV](WEBDAV.md) | 连接、扫描、歌词 / 封面与限制 |
| [EMBY_TEST_SETUP](EMBY_TEST_SETUP.md) | 专用测试账号与临时歌单验证边界 |
| [LRC_API](LRC_API.md) | 可选在线歌词补充、配置与缓存边界 |
| [EMBY_LYRICS](EMBY_LYRICS.md) | Emby 带时间歌词格式、旧缓存升级与手动导入优先级 |
| [NATIVE_DEPENDENCIES](NATIVE_DEPENDENCIES.md) | libmpv / FFmpeg 来源、许可与待办 |
| [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES.txt) | 已解析 Dart 依赖许可证 |
| [native_licenses](native_licenses/README.md) | 原生许可证文本与说明 |
| [测试音频](../test/fixtures/README.md) | 合成素材与用途 |

用户当前指令决定工作范围。需求与计划提供背景，代码说明当前实现，日志和进度记录实际验证，发布门槛约束正式交付。发现冲突时核对代码和用户已确认的变更，更新对应文档。
