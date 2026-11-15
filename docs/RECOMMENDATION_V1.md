# SylphyMusic 智能推荐 V1 — 源码覆盖包

## 范围

- 首页新增「每日精选」卡片、24 首每日混合推荐与详情页；同一天快照稳定，支持「换一批」、播放整单、保存为本地歌单、逐曲隐藏。
- 「专辑精选」改为按用户偏好与未探索比例独立生成（最多 8 张），使用来源作用域内的专辑身份，默认唱片/曲序播放。
- 使用本地播放事件与媒体进度近似计算有效聆听、完成和主动跳过；近期会话保存 90 天、累计统计长期保存。
- 可选使用 ListenBrainz 全球周榜 + Apple Music RSS 中国区热门歌曲榜作弱热度信号，公开固定请求不会发送个人曲库、曲目或播放历史。请求失败可离线回退。
- 历史记录从最近 **50 首去重 TrackRef** 扩容到 **1000 首**；批量解析最近播放，避免逐首数据库往返。
- SQLite v9 -> v10 仅新增表、索引，保持已有曲库与历史数据。原 50 条无法倒推出更久以前已经丢失的历史。
- 设置 → 外观与个性化 → 推荐设置：个性化推荐、在线热度开关与清除推荐统计；每日精选菜单保留原有快捷操作。清除统计前需确认，更改后重新生成每日精选 / 专辑推荐并刷新首页。关闭个性化后停止新增行为统计，使用随机候选。

## 安装

本包针对 GitHub 仓库 `ymltsh/SylphyMusic` 的 2026-11-11 `main` 公开代码起草。该环境无法直接访问用户电脑上的仓库，也未安装 Flutter/Dart；本包未完成 Flutter 构建验证。

在本地使用：

```bash
python apply_to_repo.py /path/to/SylphyMusic --check
python apply_to_repo.py /path/to/SylphyMusic
```

脚本先检查所有源文件锚点和新文件是否冲突，再写入。不会调用 git、推送 GitHub、修改发布记录或运行测试；不覆盖不同内容的已有新文件。若提示某个源码锚点不匹配，意味着实际工作区与参考 `main` 不同；请按本地源码人工合并，不要强行替换文件。

随后按项目既有流程手动执行（由使用者负责环境与设备验证）：

```bash
dart format lib/core/listening_history.dart lib/core/recommendation_models.dart \
  lib/data/app_db.dart lib/data/library_catalog.dart \
  lib/data/recommendation_repository.dart lib/services/listening_events.dart \
  lib/services/listening_analytics.dart lib/services/public_music_trends.dart \
  lib/services/recommendation_engine.dart lib/services/recommendation_service.dart \
  lib/services/playback.dart lib/core/app_controller.dart \
  lib/ui/home_page.dart lib/ui/daily_mix_page.dart
```

建议按用户现有工程约定编译 Windows / Android。尤其应验证单曲循环（seek 回零）、系统音频焦点和后台恢复，不把编译成功当成音频行为验收通过。

## 数据表

- `listening_sessions`: 有效时长、起始本地时段、是否有效/完成/跳过，90 天淘汰明细。
- `track_listen_stats`: 累计计数、完成、跳过、听歌时长、最近有效播放。
- `recommendation_snapshots`: kind、日期、generation、算法版本、数量与随机种子。
- `recommendation_items`: 快照的单曲或来源作用域专辑身份、理由、分数和顺序。
- `recommendation_feedback`: 单曲推荐专用 hide，不修改全局音乐黑名单。

## 设计边界

1. 外部热度匹配仅使用标准化后的 **艺术家 + 标题严格一致**；不跨来源替换原始 `TrackRef`，不抓取音频、不自动向云端写歌单。
2. 当前 Track 元数据无统一曲风、情绪、BPM，因此「情境」只使用个人历史时段的歌手统计。初始不足 20 次且至少 5 天的有效收听时使用中性情境分。
3. 每天一次本地快照；榜单获取失败不会阻断本地推荐。详情页重新验证源启用、黑名单和可见性。
4. 个性化评分为可迭代的启发式规则，不属于声学或机器学习相似度。
5. 不在应用打开时扫描/下载整库，常见候选 SQL 限制为约 1200 条；专辑聚合查询按有界结果返回。
6. 当前版本不自动创建定时后台任务；打开首页时按本地日期生成，避免 Android 后台限制造成维护负担。

## 后续建议

- 推荐设置已在设置主页提供入口，可继续按需要扩展偏好选项。
- 可以进一步加本地歌手/专辑聚合索引、强制热度刷新、地区选择、周末事件规则、播放统计可视化。
- 无法从先前最近 50 首记录还原历史的播放次数、时段或完成率，迁移时仅保留原历史顺序。
- 如果后续引入 MusicBrainz/Last.fm，请使用独立来源适配器和缓存，不把 API 密钥硬编码到公共客户端源码。

## 本地集成记录（2026-11-11）

普通版与 OpenList 工作区均通过覆盖脚本预检查后应用，保留已有播放恢复与 OpenList 租约。集成时修正关闭个性化后的退出监听清理，并在启动期间等待旧会话清理结束，避免数据库关闭后遗留任务。Dart 文件已格式化。仅按仓库约定编译打包，未运行测试、analyze、应用启动或设备验证；未请求公开热榜接口，实际结果见 [PROGRESS](PROGRESS.md)。
