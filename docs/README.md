# 文档索引

新增：[封面与歌词持久化](MEDIA_ASSETS.md)，包含 SQLite v6、缓存身份、后台刷新、手动歌词保护和旧文件迁移。

| 文档 | 用途 |
|---|---|
| [更新与发布流程](../update.md) | 手动更新、正式 / 测试版清单、本地打包与显式 GitHub 发布 |
| [Android 正式签名](ANDROID_SIGNING.md) | 正式证书、私钥备份、验签与测试版迁移限制 |
| [项目 README](../README.md) | 面向用户的功能、音源、下载、快速开始与技术栈 |
| [AGENTS](../AGENTS.md) | 协作约定、工程边界与私密数据 |
| [ARCH 入口](../ARCH.md) / [架构正文](ARCHITECTURE.md) | 模块、来源能力、数据流与生命周期 |
| [CONTRIBUTING](../CONTRIBUTING.md) | 环境、运行、编译交付、用户验证、私密联调、打包与验收边界 |
| [PROJECT_SPEC_v3.8](PROJECT_SPEC_v3.8.md) | 产品目标，不代表全部实现或验收完成 |
| [IMPLEMENTATION_PLAN](IMPLEMENTATION_PLAN.md) | 实施计划与决策背景 |
| [PROGRESS](PROGRESS.md) | 最新证据、剩余工作和验收输出 |
| [TEST_PLAN](TEST_PLAN.md) | 完整真实环境验收清单 |
| [RELEASE_GATES](RELEASE_GATES.md) | 独立验收待办，不属于发布流程 |
| [每日分时推荐与 LLM V14](DAILY_SLOTS_LLM_V14.md) | 刷新时段、两阶段请求、等待预算及成功标记 |
| [来信布局与导出 V13](LETTER_UI_V13.md) | 自拟信件标题、封面主题与导出选项、v13 迁移 |
| [音乐笔友角色彩蛋](PENPAL_CHARACTER_PRESETS.md) | 风精灵希露菲卡片、应用入口与提示词范围 |
| [与笔友聊天](PENPAL_CHAT.md) | 连续对话、主动观点与记忆管理 |
| [音乐笔友记忆 V15](PENPAL_MEMORY_V15.md) | 独立人格、轻量长期记忆、真实互动与管理入口 |
| [角色卡与隐藏彩蛋 V18](CHARACTER_CARDS_V18.md) | 稳定角色身份、彩蛋默认隐藏、独立聊天/记忆、角色编辑与删除 |
| [音乐笔友与来信存档](PENPAL_RECOMMENDATIONS.md) | 分段推荐信、SQLite v12 私人存档与独立清理 |
| [每日精选封面与提示词](RECOMMENDATION_SHOWCASE_PROMPT.md) | 首页 / 详情封面叠卡与自定义 LLM 推荐偏好 |
| [APPEARANCE](APPEARANCE.md) | 一级页自定义背景、可选主色、页面标题与连续列表 |
| [播放生命周期整合](INTEGRATED_PLAYBACK_LIFECYCLE.md) | 统一停滞恢复、实验性 AO 重载、前台系统观测与通知封面共享 |
| [媒体会话状态投影重构](MEDIA_SESSION_PROJECTION_REDESIGN_2026-11-09.md) | 暂停、焦点保持、缓冲、恢复及错误的统一媒体会话映射 |
| [播放与音频焦点重构](PLAYBACK_ARCHITECTURE_FOCUS_REFACTOR.md) | 临时失焦恢复资格、5 分钟前台保留及焦点申请边界 |
| [Android 后台恢复 V3](ANDROID_BACKGROUND_RESUME_V3.md) | 完整缓存恢复、实际进度检查、同曲有界重开与前台状态重申 |
| [Android 后台恢复 V2](ANDROID_BACKGROUND_RESUME_V2.md) | 媒体回调临时前台服务提升、拒绝重试与恢复进度诊断 |
| [后台暂停恢复补丁](BACKGROUND_RESUME_PATCH.md) | 远程暂停恢复、票据刷新、原生命令入队超时与用户验证建议 |
| [Android De-click 与诊断](ANDROID_DECLICK.md) | 样本包络、开关、原生日志及 A/B 边界 |
| [Media3 通知实施](MEDIA3_NOTIFICATION_IMPLEMENTATION.md) | 原生 mpv、单一 MediaLibraryService、Controller、缓存租约与当前边界 |
| [mpv + Media3 设计蓝图](ANDROID_MPV_MEDIA3_ARCHITECTURE.md) | 附件设计参考；实施范围以本轮实施说明为准 |
| [媒体通知设计](MEDIA_NOTIFICATION_DESIGN.md) | 单一媒体会话、真实进度时钟、标准 MediaStyle 与状态发布边界 |
| [ANDROID_SYNC_FGS](ANDROID_SYNC_FGS.md) | 手动同步通知、引擎生命周期、暂停与系统时限 |
| [ANDROID_SYSTEM_BARS](ANDROID_SYSTEM_BARS.md) | Android 手势条透明沉浸、系统图标明暗与安全边距 |
| [LLM 推荐增强](LLM_RECOMMENDATION.md) | 默认关闭的模型重排、推荐文案、API 配置与元数据发送边界 |
| [推荐设置](RECOMMENDATION_SETTINGS.md) | 基础推荐、LLM 增强、换新与数据分区及操作逻辑 |
| [RECOMMENDATION_V1](RECOMMENDATION_V1.md) | 每日精选、专辑推荐、数据统计和热榜缓存 |
| [UI_REFRESH](UI_REFRESH.md) | 本轮导航、首次引导、首页、播放器与外观调整范围 |
| [COVER_FLOW](COVER_FLOW.md) | 专辑 / 歌单封面流、分批数据接入与会话内视图切换 |
| [PLAYER_LAYOUT_EDITOR](PLAYER_LAYOUT_EDITOR.md) | 播放页全画布组件、9 / 16 宫格编辑、统一封面与歌词页、模板与迁移 |
| [DIAGNOSTIC_LOGGING](DIAGNOSTIC_LOGGING.md) | 用户主动启用的诊断日志、导出 / 分享与隐私边界 |
| [Android 完整缓存快速 AO 恢复 V4](ANDROID_CACHED_EARLY_AO_RECOVERY_V4.md) | 双样本停滞判定、复用本地输出快速重载与原有兜底 |
| [单曲循环 / 后台稳定性 V3](REPEATONE_BACKGROUND_STABILITY_V3.md) | 循环回绕进度基准修正与 2 秒 / 3 秒纯诊断采样；[分析](REPEATONE_BACKGROUND_STABILITY_V3_ANALYSIS.md) |
| [单曲循环 EOF 错误竞争](REPEAT_ONE_EOF_ERROR_RACE.md) | 曲尾错误短暂延迟、完成事件协调与旧重连任务失效 |
| [播放稳定性诊断 V2](PLAYBACK_STABILITY_DIAGNOSTICS_V2.md) | 通知 Play → FGS / 焦点 → mpv → AO 重载的关联日志及 ADB 双快照采集 |
| [后台持续播放学习清单](BACKGROUND_PLAYBACK_LEARNING.md) | 棉花音乐 APK 的代理探活 / 恢复证据、我们自身的风险与改进优先级；仅分析待办 |
| [分块缓存参考分析](FRAGMENT_CACHE_REFERENCE.md) | 片段 / 空洞、范围写锁、滚动提交、LRU 与完整文件迁移，以及现有缓存的升级建议 |
| [LAUNCHER_ICONS](LAUNCHER_ICONS.md) | Android 备用桌面图标、activity-alias 切换与资源生成 |
| [FN_MUSIC](FN_MUSIC.md) | 飞牛音乐原生音源首期接入方式及限制 |
| [WEBDAV](WEBDAV.md) | 连接、扫描、歌词 / 封面与限制 |
| [EMBY_TEST_SETUP](EMBY_TEST_SETUP.md) | 专用测试账号与临时歌单验证边界 |
| [LRC_API](LRC_API.md) | 可选在线歌词补充、配置与缓存边界 |
| [EMBY_LYRICS](EMBY_LYRICS.md) | Emby 带时间歌词格式、旧缓存升级与手动导入优先级 |
| [NATIVE_DEPENDENCIES](NATIVE_DEPENDENCIES.md) | libmpv / FFmpeg 来源、许可与待办 |
| [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES.txt) | 已解析 Dart 依赖许可证 |
| [native_licenses](native_licenses/README.md) | 原生许可证文本与说明 |
| [测试音频](../test/fixtures/README.md) | 合成素材与用途 |

用户当前指令决定工作范围。需求与计划提供背景，代码说明当前实现，日志和进度记录实际验证；编译成功即可交付；静态分析、测试和设备验证由用户负责，不默认执行验证修复流程。发现冲突时核对代码和用户已确认的变更，更新对应文档。
