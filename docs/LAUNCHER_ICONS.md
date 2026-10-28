# Android 应用图标切换

## 准备图标

将自制 PNG（建议 512×512，必须是 192–4096 px 的正方形）复制到 `assets/launcher_icons/`，例如：

```
assets/launcher_icons/
├── 高气压.png
├── 春风拂面.png
└── 杨柳依依.png
```

文件名（不带 `.png`）是 App 中显示的图标名称；文件名前的数字只用于排序，例如 `2.高气压.png` 显示为「高气压」。内置默认图标使用 `assets/icon.png`（当前为「微风与低音」），不放入此目录；默认选项之外保留 6 个备用图标：高气压、春风拂面、杨柳依依、点阵白、点阵黑、风精灵。PNG 图标由生成脚本按原文件复制到 `res/mipmap-nodpi`，不进行修改或再压缩。

关于页的 Logo 单独使用 `assets/about.png`（透明底），不再复用桌面默认图标。

## 生成默认图标与平台图标

默认图标以 `assets/icon.png` 为准。修改后运行：

```bash
python tool/generate_icons.py
```

脚本从 `assets/icon.png` 派生 Android `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` 和 Windows `runner/resources/app_icon.ico`（16–256 px 多尺寸），只依赖 Python 标准库。

## 更新图标清单并打包

```bash
python tool/generate_icons.py
python tool/generate_launcher_variants.py
dart format lib/ui/settings_page.dart lib/ui/launcher_icon_picker.dart lib/services/launcher_icon_service.dart
flutter analyze
flutter test
flutter build apk --debug
```

在 Android 应用的 **设置 → 外观与个性化 → 应用图标** 中选择。设置入口只在 Android 显示，其他桌面平台的应用图标保持不变。

每次新增、删除或重命名备用图标后都要重新运行脚本和构建安装包。因为 Android 启动器图标由 AndroidManifest 的 `activity-alias` 静态声明，不能在用户安装后从任意文件直接设置。生成脚本维护别名、原生选项清单、Android mipmap 资源；原生代码保存当前选项为组件启用状态，不单独写数据库。

## 行为与兼容性

- `LauncherIconDefault` 初始启用，备用图标别名初始禁用。目标都是已有 `MainActivity`，播放器及后台 Service 保持不变。
- Android 13+ 使用 PackageManager 的批量组件状态 API 原子切换；旧系统先启用新入口再关闭其他入口，`DONT_KILL_APP` 尽量避免终止当前播放进程，但某些 ROM 仍可能重建任务。
- 某些厂商启动器刷新图标会延迟，已固定的桌面快捷方式可能需要重新添加。更换时请同时检查后台音乐播放是否受到特定 ROM 影响。
- `MainActivity` 不再声明 MAIN/LAUNCHER；别名负责启动入口。升级既有安装时，Android 可能自动处理旧桌面图标，具体取决于桌面启动器。
- 删除图标资源前，建议用户先切回默认图标；如果从新版移除了已选择的别名，重装／更新后系统的组件状态可能需要由操作系统修复，需实机验证升级场景。

## 验证重点

1. 首次安装默认图标正确且仅有一个图标；进入应用查看预览。
2. 切换每个图标与切回默认；桌面显示无重复入口，图标在重启和更新后仍然保留。
3. 后台播放音乐时切换图标，检查通知、播放状态和桌面快捷方式。
4. 对 Android 12 / 13 / 15+ 和不同厂商启动器分别验证。
5. 关于页显示透明底的 `assets/about.png`；换用新图标后不应再出现桌面旧图标的白色方块。
