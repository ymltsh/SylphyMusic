# 每日精选封面卡片与 Prompt 自定义

此增量基于 2026-11-12 刷新后的 `ymltsh/SylphyMusic/main`，要求先有 LLM 推荐模块 `lib/services/llm_recommendations.dart`、SQLite v11 推荐快照和 `DailyMix.introduction`。

## 用户可见改动

- 首页每日精选：改用与「我的音乐空间」一致的柔和渐变、圆角卡片与叠放封面，取当前精选中的前四张真实音乐封面；保留点击进入详情、播放全部。
- 每日精选详情：首屏一块推荐展示卡。宽屏封面组在左、推荐寄语和前三条曲目推荐依据在右；窄屏封面组在上、文案在下；曲目列表在卡片之后，点击歌曲仍按原有索引播放。
- 推荐词始终优先取 `DailyMix.introduction` 和 `RecommendedTrack.reason` 已有字段，不额外重复请求 LLM，空寄语使用不宣称音乐内容的本地兜底文案。
- 设置 → API 设置 → LLM 推荐 → 「自定义 Prompt」：System 与 User 各支持最多 2000 字，分别编辑推荐角色 / 策略和个人偏好，支持恢复默认、保存后生效。

## Prompt 权限划分

- **System（部分可编辑）**：推荐编辑角色、选曲策略、探索侧重和文案风格允许自定义。应用在其后追加固定约束：仅选择本地候选整数 ID、禁止编造歌曲/专辑/音源/歌词/风格/用户经历、只返回结构化 JSON，并限定导语 / 单项推荐词长度。
- **User（用户编辑）**：个性化选曲侧重和文案语言风格。客户端把自定义段落与不可修改的候选 JSON 一同放入 `role=user` 消息，不允许设置改变实际候选列表或输出解析规则。
- **服务端响应**：继续使用当前已有严格 ID 映射、去重、多样性限制和本地算法回退；模型输出文本仅作为普通 Flutter Text 显示。

## 配置与持久化

- 设置键：`settings.api_llm_user_prompt`、`settings.api_llm_system_prompt`，不需要新数据库迁移；旧用户偏好保留，新增 System 字段使用默认值。两段提示词与递增配置版本在同一事务中保存，一次通知刷新。
- 更改提示词递增 `ApiSettings.llmRevision`，使当日快照的 `llm_tag` 失效。会重新生成精选并可能产生 API 费用；正在播放的队列不会被更改。
- 原有 API Key 继续通过 `AuthVault` 保存；推荐逻辑与歌曲身份没有变化。自定义 System / User Prompt 会发往用户选择的 LLM 服务，并且其中不应填写个人密钥。

## 应用、编译与已知边界

1. `python apply_to_repo.py /your/SylphyMusic --check` 先检查所有锚点。
2. `python apply_to_repo.py /your/SylphyMusic` 生成本地 `.private/recommendation-showcase-before` 备份，覆盖五个现有文件，新增一个 UI 组件和本文档。
3. 在你的 Flutter 工作区对五个修改的 Dart 文件和一个新 Dart 文件执行 `dart format`，再按项目正常方法编译 Android/Windows。安装脚本本身不触发构建、发布、推送或测试。

因当前会话无本地检出、Flutter SDK，无法声称 Flutter 编译或真机界面已经通过验证；用户应先在自己的工作区完成编译。
