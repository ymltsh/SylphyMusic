# Android 手势条沉浸显示

2026-10-27，根据用户要求查阅官方资料并接入。

## 依据

- [Flutter：默认 edge-to-edge 的迁移说明](https://docs.flutter.dev/release/breaking-changes/default-systemuimode-edge-to-edge)：目标 API 35 起默认边到边，目标 API 36 不支持退出；不能用不透明系统栏颜色作为新版本布局方案。
- [Android：Display content edge-to-edge](https://developer.android.com/develop/ui/views/layout/edge-to-edge)：背景可延伸到系统栏下，交互控件需要避开系统 Insets。
- [Flutter：systemNavigationBarContrastEnforced](https://api.flutter.dev/flutter/services/SystemUiOverlayStyle/systemNavigationBarContrastEnforced.html)：透明导航栏可额外叠加对比度遮罩，关闭后需要应用确保按钮可读。
- [Flutter：setSystemUIOverlayStyle](https://api.flutter.dev/flutter/services/SystemChrome/setSystemUIOverlayStyle.html)：使用 AnnotatedRegion 随页面渲染维护样式，AppBar 仍负责顶部状态栏样式。
- [Flutter：NavigationBar.maintainBottomViewPadding](https://api.flutter.dev/flutter/material/NavigationBar/maintainBottomViewPadding.html)：保留底部 ViewPadding 可避免输入法改变导航栏控件位置。

## 实现

`main.dart` 在 Android 初始化时显式启用 SystemUiMode.edgeToEdge，桌面不执行此调用。MaterialApp.builder 中的 AppSystemBars 为所有路由提供透明系统导航栏、透明分隔线，并随当前应用主题切换手势条 / 三键图标明暗。手势导航使用透明栏；三键导航保留系统的对比度保护，安全区按实际 Insets 避让。保留系统手势条，不隐藏系统导航。

Android API 29+ 的 LaunchTheme / NormalTheme 及夜间资源同步配置透明状态 / 导航栏与正确图标初始明暗，启动阶段保留系统对比度保护。未降低 targetSdk、未退出 edge-to-edge、未修改原生媒体 / 缓存 Runner。

主界面继续使用 Material NavigationBar 自身的 SafeArea，在其背景内延伸到屏幕底部；不为它额外叠加一次底部边距，并启用 maintainBottomViewPadding。宽屏迷你播放器、独立设置等路由、音乐库及聚合分页操作、全屏播放器和队列弹层补齐安全边距。播放器的背景 Material 包在 SafeArea 外，因此手势条下方仍为同一播放器背景。搜索页面沿用 Scaffold 的键盘避让。

## 验证

`integration_test/system_bars_test.dart` 使用临时数据库、合成 WAV 和内存凭据仓库，覆盖浅色 / 深色、首页、设置、真实搜索键盘、全屏播放页、队列弹层。断言系统底部 Insets 非零、NavigationBar 总高度只包含一次安全区、文字和 Seek 控件位于手势区之上。

本机 SylphyTest_API35 独立模拟器分别使用手势和三键导航执行。主机从 Android 合成器截取含实际系统栏的截图，保存在 `build/test_logs/edge/`；测试截图不包含私人来源或曲库。测试结束恢复原导航模式；具体结果见 [进度](PROGRESS.md)。

API 35 模拟器结果不代替其他 Android 版本、厂商系统及物理设备的验收。手势条由 Android 系统绘制，第三方系统可调整它的形状和显隐行为。
