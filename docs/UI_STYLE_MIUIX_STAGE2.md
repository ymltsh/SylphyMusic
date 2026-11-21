# Miuix 双 UI 第二阶段：Android 竖屏主界面

> **修订说明（2026-11-21）**：本文件保留最初 Stage 2 方案的历史范围。采用 Stage 2 refinement 补丁后，独立「我的」排版和独立主 Shell 已撤销；最终实现与安全区规则以 [UI_STYLE_MIUIX_STAGE2_REFINEMENT.md](UI_STYLE_MIUIX_STAGE2_REFINEMENT.md) 为准。

## 视觉参考与范围

本阶段参照 HyperOS 应用的轻量视觉层次：雾面蓝紫氛围背景、留白较大的个人页、超圆角分组卡片、带选中胶囊的半透明悬浮底部导航。保留 Sylphy 的品牌标识与四个既有 tab（首页、音乐库、歌单、我的），不照搬第三方应用标志和文字。

- Android 实验构建 + 用户选中 Miuix + 竖屏宽度不大于 750 时生效。
- Android 横屏、宽屏和所有非实验构建继续使用原有 Shell，保留现有 PC/导航侧栏行为。
- `MiuixSmallTopAppBar`、`MiuixNavigationBar`、`MiuixNavigationBarItem`、`MiuixCard`、`MiuixArrowPreference` 与 `MiuixText` 使用 `flutter_miuix: 1.3.0`。
- 首页、音乐库、歌单继续调用现有 `_page()`。所有标签状态、批量选择、搜索、音源、播放与导航动作仍由同一个 `SylphyShell` 持有。
- 「我的」使用 Miuix 组件重排，但所有原有操作（音源、历史、收藏、全部音乐、下载、缓存、黑名单）仍复用原回调；补充设置和关于快捷入口。
- 迷你播放器继续使用现有 `PlayerBar`，在导航栏上方布局。折叠 FAB 沿用原有控制与动画。

## 背景与安全区

- Miuix 内置背景默认使用纯 Flutter 渐变和轻量 RadialGradient，不采用全屏模糊。
- 用户设置自定义背景图且关闭纯色模式时，优先显示原有用户图片，不再叠加 Miuix 氛围渐变。
- 未选用用户图片时，Miuix 采用独立的内置氛围背景（这与 Material 3 纯白/炭灰的设计不同）。
- 仅底部悬浮导航做局部 BackdropFilter；Miuix 原生导航项和无障碍标签保留。
- 导航栏使用 SafeArea 底部留白，Scaffold 根据 bottomNavigationBar 自动为正文和迷你播放器分配空间，避免与手势区域重叠。
- 不修改 `AppSystemBars`、`Appearance`、任何播放服务或布局数据格式。

## 应用顺序

**本补丁依赖第一阶段补丁已经应用**，新增文件不覆盖阶段一的 `ui_style`、主题桥接和实验门控。二阶段仅在现有文件中做少量定点集成。

```sh
git apply --check sylphy_miuix_stage2.patch
git apply sylphy_miuix_stage2.patch
flutter analyze
flutter test test/ui_style_test.dart test/miuix_theme_test.dart test/miuix_stage2_widgets_test.dart
flutter build apk --debug --dart-define=SYLPHY_EXPERIMENTAL_MIUIX=true
```

## 验收与后续

- Material 3 显示、Android 横屏导航、Windows 布局不变。
- 真实 Android 竖屏里四个标签都能切换、状态保持；选中项有明显的玻璃胶囊背景。
- 「我的」中所有功能入口都能打开，返回键及设置路由正常。
- 主题深浅色、字体放大、系统手势导航和底部安全区正确。
- 长列表滚动、迷你播放器展开/折叠、切歌、搜索和歌单操作无回归。
- 用户自定义背景继续有效；低端 Android 设备重点验证玻璃导航的 GPU 性能。
- 后续再移植首页卡片、音乐库列表、歌单和完整的 Miuix 全屏播放视觉，保留共享播放页布局编辑器。

此文件记录待验收项目，不代表已完成 Android 真机测试。
