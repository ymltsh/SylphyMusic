# 双 UI 风格 · Miuix 第一阶段（实验性）

## 决策与边界

- Material 3 是默认及稳定回退路径。
- Miuix 尽可能使用 `flutter_miuix` 原生组件，首期只交付主题、风格选择与组件预览；主要页面和播放页后续分阶段适配。
- 本阶段不得新建 `SylphyApp`、播放器、数据库或第二个 `MaterialApp`，不得修改 Media3、播放布局格式和曲库索引。
- `ui_style` 存储用户选择（`material3` / `miuix`），只有 Android 的实验构建允许 Miuix 生效；门控不回写用户配置。
- Android 系统栏继续由 `AppSystemBars` 管理；Miuix 主题位于其祖先，保持前后景明暗一致。

## 构建

依赖固定 `flutter_miuix: 1.3.0`。**应用补丁后必须运行 `flutter pub get` 并提交生成的 `pubspec.lock`**：补丁不包含在无 Flutter SDK 环境下无法解析生成的锁文件。

```sh
flutter pub get
flutter analyze
flutter test test/ui_style_test.dart
flutter test test/miuix_theme_test.dart
flutter test test/appearance_test.dart
flutter build apk --debug
flutter build apk --debug --dart-define=SYLPHY_EXPERIMENTAL_MIUIX=true
```

正式构建默认禁用实验功能；只有显式添加 `--dart-define=SYLPHY_EXPERIMENTAL_MIUIX=true` 才允许 Android 设备选择。Windows / Linux / Web 不开放 Miuix，此时使用 Material 3。

## 设置与生命周期

`Appearance` 使用既有 settings 表存储 `ui_style`，在加载时缺失或无效值回退 Material 3。快速写入串行化；数据库写成功后才通知观察者；`Appearance.shutdown()` 等待写入结束。

`MaterialApp`、`navigatorKey`、`PlaybackShortcuts` 和 `AppSystemBars` 均保持唯一；切换风格只改变主题子树，不创建新的播放服务。Miuix 未适配页面由兼容的 Material 主题承载。

## 首轮验收

- 旧用户默认 M3；切换 Miuix / 重启后选中值保留。
- 未开启实验标志时即使已有 `ui_style=miuix` 也仍显示 M3。
- Android 实验版真实渲染 MiuixScaffold / Card / Preference；预览开关可操作。
- 正在播放中切换风格不影响当前歌曲、进度和队列。
- Android 竖屏/横屏的系统安全区、返回键、主题明暗与键盘无遮挡。
- Windows 默认构建与当前 M3 无回归。
- `flutter pub get --enforce-lockfile` 在锁文件更新提交后通过；第三方许可清单必须包括 flutter_miuix Apache-2.0 与新增依赖。

## 后续范围（不在本补丁中）

- 分离导航共享状态，增加 Miuix Shell、首页、曲库、搜索、歌单和迷你播放器。
- 播放页继续共享 `PlayerLayoutStore`、自由画布及布局编辑器；另加 Miuix 控件样式与默认模板，不自动覆盖用户配置。
- 风格的跨设备迁移需在真正对外开放时另行加入 `transferConfigKeys`，避免实验版配置污染稳定版。
