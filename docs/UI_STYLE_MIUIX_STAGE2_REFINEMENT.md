# Miuix Stage 2 refinement：保留 Sylphy 排版的渐进式 Miuix

## 用户反馈后的最终方案

参考 KernelSU 的做法，将 Miuix 作为现有页面的视觉系统，不再重排 Sylphy 的信息架构：

- 首页、音乐库、歌单、我的依旧走 **同一个** `SylphyShell._page()`。
- 「我的」保留 MusicSpaceCard、快捷方式网格和音乐管理分组，而非独立的大 Logo / 列表版页面。
- 顶栏继续使用现有 `AppBar` 的标题、搜索、设置与安全区；Miuix 主题桥接提供配色。
- Miuix 模式只替换竖屏的底部导航容器，继续采用 Miuix 原生导航项和选中态反馈。
- 卡片依旧走原有 Widget 树，使用 Stage 2 `MiuixThemeScope` 的卡片形状和色彩桥接。
- 非 Miuix 模式仍通过原来的 `AppBackground`；纯色底色与用户自定义背景图拥有最高优先级。仅在关闭纯色且没有自定义背景时才渲染额外渐变。
- Android 横屏、Windows、正式版遵循原有排版和导航回退规则。

## 统一导航高度与手势留白

| 维度 | Material 3 | Miuix |
|---|---|---|
| 导航内容基础高度 | 64dp（原为 72dp） | 原生 NavigationBarItem 64dp |
| 顶/底外部装饰间距 | 无 | 各 2dp（原为 6dp/10dp） |
| item 纵向 margin | 无 | 0dp（原为 4dp） |
| 系统底部安全区 | NavigationBar 内建 SafeArea | 单一 SafeArea，maintainBottomViewPadding |
| 选中态 | MD3 原有指示器 | 原生 Miuix item + 自定义圆角背景 |

不得删除系统手势底部安全区，也不得重复引入 `SafeArea`。调整的是导航主体和额外装饰间距，而非平台系统手势区域。`NavigationBar.height` 文档说明它不含 SafeArea；同时要避免再手工加第二层底部 inset。

## 行为与验证边界

- 播放、音乐库分页、收藏、下载、播放页模板等业务逻辑未修改。
- 风格切换不会为任何页面创建第二个 SylphyApp / PlaybackCoordinator。
- 测试覆盖 Miuix 底栏选中回调及 24dp 手势 inset 下的几何约束。
- 必须在 Android 真机验证三键导航、手势导航、横屏、IME、较大字体、迷你播放器/FAB 和 320dp 窄屏。
- Flutter SDK 不在补丁生成环境内，真机 UI 和编译通过需由开发机补充验证。

应用次序：第一阶段 -> 第二阶段 -> **本修订补丁**。不要将本修订直接应用到原始 `main`。
