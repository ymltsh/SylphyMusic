# 实施与验证记录

## 2026-10-28 更新检查与本地发布工具

参考用户提供的 Mfuns Flutter `update.md`，新增设置页手动检查更新、实际安装包版本读取、正式 / 测试版独立清单、更新说明和平台下载入口。仅点击检查时发请求，加速地址失败回退 GitHub，12 秒 / 次、1 MiB 上限、同版 / 旧版不提示更新，下载链接限于本项目 HTTPS GitHub Release。新增 package_info_plus / url_launcher 并锁定依赖，重新生成插件注册与 Dart 许可证清单。

根目录 `release.py` 默认只本地准备：版本 / 构建号、检查、三 ABI APK、Windows 便携 ZIP / Inno Setup 安装程序、凭据内容扫描、SHA-256 与源码指纹记录。显式 `--publish` 才操作 GitHub，先上传草稿再公开，最后仅更新所选渠道清单；不自动提交或推送源码。要求正式签名、干净工作区和可在 GitHub 访问的源码提交，正式版继续受原发布门槛约束；复用产物校验摘要 / 源码，恢复发布核对远程文件且不覆盖已有资产。使用方法见根目录 [update.md](../update.md)。两份清单初始 latest=null，没有虚构已发布包。

验证：`flutter analyze --no-pub` 无问题；`test/app_updates_test.dart` 7 项通过；Python 发布工具 11 项测试通过（模拟 GitHub，覆盖纯预览、构建号、清单历史、资产损坏、上传失败 / 恢复、凭据内容扫描与正式版门槛）。Windows 原生 `ui_refresh_test.dart` 最终通过（`build/test_logs/release-system-ui-final.log`），核对手动更新页不自动检查、实际安装包版本显示及既有设置 / 播放流程；已查看 `build/test_logs/ui/settings-update-mobile.png`。Android Debug 构建通过（`build/test_logs/release-system-android.log`），未安装到设备。

未执行 GitHub 发布 / tag / 清单推送，线上接口需另行授权推送后才可使用。本机没有 Inno Setup 编译器和 `android/key.properties`，尚未实测安装程序编译、正式签名 Release 构建、安装升级 / 卸载或真实 GitHub 事务；未重新生成内部 Release 验收包，未执行 Linux 验收。


## 2026-10-28 设置页分类与二级配置

按用户提供的设置页讨论，将原 `app_shell.dart` 长列表抽到 `lib/ui/settings_page.dart`：一级页为四组八项分类入口及实时摘要；二级页分别处理播放、歌词、主题、背景、播放器外观、下载与缓存、关于。沿用原音乐源管理、缓存任务与逐曲清理页面、外观 / 播放 / 缓存持久化。补充已有唱片旋转偏好的入口；滑块放在标题下方，桌面内容限宽居中。返回目录后刷新缓存上限等摘要。

首轮原生回归发现旧缓存预算弹窗在退出动画结束前释放 TextEditingController；改为表单输入，并验证 1–200 GiB 的整数。最终 `flutter analyze --no-pub` 无问题；`test/appearance_test.dart` 8 项通过；Windows 原生 `integration_test/ui_refresh_test.dart` 通过（`build/test_logs/settings-ui-final.log`），覆盖设置分类、二级跳转、速度调整、歌词字号独立性、主题 / 背景 / 唱片旋转、预算保存、清理取消、缓存空间 / 任务 / 许可证入口和既有来源 / 播放流程。已查看 360×800、320×640 和 1200×850 截图，位于 `build/test_logs/ui/settings-*.png`。未执行 Android 设备验证或重新打包 APK / Release 包。


## 2026-10-27 音乐库分类切换抽动修复

根因是 `LibraryBrowser` 查询等待 / 失败时的布局没有播放数量行，筛选栏会短暂上移。统一加载 / 成功 / 失败的外层布局，保留播放数量行及来源 / 排序操作，等待期间显示「—」并禁用播放；加载完成只更新数量和列表，空结果仍显示 0。数量单行显示，不随位数改变行高。

验证：`flutter analyze --no-pub` 无问题；Windows 原生 UI 回归通过（`build/test_logs/stable-library-header-ui.log`）。测试用受控 SQLite 事务延迟查询，等待期间连续切换艺术家 / 歌曲 / 专辑，逐帧核对筛选栏与数量行坐标不变，播放禁用且来源入口存在；查询完成后数量正确、播放恢复，实际数量 3→1 及空来源 0 的坐标也保持一致。未执行 Android 设备验证或重新打包 APK。

## 2026-10-27 迷你歌词长句两行显示

歌词预览由固定单行槽位改为按实际文字高度排版：每句最多两行自动换行，优先保留当前句，再按剩余高度显示邻近句（最多五句），避免长句在第一行就被省略或第二行被裁切。保留迷你字号、时间高亮、同时间戳主句规则；极小文字框缩放容纳当前句，完整歌词页仍可查看超过两行的极长内容及译文。

验证：`flutter analyze --no-pub` 无问题；`test/lyrics_preview_test.dart`、`test/lyrics_view_test.dart` 共 9 项通过，覆盖长句两行完整显示、两倍字号 / 矮框边界及原有时间高亮 / 歌词页行为；Windows 原生界面回归通过（`build/test_logs/wrapped-lyrics-ui.log`），实际 Seek 到合成长句并核对两行无截断。已查看截图 `build/test_logs/ui/player-lyrics-preview.png`。Android 实机效果尚未验证。

已按用户要求执行 `tool/build_review.ps1`，生成包含本次长句换行及此前圆角分类 / 三分类播放行 / 无顶栏四项快捷操作 / 睡眠定时的内部 Release 包。arm64-v8a APK 29.22 MB、armeabi-v7a 26.17 MB、x86_64 31.52 MB，Windows ZIP 21.70 MB，位于 `build/internal-review/`；三种 APK 签名与全部产物 SHA-256 核对通过，使用本机测试签名。构建日志 `build/test_logs/wrapped-lyrics-build.log`，未安装到 Android 设备验证。

## 2026-10-27 播放页无顶栏与四项快捷操作

移除播放页 56 dp 顶栏，画布与编辑器同步使用完整安全区。第一个可见进度条上方固定显示睡眠定时、歌词页、收藏、更多；更多仍仅含音质信息与编辑播放页，没有进度条时使用底部回退行，删空自定义组件也能进入编辑器。调整内置迷你歌词高度，旧自定义歌词区与快捷行相交时缩短显示边界，进度条最小上边距给快捷行留出空间；下滑收起、左滑歌词保留。

用户确认定时含义为倒计时停止。新增应用级 `PlaybackSleepTimer`：15 / 30 / 45 / 60 / 90 分钟与取消，到期调用当前播放器暂停，切页不丢失；恢复前台复核截止时间，更换定时取消旧任务，应用关闭前取消并等待正在执行的暂停任务。不跨进程保存，Android 后台精确到点未在实机验收。收藏组件抽为共用控件并监听收藏变更。

验证：静态分析无问题；定时、布局及长文字相关测试 21 项通过；Windows 原生 `player_layout_test.dart` 与 `ui_refresh_test.dart` 分别通过（`build/test_logs/quick-actions-layout-final.log`、`quick-actions-ui.log`）。实际验证快捷行顺序 / 位于进度条上方、无顶栏、睡眠预设 / 取消 / 跨歌词页保留 / 到期暂停、收藏写入及反馈、编辑与空布局恢复、既有手势和 320×640 / 360×800 / 1200×850 布局。最终回归捕获并修复收藏同步监听的 setState 回调误返回 Future。已查看手机截图 `build/test_logs/ui/player-lyrics-preview.png`。本轮未执行 Android 设备验证或重新打包 APK。

## 2026-10-27 圆角筛选栏与分组播放全部

按用户修正，将音乐库筛选按钮调整为 8 dp 圆角矩形。歌曲、专辑、艺术家均显示同一播放全部操作行，数量对应歌曲数 / 专辑数 / 艺术家数；来源过滤、排序与升降序统一位于该行右侧，筛选栏保持在其下方靠左。专辑和艺术家播放全部通过 `CatalogQuery.songs` 获取完整匹配歌曲身份，保留来源、搜索、组内范围、排序和黑名单边界，避免只播放分组代表曲目。空分类显示 0 并禁用播放。

验证：`flutter analyze --no-pub` 无问题；`test/library_catalog_test.dart` 4 项通过，新增分组播放全部覆盖完整曲目、来源 / 搜索 / 黑名单、时长 / 年份排序和空来源；Windows 原生 UI 回归通过（`build/test_logs/rounded-library-ui.log`），实际点击专辑 / 艺术家播放全部并核对三首队列，验证数量 3 / 1、空来源 0 与禁用、无重复筛选 / 排序入口及圆角形状。已查看 `build/test_logs/ui/library-albums-mobile.png`。本轮未执行 Android 设备验证或重新打包 APK。

## 2026-10-27 移除播放页迷你歌词缩放按钮

移除迷你歌词右下角缩放按钮及播放页内直接拖动尺寸、自动保存布局的逻辑，尺寸统一在编辑器「歌词预览」内调整。`PlayerScene` 简化为渲染已保存布局，同时移除播放页为缩放手势设置的冲突保护；歌词点击、左滑进入完整歌词及下滑收起继续保留。

验证：`flutter analyze --no-pub` 无问题；Windows 原生界面回归通过（`build/test_logs/remove-lyrics-handle-ui.log`），断言按钮和提示均不存在，保留迷你歌词显示、点击打开完整歌词与原有页面操作。已查看实际截图 `build/test_logs/ui/player-light-cover-blur.png`，确认右下角无缩放覆盖按钮。

已执行 `tool/build_review.ps1` 重新生成包含本次及前面菜单 / 音乐库调整的内部 Release 产物：arm64-v8a APK 29.15 MB、armeabi-v7a 26.16 MB、x86_64 31.46 MB，Windows ZIP 21.69 MB；三种 APK 签名验证和全部 SHA-256 核对通过。日志 `build/test_logs/remove-lyrics-handle-build.log`，文件位于 `build/internal-review/`。使用本机测试签名，未执行 Android 设备安装验证。

## 2026-10-27 播放页更多菜单迁移

按用户要求，播放页「更多」仅保留音质信息和编辑播放页。移除该菜单内的导入歌词、查看完整歌词和完整歌词字号入口；完整歌词仍可点击歌词区或左滑打开，字号由歌词页内入口调整。

编辑器「专辑封面」新增唱片样式、唱片旋转；「歌词预览」新增迷你歌词字号选择；「页面」新增封面模糊开关；「布局操作」提供使用系统默认布局。沿用全局外观偏好与自动保存，面板明确说明，修改即时刷新预览，关闭编辑器后仍保留；组件布局继续保存并应用，放弃提示区分这两类修改。

验证：`flutter analyze --no-pub` 无问题；Windows 原生布局编辑器测试通过，覆盖两项菜单、编辑器内封面切换、旋转预览和持久化、默认布局恢复及原有编辑流程（`build/test_logs/editor-settings-ui.log`）。同次运行的第二组界面测试启动调试连接失败，单独重跑 `integration_test/ui_refresh_test.dart` 通过（`build/test_logs/editor-settings-ui-retry.log`），验证迷你歌词字号 20→24、模糊背景、关闭编辑器后生效及原有导航 / 歌词手势。已查看编辑器手机截图；本轮未在 Android 设备验证或重新打包 APK。

## 2026-10-27 音乐库方形筛选栏位置调整

按用户要求将歌曲 / 专辑 / 艺术家筛选按钮改为直角矩形，将筛选栏移到歌曲列表播放全部操作行下方，左侧边距 16 dp。保留横向滚动、主题选中色及原有分类切换；加载 / 失败状态仍可切换分类，其他列表不增加筛选栏。

验证：`flutter analyze --no-pub` 无问题；Windows 原生 `integration_test/ui_refresh_test.dart` 通过，新增断言检查三个按钮的直角形状、筛选栏位于操作行下方及左侧对齐，原有分类切换 / 来源过滤 / 排序 / 搜索继续通过。已查看 360×800 截图 `build/test_logs/ui/library-sort-mobile.png`。首次测试因系统临时目录拒绝访问而失败，改用项目 `.private/ui-test-temp` 后通过；日志 `build/test_logs/square-filters-ui-retry.log`。未执行 Android 设备验证或重新打包 APK。

## 2026-10-27 播放页长标题与歌手信息

修复自由画布文字固定允许三行、却没有按组件高度限制完整行数的问题。播放页和编辑器共用 `PlayerMetadataText`：标题按实际字体 / 系统文字缩放测量，最多两行；歌手 / 专辑单行，超长末尾省略。极矮文字框缩放容纳完整一行，文字限制在组件内；长按或桌面悬停可查看完整内容。

验证：`flutter analyze --no-pub` 无问题；`flutter test --no-pub test/player_metadata_text_test.dart test/player_layout_test.dart` 共 16 项通过。新增 Widget 测试覆盖长中英标题、歌手 / 专辑、完整行与省略、长按提示、手机 / 宽屏布局、两倍文字缩放及极矮自定义文字框的实际绘制边界。本轮未执行原生设备验证或重新构建安装包。

随后按用户要求执行 `tool/build_review.ps1`，已生成包含此修复的内部 Release APK：arm64-v8a 29.22 MB、armeabi-v7a 26.16 MB、x86_64 31.52 MB，位于 `build/internal-review/`；脚本同步更新 Windows ZIP（21.70 MB）。三种 APK 的 apksigner 签名验证和全部产物 SHA-256 核对通过，使用本机测试签名。日志：`build/test_logs/metadata-review-build.log`。本次未安装到设备验证。

日期：2026-10-27（Asia/Shanghai）。完整首版目标仍有效；当前没有声明正式版完成或发布。

## 已执行的验证

| 验证 | 结果 / 边界 |
|---|---|
| Flutter 升级 | 3.47.8 stable / Dart 3.13.7；依赖已升级并锁定 |
| Windows Debug | 已构建并实际启动 |
| Windows 原生集成 | SMTC 与托盘创建、本地音频播放通过 |
| Android Debug | 已构建并安装到独立 API 35 模拟器 |
| Android 原生集成 | 本地 + BR1 播放、P2、Seek、完整缓存字节一致性、独立 dataSync 缓存服务与任务完成通过 |
| 真实 Emby 只读 | 登录、索引、歌单读取、原始音频 Range 通过；模拟器真实 Emby 播放 / Seek 通过；凭据未输出或打包 |
| Navidrome 0.64.2 | 隔离本机实服；登录、索引、原始流、封面、临时歌单 CRUD / 重复条目 / 重排 / 改名通过 |
| libmpv 核心 | 合成 WAV 加载、Seek、切歌、队列移除、真正关闭后恢复暂停通过 |
| 标签 | 合成 MP3 / 96 kHz FLAC、内嵌封面、增量扫描通过 |
| 小屏 UI | 360×800 主界面与队列无布局溢出 |
| BR1 / 缓存 | 回环 HTTP 集成测试：完整落盘、Range / 后缀 / HEAD、强版本 P2 复用、版本变化重取、来源停用 / 删除拒绝票据通过 |
| 云歌单状态机 | 写入后响应丢失不重复追加、只读刷新保留草稿、重排冲突停写、跨账号拒绝、改名基线通过 |
| 传输 | 安全读有限重试、写入不盲目重放、401 / 重定向不重试、URL 子路径与凭据排除通过 |
| 200 首缓存任务 | 原子快照 / 去重、下载中断、调度器重建恢复、全部 READY 与抽查字节一致、TEMP 清理通过；合成小文件，不等同于真机长时间压力结果 |
| Emby 分页 | 无 TotalRecordCount 时完整翻页、歌单重复曲目保留、无效 / 不前进页拒绝刷新通过 |
| Emby 真实写入 | 经用户授权，仅新建 Sylphy Test 临时歌单；重复条目添加、重排、改名、删除及删除后列表核对通过，未操作已有歌单 |
| 大库索引 | 50,000 首合成元数据、250 首逐页落 SQLite 暂存、完整原子切换；失败 / 取消保留旧索引；重启丢弃残页并记住未完成来源重新扫描通过 |
| 数据库分页浏览 | 歌曲 / 专辑 / 艺术家、来源 / 搜索 / 黑名单过滤均在 SQLite 执行，每页 100 条完整元数据；队列只取身份；Windows 原生分页和分组进入通过 |
| 来源生命周期 | 停用先拒绝新工作并关闭索引、BR1 上游、P2 / 完整缓存及封面读取；READY、索引、歌单与任务快照保留。重新启用先验证身份和认证，再同步，保持暂停，显式播放刷新旧票据。真实 Emby Android 完整流程与 Windows 停用缓存保留通过 |

单元测试最近一次全量通过 **159 项**，另外五项真实环境测试默认跳过（包括 Emby 封面实服验证）。真实 Emby 写入已获准并另行执行通过。Windows / Android 原生集成另行执行；两平台均已实际通过 50,000 条元数据的逐页索引、末页 SQL 读取、艺术家聚合与分页界面导航，以及 WebDAV 原生端到端测试。Android 同时通过新索引链路连接真实 Emby 后播放 / Seek。

原生播放回归本轮复现并捕获到恢复时间断言的 1 ms 差异（预期 2000 ms，实际 1999 ms）；原生时间断言已改为 2 ms 容差，队列身份与暂停状态仍严格断言。其他负载与时序压力继续验证，不据重复通过宣称所有时序风险已关闭。最新完整单元测试输出保存在本机忽略目录 `build/test_logs/assets-full-suite.log`；原生 WebDAV 结果见同目录 `webdav-native-windows.log` 与 `webdav-native-android.log`。

## 已接入但仍需进一步压力 / 平台验证

- PR1：缓冲不足时后台读取让步、播放期间后台限速、接近切歌且缓冲充足时 P2 机会、同一资源共享与取消保护。
- 完整缓存 SHA-256 复核、资源元数据版本校验与 SQLite v1→v5 迁移。
- 来源编辑重新认证使用临时凭据命名空间，不把原 token 发送给新端点；Emby 核对服务器和用户身份。
- 自动重连受次数限制；鉴权 / TLS 明确拒绝时停止重连。
- 三端 CI 配置已加入，但还没有远端 CI 执行结果。

## 完整首版剩余闸门

1. 真实 Emby 的只读账号 / 权限撤销与双客户端并发冲突场景还需补充实服验证；临时歌单基本 CRUD 已完成。
2. 用户要求先本地运行，不推送 GitHub。Linux 本机构建和原生运行环境尚不可用；当前无可用 WSL 发行版且进程不是管理员，用户已明确暂缓 Linux 验收，先继续 Windows / Android；不安装 WSL。
3. Android 物理设备的锁屏、来电、永久 / 短暂失焦、耳机 / 蓝牙、OEM 省电、强停与系统时限验证。
4. 更多 OpenSubsonic 实现的兼容性、服务端歌词差异，以及弱网 / 200 首任务 / Seek / 崩溃时序压力测试。
5. 正式应用标识、签名与安装升级验证、原生 libmpv / FFmpeg 对应源码与许可证分发义务、公开仓库和完整发布包。

原生依赖已记录运行时版本、Windows DLL 摘要及上游构建开关，见 [NATIVE_DEPENDENCIES.md](NATIVE_DEPENDENCIES.md)。尚未据此宣称分发许可验收完成。

下一轮代码审查还需逐项核对规格中的安全签名播放重定向、重定向相关凭据边界等行为；当前实现中的严格拒绝重定向不能代替规格要求的合法播放跳转兼容性。剩余工程工作不限于外部设备验收。

调试 APK 或 Windows Debug 可用于内部验收，不能用它们代替以上完整正式版门槛。

## 当前内部验收输出

2026-10-27 WebDAV：新增来源类型与添加入口，安全存储 Basic 认证密码；按 Depth: 1 递归扫描，每 250 首提交暂存页，失败保留旧索引。对 href 做同源及根目录范围校验，支持编码文件名，同名歌词与目录封面，播放 / Seek / 完整缓存 / 缓存任务复用现有通路，收藏和本地歌单可引用 WebDAV 曲目；隐藏不支持的云歌单目标。首次显示文件名与目录分组，不在扫描时下载远程文件解析内嵌标签；已有完整缓存可读取内嵌歌词。修改地址须建立独立来源。

WebDAV 测试账号已完成真实服务器只读登录、递归扫描与音频 Range 验证。新增 5 项回归测试覆盖编码路径、目录遍历、503 首分批、属性与认证错误、越界 URL / 重定向拒绝及只读歌单能力。全套 66 项通过，4 项私密测试默认跳过，静态分析无问题；Windows 与 API 35 Android 原生 WebDAV 端到端测试均通过（同步、实际播放、Seek、READY 字节一致、歌词、本地歌单、停用保留缓存、重启用验证）。账号只在 Git 忽略目录，服务器仅执行 PROPFIND / GET，不做写入。设置与限制见 [WEBDAV.md](WEBDAV.md)。

2026-10-27 歌词修复：补齐原先直接返回 null 的 Emby 歌词读取。每次首次获取刷新单曲 MediaSources / MediaStreams，按 Subtitle 流索引读取：内嵌 text 使用 Stream.txt，外置 lrc 使用 Stream.lrc；兼容旧版 Videos 路径。认证保持请求头及配置的服务器前缀，不下载整首音频提取歌词。真实测试服务器已验证内嵌 text 返回有效歌词；失败与无歌词分别提示，允许重试，成功内容沿用本地歌词缓存。新增 4 项模拟服务回归测试，完整测试 61 项通过、3 项私密联调默认跳过，静态分析无问题；真实 Emby 只读联调另行通过，测试输出不含歌词、曲目名称或服务器地址。

- `build/internal-review/SylphyMusic-windows-release-internal.zip`：**21.72 MB**，完整解压后运行其中的 `sylphy_music.exe`，保留同目录数据与 DLL；原 Debug ZIP 为 55.4 MB。
- `build/internal-review/SylphyMusic-android-release-internal-arm64-v8a.apk`：**29.28 MB**，64 位 ARM；另提供 armeabi-v7a 26.22 MB 与 x86_64 31.59 MB；原通用 Debug APK 为 207.5 MB。
- Android 使用 Release 优化 / R8 / 图标裁剪并按架构拆分，本轮明确使用本机原测试证书签名，已核对两版证书摘要相同。API 35 x86_64 模拟器已通过 Debug→Release 直接覆盖安装、冷启动、主界面与无运行时错误日志检查；arm64 真机仍待验收。Windows Release 已实际启动。
- 同目录 `SHA256SUMS-optimized.txt` 提供文件摘要。输出由普通 `lib/main.dart` 构建，已覆盖集成测试入口，并检查已知 Emby URL / 密码未出现在已跟踪源码和包内容中。`tool/build_review.ps1` 可重复构建较小的内部验收包；Release 构建保留 pub / 插件注册生成步骤，避免集成测试开发插件残留。

Windows 主界面与来源管理已实际打开检查。测试用 Navidrome 和独立模拟器在验证结束后停止，私密资料继续留在 Git 忽略目录；此记录不表示当前仍有应用窗口运行。

## 开发文档维护

2026-10-27 补齐仓库 `AGENTS.md`、`ARCH.md`、`CONTRIBUTING.md` 和文档索引，工作目录外层增加工程入口。架构更新至 WebDAV、SQL 分页索引、来源生命周期、歌单意图日志和 TEMP / READY 缓存的实际实现。统一最新测试数量与日志位置，保留 Linux、真机及正式发布的未完成闸门。本轮只修改文档，核对相对链接、命令及代码路径，不重新构建安装包。


## 2026-10-27 UI 调整

依据用户提供的界面参考，在原 Flutter 工程中完成四项导航（首页 / 音乐库 / 歌单 / 我的）、右上角设置与设置内音乐源管理、可跳过并保存选择的首次连接引导、Material 3 首页卡片和专辑区、最近播放 / 收藏 / 下载入口、单行迷你播放器，以及封面 / 唱片与滑动歌词视图。外观设置持久化主题、背景和默认关闭的实验性磨砂效果。最近播放只保存最多 50 个 TrackRef，监听已开始的播放，写入排队并在关闭数据库前收尾；暂停队列恢复不生成记录。不改来源协议、数据库版本和缓存 / 云歌单状态机。

静态分析无问题；全量单元 / Widget 测试 66 项通过，4 项私密环境测试默认跳过（日志 `build/test_logs/ui-unit-suite.log`）。新增 Windows 原生 UI 集成测试通过：360×800 与 1200×850、浅色 / 深色、引导跳过后再次进入、四项导航、来源跳转、样式保存、合成 WAV 的真实播放记录、唱片 / 封面切换和滑动歌词，未发现布局溢出（日志 `build/test_logs/ui-native-windows.log`）。测试补获并修复首页首次从空库导入后专辑区未刷新问题；截图保存在 `build/test_logs/ui/`，只含合成数据。

本轮未执行 Android 设备验证或重新生成内部 Release 安装包，Linux 仍暂缓。参考讨论中的新增协议、独立文件夹浏览、智能歌单、唱片旋转、图标 / 语言设置和封面取色主题不在本轮实现范围，见 [界面说明](UI_REFRESH.md)。原有内部验收 ZIP / APK 不包含本轮 UI 变化。

Windows 既有原生桌面回归另行通过（`build/test_logs/ui-desktop-regression.log`）：原生媒体控制、本地 / 回环音频、Seek、完整缓存和新音乐库入口分页导航。此验证使用合成数据，未连接私人服务器。

集成测试结束后已重新构建普通 `lib/main.dart` Windows Debug 入口（`build/test_logs/ui-windows-build.log`）；可运行 `build/windows/x64/runner/Debug/sylphy_music.exe`，需保留整个输出目录的依赖。未重打包 Release ZIP / APK。


## 2026-10-27 UI 版 APK 打包

按用户「打包apk」请求，使用 `tool/build_review.ps1` 完成普通 `lib/main.dart` 入口的 Android Release / split-per-ABI 构建及内部打包。此次输出已包含上文 UI 改动，替代此前不含新 UI 的同名安装包：arm64-v8a **28.69 MB**、armeabi-v7a **25.60 MB**、x86_64 **31.00 MB**，位于 `build/internal-review/`。现有脚本同时刷新 Windows Release ZIP（21.49 MB）。

三份 APK 均通过 apksigner 验证，签名证书与此前内部 arm64 APK 一致；未配置正式签名文件，沿用现有本机测试证书。核对包名 `music.sylphy.sylphy_music`、版本名 0.2.0、最低 Android API 24 与各 APK 单一目标 ABI。使用本机既有私密凭据文件进行已跟踪源码和安装包解压内容扫描，未输出凭据；打包成功且全部产物 SHA-256 与清单一致。日志为 `build/test_logs/ui-review-build.log`，摘要为 `build/internal-review/SHA256SUMS-optimized.txt`。本轮未安装到 Android 设备或重新执行 Android 运行验收；此为内部验收包，尚非正式发布。


## 2026-10-27 独立搜索与歌曲连续滚动

主界面原同步图标替换为搜索入口，进入独立 SearchPage；音乐库移除搜索框，来源与排序功能保留。「同步所有来源」移至设置中的音乐源管理页，沿用原操作及忙碌禁用行为。搜索支持分类、来源过滤、250 ms 输入防抖、提交立即执行、清空与无结果提示。

歌曲视图移除上一页 / 下一页与页码，改为虚拟连续滚动；底层仍按每批 100 行读取 SQLite，滚动缓存最多六批，切换查询或索引版本时丢弃旧代次异步结果。播放全部和点播仍按完整查询建立 TrackRef 队列，未改成仅播放已加载批次。专辑和艺术家的聚合列表保留原分页。

验证：flutter analyze 无问题，全套 66 项单元 / Widget 测试通过、4 项私密测试默认跳过（`build/test_logs/search-unit-suite.log`）。Windows 三项原生集成均通过：五万首曲库跨批次跳转、末尾、返回顶部和请求中改查（`continuous-large-library.log`）；独立搜索、无匹配 / 清空、新按钮位置与小屏布局（`search-ui-native.log`）；本地 / 回环播放、Seek、缓存及连续歌曲列表（`continuous-desktop.log`）。以上日志均在 `build/test_logs/`；新搜索和音乐源页截图在 `build/test_logs/ui/`，仅含合成数据。Android 本轮未安装验收。

已使用 `tool/build_review.ps1` 更新普通主入口 Release APK，包含此次搜索 / 同步入口和连续滚动改动：arm64 28.69 MB、32 位 ARM 25.63 MB、x86_64 31.00 MB，同目录 Windows ZIP 21.50 MB。已通过既有私密值内容扫描、三份 APK 签名验证（证书与旧内部包一致）及全部产物 SHA-256 核对。日志 `build/test_logs/search-review-build.log`；沿用本机测试签名，仍为内部验收包。


## 2026-10-27 歌曲数量行与排序位置

音乐库歌曲列表将来源过滤、排序和升降序按钮移至播放操作行右侧，移除分类下方原按钮行，保留播放图标，文字只显示歌曲数量数字。复用的搜索 / 分组歌曲列表和歌单曲目列表也移除「播放全部 · … 首」文案；播放动作保持不变，播放图标保留 Tooltip。专辑 / 艺术家聚合视图保留原排序入口。

静态分析通过，Windows 原生 UI 集成通过（`build/test_logs/sort-row-ui.log`），确认 360×800 下数量与排序同排、排序可操作且无溢出；3 项播放 / Widget 回归通过（`sort-row-playback.log`）。截图 `build/test_logs/ui/library-sort-mobile.png` 使用合成数据。未新增业务能力或更改曲库查询、音频和缓存逻辑。

数量行的过滤 / 排序调整已通过 `tool/build_review.ps1` 重建并打包普通入口 Release：arm64 28.69 MB、32 位 ARM 25.63 MB、x86_64 31.00 MB。内容扫描、三份 APK 签名及产物摘要核对通过，使用现有内部测试签名；日志 `build/test_logs/sort-row-review-build.log`。本轮未执行 Android 真机安装验证。

## 2026-10-27 Emby 封面修复

真实服务器抽样 250 首中 248 首声明歌曲自身的 Primary 图片，原实现却优先请求 AlbumId，实服复现专辑图片 404、单曲图片 200。现按图片所属对象选择 ID 与 tag，兼容旧索引行与带 / 不带反向代理前缀的配置；缺图 404 可回退专辑 / 继承图，鉴权失败不当作缺图回退。封面请求与磁盘缓存 key 加入图片版本，界面在 tag 更新时换图，失败结果不永久缓存；下载最多六路并发，并增加响应超时。

7 项新增回归通过，覆盖歌曲 / 专辑 / 继承图片身份与 tag、URL 前缀、404 与鉴权边界、失败重试、缓存重用、版本变化和并发限制。真实服务器随机 8 张图片下载与 Flutter 图片解码通过；未记录私有地址、图片身份或内容。完整回归 73 项通过、5 项私密环境测试默认跳过，静态分析通过，Windows 原生 UI 集成通过。日志位于忽略目录 build/test_logs/cover-fix-suite.log、emby-cover-live.log、cover-fix-windows-ui.log。本轮 Android 先做优化包构建，未据此声明真机封面验收。

封面修复已由 tool/build_review.ps1 重建普通入口优化包：arm64 28.69 MB、32 位 ARM 25.63 MB、x86_64 31.00 MB，Windows ZIP 21.50 MB。两组既有测试凭据的私密值内容扫描通过，三份 APK 签名及全部产物 SHA-256、Windows ZIP CRC 均通过；日志 build/test_logs/cover-fix-package.log。沿用本机内部测试签名，未进行远端推送。


## 2026-10-27 手势条、自定义外观与列表补充

查阅 Flutter / Android 官方 edge-to-edge、SystemUiOverlayStyle、SafeArea 与 NavigationBar 文档后，新增统一 AppSystemBars：Android 启动显式启用边到边，手势导航透明并按主题切换图标明暗；三键导航保留系统对比度保护。API 29+ 原生昼夜启动主题同步透明系统栏。首页导航栏只避让一次底部 Insets，全屏播放器、队列弹层、独立页面及列表补齐安全区。未隐藏手势条、未降低 targetSdk 或退出 Android 15 / 16 的 edge-to-edge。

新增主题色与背景图设置。默认实际主色 #5094B2，支持预设 / HEX 输入和恢复默认；背景图保持比例自适应铺满，**仅首页、音乐库、歌单、我的四个一级页面使用**，其他路由保持主题 Surface。图片在应用数据目录保存受管副本，最长边归一化到 2048，源文件上限 40 MB；替换失败保留原背景，清理不删除用户原始图片，关闭数据库前等待写入完成。颜色对话框控制器由自身生命周期管理，修复应用新主题时退场动画中使用已释放控制器的问题。

首页左上角仅显示应用名：系统为英文时 `Sylphy Music`，其他语言「风灵音乐」；另三个一级页面显示对应页名，移除原副标题，并监听系统语言变化。专辑、艺术家与歌曲统一采用虚拟连续滚动，保持每批 100 行与最多六批缓存，不再显示任何分页栏。

验证：静态分析无问题；77 项单元 / Widget 测试通过，5 项私密联调默认跳过（`build/test_logs/appearance-full-suite.log`，包含工作区封面相关回归）。新增 appearance_test 覆盖主色、偏好恢复、原文件独立、坏图失败保留、图片比例 / 尺寸与串行清理。Windows UI 原生集成通过中英文系统名称、一级页面名和 360×800 / 宽屏布局（`appearance-ui-windows.log`）；五万首歌曲及 200 组专辑 / 艺术家连续列表跨 100 行边界、末尾和返回顶部通过（`continuous-all-groups.log`）。日志均位于 build/test_logs。

独立 SylphyTest_API35 模拟器上的手势、三键导航原生测试均通过（`build/test_logs/edge/gesture.log`、`threebutton.log`）：浅色 / 深色、主题颜色应用 / 恢复、自定义背景和设置 / 搜索 / 播放等路由排除、原生软键盘、全屏播放和队列弹层。实测 Insets 及 NavigationBar 总高度，Seek 控件在安全区内；从 Android 合成器获取含系统栏的合成数据截图，未涉及私人音乐库。测试结束恢复原手势模式并关闭本轮启动的模拟器。物理设备、更多系统版本和厂商系统仍待验收。

说明与资料链接：[Android 系统栏](ANDROID_SYSTEM_BARS.md)、[自定义外观](APPEARANCE.md)。

补充：空来源的数量行现在显示 0，并保留过滤与排序入口，可直接切回全部来源；Windows UI 集成已覆盖。Appearance 关闭放在媒体 / 索引等生产任务停止之后、SQLite 关闭之前。Windows 构建曾因并行单元测试占用 sqlite3.dll 失败，已结束占用后串行重建并通过，未删除数据或重建 Runner。

最终补查后 7 项外观 / 原生播放回归通过（`appearance-final-regression.log`）；重新使用 `tool/build_review.ps1` 生成普通主入口 Release 包，三份 APK 均包含本轮所有外观、标题与列表改动：arm64 28.82 MB、32 位 ARM 25.68 MB、x86_64 31.06 MB，Windows ZIP 21.52 MB。安装包内容扫描、三份 APK 签名验证及 SHA-256 清单核对通过，证书与原内部包一致；日志 `build/test_logs/appearance-review-build.log`。沿用本机内部测试签名，未声明正式发布或物理设备验收完成。

## 2026-10-27 播放失败提示改为短暂吐司

移除迷你 / 完整播放栏的常驻错误文字和重试行，应用根页面统一显示浮动吐司，3 秒自动消失；播放恢复后提前收起，重复状态更新不续时或排队，不拦截点击，切换路由仍只有一个通知。通知使用概括文本，不显示含私人连接信息的原生错误明细。播放器在实际播放进度恢复时清空旧 error；失败后再次点击播放重新加载媒体，原有自动重连与连续失败停止规则保留。

4 项吐司 Widget 回归覆盖自动消失、恢复收起、重复与快速事件、路由 / 点击和卸载定时器清理，新增真实 libmpv 进度恢复清错回归；相关 8 项回归通过。完整测试 82 项通过、5 项私密环境测试默认跳过，静态分析通过。日志 build/test_logs/playback-toast-regression.log 与 playback-toast-suite.log。本轮未据桌面测试声明 Android 真机通知验收。

已重新生成普通入口优化包：arm64 28.82 MB、32 位 ARM 25.68 MB、x86_64 31.06 MB、Windows ZIP 21.52 MB。两组测试凭据私密值扫描、三份 APK 签名、产物 SHA-256 和 Windows ZIP CRC 验证通过；日志 build/test_logs/playback-toast-build.log。沿用内部测试签名。

## 2026-10-27 沉浸播放页与歌词完善

依据用户补充的 P2 设计说明，播放页改用全屏封面模糊背景、深色渐变与局部深色主题，大封面 / 唱片成为主视觉。移除全屏底部重复的歌曲信息条，仅保留进度、时间、五项播放控制与队列，音质信息移入更多菜单。手机支持点击与滑动切换封面 / 歌词，歌词视图顶部保留小封面与曲目信息；宽屏并排展示。沿用沉浸背景开关与用户主色，未新增调色板依赖、定时关闭或唱片旋转。

歌词改为按实际文本高度定位和完整换行，同时间戳原文 / 译文合并、空行间奏提示、小 / 标准 / 大字号、系统字体缩放与减少动画；手动滚动暂停跟随，通过「回到当前」恢复，点击歌词仍可 Seek。保留无时间轴文本阅读、错误重试及每曲导入；原生新增测试捕获并修复重试 setState 回调意外返回 Future 的问题。

验证：静态分析无问题；歌词解析 / Widget 与既有播放通知 9 项相关回归通过（build/test_logs/immersive-regression.log）。Windows 原生 UI 集成通过 360×800、1200×850、合成封面与双语歌词、无歌词重试、手动浏览 / 回到当前、单一队列入口与无布局异常（immersive-ui-windows.log）。已查看合成截图 build/test_logs/ui/player-lyrics-mobile.png 与 player-immersive-wide.png。随后重新构建普通 lib/main.dart Windows Debug 入口成功（immersive-windows-build.log）。本轮未执行 Android 设备测试、全量单元测试或重新生成 Release ZIP / APK；现有内部安装包尚不包含本轮变化。

## 2026-10-27 可视化播放页编辑器

按用户指定的共享设计说明实现组件注册表、版本化布局数据、渲染器与独立编辑草稿；不新增播放器实例或替换来源 / 缓存 / 云歌单通路。入口为播放页「更多 → 编辑播放页」。提供沉浸封面、歌词优先和个人模板；分区内拖动、右下角缩放、4 / 8 dp 网格开关、中心 / 边缘 / 等距参考线，最多 80 步撤销 / 重做。组件可添加、锁定、隐藏、删除，支持区域、宽高、透明度、字号、对齐、预设颜色、封面圆形 / 圆角及背景样式；手机与宽屏自适应分区，小窗口保留最小组件尺寸并滚动。

保存并应用、另存、改名、恢复默认、JSON 导入导出已接入；模板与当前选择在现有 SQLite settings 一次写入，不修改 schema，关闭数据库前等待队列完成。导入先到草稿，拒绝未知版本 / 组件、越界数值、重复 ID 和超过 128 KiB 的文件。坏的持久化数据不自动覆盖。固定顶栏不受布局删除影响，删空也能重新编辑或恢复系统默认。编辑和预览均屏蔽组件指针操作，避免误触播放 / Seek。配置不包含曲目身份、音乐源、文件路径和凭据。

补测发现本地旁挂 LRC 会被 mpv 重复作为外部字幕自动加载，在 Windows 扩展路径上报「无法打开外部文件」，触发已有错误处理并暂停播放。现关闭 mpv 的 sub-auto，歌词继续由应用解析；同一合成 WAV + LRC 的原生测试已覆盖正在播放时进入编辑器、保存切换模板与暂停后进度保留。另修复浅色主界面进入深色播放页后图标继承黑色的问题，背景配置统一覆盖到顶栏与内容区。

本轮使用现有 ChangeNotifier、SQLite 和 Flutter 手势能力，不新增布局拖动 / 状态管理依赖。解除分区自由画布、复杂图层、逐字歌词、圆形进度、旋转封面、在线主题分享等后续阶段尚未实现。详见 [播放页布局编辑器](PLAYER_LAYOUT_EDITOR.md)。

本轮最终验证：静态分析无问题；全量单元 / Widget 测试 **93 项通过、5 项私密环境测试默认跳过**（build/test_logs/layout-full-suite.log）。Windows 原生编辑器集成通过：360×800、1200×850、320×640，拖动 / 缩放、撤销重做、编辑与预览不误触播放 / Seek、自定义控件正常开始播放、播放中编辑并切换模板不中断、模板恢复、删空组件后恢复入口及歌词显示（layout-native.log，最终运行未启用 headless）。既有 Windows UI 集成也通过（layout-ui-regression.log）。检查了合成截图 build/test_logs/layout/editor-selected-mobile.png、editor-wide.png 与 custom-lyrics-mobile.png；截图无私人曲库内容。已成功重建普通 lib/main.dart Windows Debug 入口（layout-windows-build.log），格式和 diff 空白检查通过。

初次播放中编辑测试揭示的旁挂 LRC 原生加载错误已修复并由最终同一用例通过验证；不把早期失败或 headless 排查运行计为最终通过。JSON 模型 / 存储的往返、非法文件拒绝及保留旧数据已有自动化覆盖；系统文件选择器的完整人工导入导出流程与 Android 设备尚未验收。未重新生成 Release ZIP / APK，现有内部安装包不含本轮编辑器。

按用户明确要求执行 `flutter build apk`：普通 `lib/main.dart` Release 通用 APK 构建成功，输出 `build/app/outputs/flutter-apk/app-release.apk`，84,967,215 字节（Flutter 显示 81.0 MB），包含本轮播放页编辑器与歌词 / 播放修复。缺少正式 key.properties，沿用既有 SYLPHY_INTERNAL_DEBUG_SIGNING 本机测试签名；进程内临时启用后恢复。apksigner 验证通过、ZIP CRC 完整性通过，包含 arm64-v8a / armeabi-v7a / x86_64 三种 ABI，未发现私密目录、签名配置或密钥文件被打包。日志 build/test_logs/layout-apk-build.log。本次未安装到设备，也未覆盖 build/internal-review 的旧分架构 APK。

## 2026-10-27 合并随机与循环模式

用户要求将随机播放、列表循环、单曲循环合并。迷你播放器、默认全屏与自定义布局统一使用 PlaybackModeButton，一个按钮依次切换列表循环 → 单曲循环 → 随机播放 → 列表循环，图标和 Tooltip 随状态更新。全屏主播放按钮保留居中，原独立随机 / 循环两个入口移除，编辑预览仍不可操作播放。

PlaybackCoordinator 一次更新 repeat / shuffle / order，三种状态互斥，随机模式循环整个队列；切换不加载新媒体，不改变歌曲、进度和暂停状态，保留历史。退出随机恢复自然顺序。旧顺序模式和缺省配置读取为列表循环，旧随机 + 单曲循环组合按单曲循环恢复；队列身份、当前索引、进度与历史继续保留，保存随机排列并在重启后恢复，无数据库 schema 变更。

验证：静态分析无问题，完整单元 / Widget 测试 98 项通过、5 项私密环境测试默认跳过（build/test_logs/mode-full-suite.log），新增覆盖三态循环、旧配置兼容、模式切换期间音频身份 / 进度 / 暂停状态保持、随机排列重启恢复及列表末尾回到第一首。Windows 原生编辑器 / 播放页交互通过（mode-native.log），验证默认与自定义布局共用单一入口、三态切换、保存和播放中编辑。主界面原生回归首次进程提前退出、未完成；独立重新运行通过 360×800 与宽屏布局及迷你播放器（mode-ui-regression-retry.log），不把首次中断计作通过。

已更新普通主入口通用 Release APK：build/app/outputs/flutter-apk/app-release.apk，约 81.0 MiB，包含合并后的模式按钮。沿用本机内部测试签名，签名验证及 ZIP 完整性检查通过；未发现私密目录或签名密钥文件被打包。普通 Windows Debug 主入口同步重建成功。日志 mode-apk-build.log 与 mode-windows-build.log。Android 本轮仅构建、未在设备上安装验证；旧 build/internal-review 分架构包未刷新。

## 2026-10-27 Emby 歌词时间轴修复

按用户提供的 API 与指定凭据执行只读排查：内嵌 Codec=text、IsTextSubtitleStream=true，Stream.txt 返回纯文本而无时间轴，Stream.srt 返回 55 条带起止时间的字幕；该样本的 LRC / VTT 转换为空、JSON 格式返回 404。实际响应仅保存在 Git 忽略的 .private，未把地址、账号、Token、媒体身份或歌词加入源码、公开日志和安装包。

EmbyAdapter 改为文本流优先 SRT 转换，外置 LRC 仍优先原格式；兼容原 Items / Videos 路径，不支持格式回退 TXT，保留认证头、前缀、禁止重定向与 1 MiB 上限。统一转换小时 / 分钟 / 秒 / 毫秒为 LRC，保留同时间译文顺序，间奏按字幕结束时间解除上一句高亮。旧 Emby 纯文本缓存尝试升级至 emby-timed-v2，旧文件保留为失败 / 无新内容时的回退；新手动导入独立保存并优先使用。旧版无来源标记的手动纯文本仍保留原件，但若需继续覆盖服务器时间轴，需重新导入一次。详情见 [Emby 歌词](EMBY_LYRICS.md)。

验证：格式和静态分析通过；109 项单元 / Widget 测试通过、5 项私密环境测试默认跳过（build/test_logs/emby-timing-full-suite.log）。包括 15 项歌词协议 / 解析 / Widget 回归和 5 项缓存迁移 / 导入 / 失败保留测试；私密实服 SRT 快照逐条验证 55 个起始时间全部保留，规范化后 62 行（含间奏空行），不输出实际歌词（emby-timing-snapshot.log）。Windows 原生编辑器 / 播放页回归通过（emby-timing-native.log）。实服验证为实际响应抓取加本地快照对照，不宣称在 Android 上完成真实服务器播放验收。

已重新生成普通 lib/main.dart 通用 Release APK（build/app/outputs/flutter-apk/app-release.apk，约 81.0 MiB），三个 ABI 的 libapp.so 均核对包含本轮时间轴缓存版本。沿用本机内部测试签名，apksigner、ZIP CRC 和指定凭据的源码 / 包内私密值扫描通过，凭据未输出。Windows Debug 普通入口同步构建成功。日志 emby-timing-apk-build.log、emby-timing-windows-build.log。本轮未在 Android 设备安装验收，也未刷新 build/internal-review 旧分架构包。

## 2026-10-27 播放控件、唱片旋转与自定义歌词分页

播放 / 暂停按钮改为支持圆角矩形，自定义布局的「播放控制」面板可调圆角与按钮宽度。队列入口移入模式、上一首、播放 / 暂停、下一首同一排控制区，保留主按钮居中；默认布局移除原下方重复队列按钮。内置模板删除独立队列元素，旧版内置 bottom/queue 元素读取时合并，另行插入或移动到其他区域的用户元素保留。

圆形封面新增「播放时旋转」属性并随模板保存；系统默认唱片样式可在更多菜单设置旋转，偏好持久化。统一 RotatingCover 按播放状态约 20 秒一圈，暂停保持角度、继续后接着旋转，切歌重置；编辑预览、方形封面、隐藏页面及减少动画模式不转。此实现不驱动或重建播放内核。

修复自定义布局直接进入 Renderer 而失去封面 / 歌词 PageView 的问题：正常展示始终支持从右向左进入独立歌词页，反向返回。两页共享一个固定控制区，横向滑动不移动进度与播放按钮，也不影响歌曲或播放进度。是否能进入歌词页不再取决于模板里有没有歌词组件。独立歌词页复用既有获取和时间轴逻辑。

当前验证：静态分析无问题；113 项单元 / Widget 测试通过、5 项私密环境测试默认跳过（build/test_logs/player-polish-full-suite.log）。新增测试覆盖旋转 / 暂停 / 恢复 / 隐藏 / 减少动画、旋转偏好恢复、按钮样式保存和旧布局兼容。Windows 原生播放页编辑器集成通过圆角和宽度实际渲染、保存后右向左滑动进歌词及返回、控制区固定不动、队列打开、播放和编辑恢复（player-polish-native.log）。本轮未做真实服务器联调，未读取私人曲库或凭据。

既有 Windows 主界面 / 默认播放器原生回归也通过（player-polish-ui.log），合成数据截图已查看 build/test_logs/layout/custom-swiped-lyrics.png。已重建普通 lib/main.dart Windows Debug 与通用 Release APK（约 81.0 MiB），APK 三种 ABI 均包含本轮按钮宽度和自定义分页实现，测试签名、ZIP 完整性与私密目录 / 密钥文件排除检查通过；日志 player-polish-apk-build.log、player-polish-windows-build.log。保留此前 Emby 时间轴和合并播放模式修复。Android 仅构建，未进行设备安装 / 手势 / 旋转验收，旧 build/internal-review 分架构包未刷新。


## 2026-10-27 播放页视觉审计落地与控制尺寸

按用户确认的审计方案统一默认与自定义播放页：顶栏保留收起 / 更多，将封面切换、歌词导入和字号移到更多；共用 PlayerBackdrop、PlayerProgress、PlayerControls，统一主题强调色、遮罩、时间与滑轨边界及主按钮默认尺寸。手机使用双圆点提示，保留右向左歌词手势、固定控制区和队列；歌词页统一小封面信息，隐藏常驻状态工具栏与定时歌词桌面滚动条。

同时间戳第一行为主句，后续行按约 65% 字号、较低字重和亮度显示，不自动推断语言；TextPainter 与富文本渲染使用相同度量，焦点调整至可用高度约 43%，保留长句换行、大字体、手动浏览 / 回到当前及 Seek。新模板收拢信息间距；旧自定义竖屏坐标保留。宽屏将封面与信息集中到左侧，右侧歌词、左下控制，内容最大宽度 1200；可选 wideFrame / wideRegion 使宽屏编辑独立保存，旧 v1 文件无需重写。编辑器仅突出所选区域，缩放手柄保持约 36 dp 屏幕尺寸。

按追加要求，播放控制组件新增按钮间距 0–32 dp、主播放按钮高度 48–96 dp，保留独立宽度 56–96 dp 和圆角；图标随主按钮高度变化，两侧按钮尺寸保持稳定。控件不随外框整体缩放，窄屏只限制实际间距而保留保存值，较大主按钮增加控制区最小高度。props.playHeight / controlSpacing 随模板保存，旧布局默认高 64 / 间距 12，不改数据库 schema。

验证：静态分析无问题（audit-analyze.log）；115 项单元 / Widget 测试通过、5 项私密环境测试默认跳过（audit-full-suite.log）。覆盖双语层级、实际文字高度与大字体焦点、模板旧值兼容 / 非法值拒绝、宽屏分组及独立坐标保存。Windows 编辑器原生回归通过 360×800、1200×850、320×640，验证主按钮实际 88×80 尺寸、间距变化和窄屏限制、96×96 按钮、固定队列位置、滑动歌词、播放中编辑与保存（audit-layout-native.log）。已检查合成截图 custom-lyrics-wide.png、custom-swiped-lyrics.png、custom-controls-small.png 和编辑器截图。

默认播放器 / 主界面原生回归首次测试进程提前退出、未完成（audit-ui-native.log）；独立重跑通过（audit-ui-native-retry.log），包括方形 / 唱片菜单、双语歌词、回到当前、手机 / 宽屏和单一队列入口；不将首次中断计作通过。检查了新的 player-lyrics-mobile.png 与 player-immersive-wide.png。随后普通 lib/main.dart Windows Debug 构建成功（audit-windows-build.log）。本轮未访问真实服务器或凭据，未做 Android 设备验证，未重新生成 APK / Release ZIP；现有 APK 不含此次视觉收敛与间距 / 高度配置。

## 2026-10-27 播放页区块与歌词预览

播放页默认布局改为封面、歌词信息、播放控制三个可切换顺序的区块，移除封面 / 歌词指示点。歌词信息区按可用高度显示最多三句当前歌词，点击打开完整歌词；歌词字号 20 / 24 / 28 和区块顺序写入 settings 持久化，可在设置和播放页「更多」调整。播放页按钮、进度和歌词高亮从当前封面提取色板，失败时回退主题色；播放页支持下滑退出。外观新增纯色背景，未设置背景图时默认启用，浅色 / 深色模式分别使用白 / 黑；已有背景图保持显示，重新选择背景图会关闭纯色模式。

验证结果：\dart format\ 与 \lutter analyze\ 通过；\lutter test --no-pub test/appearance_test.dart test/lyrics_preview_test.dart test/cover_palette_test.dart test/lyrics_view_test.dart test/player_layout_test.dart\ 通过；\lutter test integration_test/ui_refresh_test.dart -d windows\ 与 \lutter test integration_test/player_layout_test.dart -d windows\ 通过。截图输出到 \uild/test_logs/ui/player-disc-mobile.png\、\player-zones-mobile.png\、\player-lyrics-preview.png\、\player-immersive-wide.png\。本轮未重新构建 Android / Windows 发布包，正式签名与真机验收门槛不变。

## 2026-10-27 播放页全画布收敛、统一唱片与唯一歌词页

按用户反馈解决播放页审计问题，并把编辑方式收敛为整页自由画布：

- 播放页不再划分封面区、歌词信息区、播放控制区，也不再提供区块顺序。系统默认页和自定义模板共用同一个 `PlayerLayoutRenderer`；编辑器直接载入当前实际页面，按当前安全区、顶栏和最大 1200 dp 内容宽度计算画布，使用封面取色主题、当前封面和真实歌词。
- 编辑器提供 9 宫格（3×3）与 16 宫格（4×4）辅助线及吸附，移除了 4 / 8 dp、区域边框、分区比例和所在区域选项。封面只保留「大小」，圆形边界、选择框和缩放手柄使用同一正方形。
- 唱片形状与旋转改为 `Appearance` 的全局设置；新增共享 `PlayerCover`，播放页、编辑器预览、歌词页头图和折叠迷你播放器共用同一封面组件与形状。唱片模式统一使用黑胶纹路、中心孔、阴影和旋转；编辑器不再显示与播放页不一致的独立圆形开关。
- 完整歌词收敛为唯一的 `LyricsPage`：歌词预览或「更多 → 查看完整歌词」打开同一页面，带返回键、字号菜单、播放进度和控制；删除了底部弹层与自定义布局 PageView。歌词预览最多显示五行，只取每个时间戳的主行，不再把原文 / 译文用 `·` 拼成一行后截断。
- 修复播放键对比度：移除页面级 `iconTheme`，播放 / 暂停按钮显式使用 `primary / onPrimary`，自定义背景色按亮度选择前景。
- 布局数据升级为 v2 全画布格式，存储 key 仍为 `player_layouts_v1`，容器版本 2。v1 区域坐标在读取时按旧公式迁移为整页坐标，并生成宽屏坐标；旧文件在用户保存或选中模板前不覆盖。逐元素 `circle` / `rotate` 不迁移，统一由全局外观控制。
- 设置不再把全局歌词字号写回模板逐元素字号；全局面板只更新歌词预览、完整歌词页和布局中的歌词预览。

验证：

- `flutter analyze` 无问题（`build/test_logs/refactor-analyze-final.log`）。
- 全量单元 / Widget 测试 **127 项通过、5 项私密环境测试默认跳过**（`build/test_logs/refactor-full-suite-final.log`）。
- Windows 原生 UI 集成通过 360×800 / 1200×850：统一完整歌词页、返回、预览与重试、方形 / 唱片切换、主播放键前景为 `onPrimary`、封面取色和下滑退出（`build/test_logs/refactor-ui-final.log`）。
- Windows 原生布局 / 编辑器集成通过 360×800 / 1200×850 / 320×640：从当前唱片页进入编辑器仍为唱片、保存后保持、封面与圆形选择边界重合、9 宫格显示、拖动 / 缩放 / 撤销重做、保存切换模板不中断播放、320 小窗完整歌词页无溢出（`build/test_logs/refactor-layout-native-final.log`）。
- 合成截图：`build/test_logs/layout/editor-mobile.png`、`editor-selected-mobile.png`、`custom-player-mobile.png`、`build/test_logs/ui/player-lyrics-mobile.png`、`player-immersive-wide.png`；均只含合成曲目和封面。
- 已重新构建普通 `lib/main.dart` Windows Debug 入口（`build/test_logs/refactor-windows-build.log`）。正式签名、真机与发布门槛不变。

## 2026-10-27 内部验收打包

按用户「打包」请求，使用 `tool/build_review.ps1` 从普通 `lib/main.dart` 入口重新构建 Android Release / split-per-ABI 与 Windows Release，并通过 `tool/package_review.py --mode optimized` 打包。使用现有私密测试凭据文件做内容扫描，未输出文件内容；扫描通过，未发现凭据进入已跟踪源码或包内容。

- `build/internal-review/SylphyMusic-android-release-internal-arm64-v8a.apk`：**29.43 MB**，versionCode 2002，仅 arm64-v8a。
- `build/internal-review/SylphyMusic-android-release-internal-armeabi-v7a.apk`：**26.40 MB**，versionCode 1002，仅 armeabi-v7a。
- `build/internal-review/SylphyMusic-android-release-internal-x86_64.apk`：**31.74 MB**，versionCode 4002，仅 x86_64。
- `build/internal-review/SylphyMusic-windows-release-internal.zip`：**21.84 MB**，完整解压后运行 `SylphyMusic/sylphy_music.exe`。
- 追加的右向左滑动歌词、迷你歌词缩放手柄、浅深色跟随、可选封面模糊、54 dp 底栏、独立迷你歌词字号与音乐库胶囊筛选已重新打入上述四份产物；包内容重新扫描、签名和 SHA-256 核对通过。
- 包名 `com.ymltsh.sylphymusic`，versionName 0.2.0，minSdk 24，targetSdk 36；三份 APK 均由本机 Android Debug 测试证书签名，签名方案 v2，三份证书 SHA-256 一致。没有正式 `key.properties`，因此仍不是正式发布包。
- 三份 APK 与 ZIP 的 SHA-256 均与 `SHA256SUMS-optimized.txt` 一致；Windows ZIP 与 APK ZIP 完整性检查通过，APK 的 ABI、包名、版本和 SDK 信息已核对。

本轮完成的是内部验收打包，未在 Android 设备安装运行，也未执行 Windows Release 启动或真机发布验收；APK / ZIP 使用合成数据与本地构建，正式签名、物理设备、Linux 和完整发布闸门仍按 [RELEASE_GATES](RELEASE_GATES.md) 执行。打包日志：`build/test_logs/review-build.log`。

## 2026-10-27 播放页滑动歌词与迷你歌词缩放

按追加需求补齐两个交互：

- 播放页内容区域支持从右向左滑动进入完整歌词页。该手势调用唯一的 `LyricsPage`，与点击歌词预览、菜单「查看完整歌词」共用同一页面，不恢复 PageView 或第二套歌词实现。滑动与页面下滑退出、控件点击和迷你歌词缩放手柄分开处理。
- 播放页的「歌词预览」作为独立 mini 歌词控件保留，右下角增加尺寸手柄；直接拖动可同时调整宽高，松手后保存。系统默认布局首次调整会创建一份自定义模板，避免把只读默认模板变成隐式全局偏好；已有自定义模板则直接更新。手柄使用原始指针事件，与页面横滑 / 下滑手势互斥，避免拖动手柄时误开歌词页或退出播放器。
- 迷你歌词区仍是布局组件，9 / 16 宫格编辑器和手柄两种调整方式都写入同一套全画布坐标；完整歌词页仍是独立路由。

验证：

- `flutter analyze` 无问题（`build/test_logs/swipe-analyze-final.log`）。
- 全量单元 / Widget 测试 **127 项通过、5 项私密环境测试默认跳过**（`build/test_logs/refactor-full-suite-final.log`）。
- Windows 原生 UI 集成通过：播放页右向左滑动进入歌词、返回；迷你歌词手柄拖动后歌词预览尺寸改变并创建自定义布局；主播放键、封面和下滑退出保持正常（`build/test_logs/swipe-ui-final.log`）。
- Windows 原生布局 / 编辑器集成继续通过 360×800 / 1200×850 / 320×640（`build/test_logs/swipe-layout-final.log`）。
- 合成截图：`build/test_logs/ui/player-mini-lyrics-resized.png`，只含合成数据。
- 已重新使用 `tool/build_review.ps1` 打包：arm64-v8a 29.22 MB、armeabi-v7a 26.16 MB、x86_64 31.46 MB、Windows ZIP 21.69 MB；四份产物 SHA-256 与签名复核通过（`build/test_logs/review-build.log`）。
- 集成测试后已重新构建普通 `lib/main.dart` Windows Debug 入口（`build/test_logs/swipe-windows-build.log`）。
- 尚未在 Android 设备验证滑动和直接缩放。正式签名与发布门槛不变。

## 2026-10-27 播放页跟随系统深浅色与可选封面模糊

按用户要求修正播放页主题：

- 播放页不再强制局部深色主题；它使用应用当前 `Theme.brightness`，因此跟随系统浅色 / 深色，也跟随用户手动选择的浅 / 深模式。封面取色同样按当前明暗提取并缓存。
- `PlayerBackdrop` 以纯色背景设置（白 / 黑）或主题 Surface 为基础；封面模糊改为默认关闭的可选层，可在设置或播放页「更多 → 封面模糊背景」开启。浅色模式使用白色系遮罩、深色模式使用黑色系遮罩。
- 纯色背景设置现在同时作用于一级页面和播放页基础底色，不再是只有一级页面才生效的设置；播放页局部布局仍可选择主题渐变、纯色或封面模糊。
- 播放页、完整歌词页和布局编辑器预览共享当前明暗、封面取色和背景规则；歌词页在浅色模式下验证了返回、字号、进度和播放控制的对比度。
- 「沉浸背景」设置更名为「封面模糊背景」，默认关闭；未显式保存过的旧安装按新默认值处理。布局编辑器的「封面模糊」选项提示它受该总开关控制。

验证：

- `flutter analyze` 无问题（`build/test_logs/theme-analyze-final.log`）。
- 全量单元 / Widget 测试 **127 项通过、5 项私密环境测试默认跳过**（`build/test_logs/theme-full-suite-final.log`）。
- Windows 原生 UI 集成通过：深色播放页、切到浅色后的白色纯色底、封面模糊菜单开关、浅色封面模糊、浅色完整歌词页、迷你歌词缩放、右向左滑动、下滑退出（`build/test_logs/theme-ui-final.log`）。
- Windows 原生布局 / 编辑器集成继续通过 360×800 / 1200×850 / 320×640（`build/test_logs/theme-layout-final.log`）。
- 合成截图：`build/test_logs/ui/player-light-solid.png`、`player-light-cover-blur.png`、`player-lyrics-light.png`；播放页深色对比截图仍为 `player-disc-mobile.png` 与 `player-immersive-wide.png`。
- 已重新打包内部产物：arm64-v8a 29.22 MB、armeabi-v7a 26.16 MB、x86_64 31.46 MB、Windows ZIP 21.69 MB；SHA-256、签名和 ZIP 完整性复核通过（`build/test_logs/review-build.log`）。
- 集成测试后已重新构建普通 `lib/main.dart` Windows Debug 入口（`build/test_logs/theme-windows-build.log`）。
- 尚未在 Android 设备验证系统深浅色切换与封面模糊；正式签名与发布门槛不变。

## 2026-10-27 底栏高度调整

按用户要求，将手机底部 `NavigationBar` 高度从 72 dp 调整为 **54 dp**（减少 1/4）：

- 只调整底栏总高度，保留 `maintainBottomViewPadding`，继续由 NavigationBar 自身安全区避让系统手势条 / 三键导航，不额外叠加底部 Insets。
- 图标、文字、选择指示和迷你播放器位置随高度自然上移，没有新增溢出。
- 宽屏 NavigationRail 不受影响。
- 更新 Android 系统栏原生测试的期望高度为 `54 + 底部 inset`。
- `integration_test/ui_refresh_test.dart` 在 360×800 实际断言 NavigationBar 高度为 54，并完成原有导航 / 播放页流程。

验证：`flutter analyze` 无问题（`build/test_logs/navbar-analyze.log`）；全量单元 / Widget 测试 127 项通过、5 项默认跳过（`build/test_logs/navbar-full-suite.log`）；Windows 原生 UI 集成通过并实际断言底栏高度 54（`build/test_logs/navbar-ui.log`）；Windows Debug 重新构建（`build/test_logs/navbar-windows-build.log`）。Android 系统栏测试已同步为 `54 + inset`，但本轮未连接 Android 设备执行。内部包已按 `review-build.log` 重新生成并通过 SHA-256 / 签名 / ZIP 完整性核对。文件：`lib/ui/app_shell.dart`。

## 2026-10-27 迷你歌词字号独立设置

播放页的迷你歌词区现在有独立字号，不再跟随完整歌词页：

- `Appearance` 新增 `miniLyricFontSize`（16 / 20 / 24，默认 20）和 settings key `ui_mini_lyrics_font_size`；完整歌词继续使用 `lyricFontSize`（20 / 24 / 28），两者分别持久化。
- 播放页「更多 → 迷你歌词字号」打开选择面板；设置 → 外观与体验新增「迷你歌词字号」，原「歌词字号」更名为「完整歌词字号」。
- 迷你歌词区、布局编辑器预览使用迷你字号；完整歌词页和其顶部字号菜单继续使用完整歌词字号。
- 布局编辑器歌词组件说明已更新，不再声称预览与完整歌词共用字号。

验证：`flutter analyze` 无问题（`build/test_logs/minilyrics-analyze-final.log`）；全量单元 / Widget 测试 127 项通过、5 项默认跳过（`build/test_logs/minilyrics-full-suite.log`）；Windows 原生 UI 集成通过，实际把迷你字号从 20 切到 24 并断言 `LyricsPreview.fontSize` 更新（`build/test_logs/minilyrics-ui-1.log`）；Windows 布局 / 编辑器集成继续通过（`build/test_logs/minilyrics-layout.log`）。已重新打包内部产物（arm64-v8a 29.22 MB、armeabi-v7a 26.16 MB、x86_64 31.46 MB、Windows ZIP 21.70 MB），SHA-256、签名与 ZIP 完整性复核通过（`build/test_logs/review-build.log`）；集成测试后重新构建普通 Windows Debug（`build/test_logs/minilyrics-windows-build.log`）。尚未在 Android 设备验证字号设置。

## 2026-10-27 音乐库胶囊筛选栏

按用户要求，将音乐库的「歌曲 / 专辑 / 艺术家」连接式分段控制器改为胶囊筛选栏：

- 使用 3 枚独立 `ChoiceChip`，`StadiumBorder` 胶囊形；选中项为主题主色 + onPrimary 图标 / 文字，未选中项为 `surfaceContainerHighest` 半透明底 + onSurfaceVariant。
- 保留图标、横向滚动、单选手感和原有 `libraryView` 状态；窄屏可横向滚动，不再出现连接式分段边界。
- 未改动独立搜索页的分类控件及其测试语义。
- 集成测试断言 3 枚 `ChoiceChip` 存在、初始「歌曲」选中、切换「专辑」后对应选中；使用 `library-filter-*` key，避免点到其他同名文字。

验证：`flutter analyze` 无问题（`build/test_logs/chips-analyze-final.log`）；Windows 原生 UI 集成通过（`build/test_logs/chips-ui-final.log`，含 360×800 视觉截图 `build/test_logs/ui/library-sort-mobile.png`）；全量单元 / Widget 测试 127 项通过、5 项默认跳过（`build/test_logs/chips-full-suite.log`）。尚未在 Android 设备验证横向滚动与触摸手感。

## 2026-10-27 媒体资源持久化实现

实现 MediaAssetStore 与 LyricsStore，数据库升级 v6，远程封面 / 歌词统一记录身份、版本、文件、摘要、时效和访问时间。不可变内容文件经唯一 TEMP / flush / rename，再事务提交索引；启动对账清除残片、缺文件记录和无索引对象。封面按实际图片身份与 tag 复用，避免歌曲修改时间误失效；支持 HTTP 条件请求。远程歌词有效期内直接命中，过期先展示本地再刷新，同源同 key 请求合并，后台更新通知页面，不再每次重复拉取纯文本。显式重试强刷，手动导入优先且不参加普通淘汰。

按来源隔离和内容去重复用；封面 200 MiB、远程歌词 20 MiB 配额由 SQL 分批 LRU 管理，读取租约保护旧文件；元数据采用 64 MiB 加本次写入量预留，磁盘不足保留旧版本。来源停用和删除阻止晚到写入，退出等待资源任务。保留旧未区分手动 / 下载歌词作为恢复副本，迁移标记避免清理后重复导回。具体边界见 MEDIA_ASSETS.md。

存储、服务和页面测试覆盖迁移、重开离线命中、SWR、并发合并、版本竞态、损坏 / 磁盘不足、配额、手动保护和页面自动更新。Windows 与 API 35 Android 原生测试均通过：使用本机模拟 Emby 和合成图片，关闭服务器，重建应用服务及 SQLite，以空凭据库再次读取、解码和显示封面 / 歌词。Windows 受执行环境目录写入限制，使用工程内独立测试目录及进程 TEMP / TMP，通过后未修改系统权限。原生日志为 assets-native-windows.log 和 assets-native-android.log；不以服务重建代替物理设备强杀验收。

最终完整测试 159 项通过、5 项私密环境测试默认跳过，静态分析与 Dart 格式检查通过。重建普通入口 Release 优化包：arm64 29.28 MB、32 位 ARM 26.22 MB、x86_64 31.59 MB、Windows ZIP 21.72 MB。两组测试凭据内容扫描、APK 签名、产物摘要及 ZIP CRC 验证通过；API 35 模拟器已成功覆盖安装 x86_64 优化包并冷启动。日志 assets-full-suite.log、assets-review-build.log 位于 build/test_logs。仍使用本机内部测试签名，未推送远端。

## 2026-10-28 Android applicationId 修改

按用户要求，将 Android 包名从 `music.sylphy.sylphy_music` 改为 **`com.ymltsh.sylphymusic`**，并重新打包 APK：

- `android/app/build.gradle.kts` 的 `namespace` 与 `applicationId` 同步修改。
- Kotlin 源文件移动至 `android/app/src/main/kotlin/com/ymltsh/sylphymusic/`，`MainActivity.kt` 与 `CacheForegroundService.kt` 的 package 声明同步更新。
- `tool/bootstrap_platforms.py` 的原生 runner 校验路径同步更新。
- Android Manifest 仍使用相对 Activity / Service 名称，构建后的清单已解析为 `com.ymltsh.sylphymusic.MainActivity` 与 `com.ymltsh.sylphymusic.CacheForegroundService`。
- Linux APPLICATION_ID、Windows 桌面标识和 Dart package 名称 `sylphy_music` 未改变；本轮只变更 Android 应用身份。

验证：`flutter analyze` 无问题；使用 `tool/build_review.ps1` 重新构建并打包成功。三份 APK 经 `aapt dump badging` 核对：包名均为 `com.ymltsh.sylphymusic`、versionName 0.2.0、minSdk 24、targetSdk 36，versionCode 分别为 2002 / 1002 / 4002，ABI 分别为 arm64-v8a / armeabi-v7a / x86_64；启动 Activity 为新包名。`apksigner` 验证 APK Signature Scheme v2 通过，三份均使用同一本机 Android Debug 测试证书。SHA-256 与清单一致，APK ZIP 完整性和内容扫描通过（205 个已跟踪文件）。

产物：arm64-v8a 29.43 MB、armeabi-v7a 26.40 MB、x86_64 31.74 MB；Windows ZIP 21.84 MB。日志 `build/test_logs/package-rename-review-build.log`。未在 Android 设备安装运行。由于 applicationId 改变，新包是独立的 Android 应用身份，旧包数据不会自动迁移；尚未配置正式签名，因此仍不是正式发布包。

## 2026-10-28 应用显示名本地化

按用户澄清，不显示双语名称，也不建立第二个桌面名称；同一应用按系统语言显示单一名称：

- Android Manifest 的 `android:label` 改为 `@string/app_name`。默认资源为 `Sylphy Music`，新增 `values-zh/strings.xml` 为「风灵音乐」。
- 首页标题与 MaterialApp 标题统一通过 `lib/ui/app_identity.dart` 获取名称：英文系统为 `Sylphy Music`，中文及其他非英文系统为「风灵音乐」。MaterialApp 的原双语 title 已移除。
- Android 包名仍为 `com.ymltsh.sylphymusic`，未新增第二个应用身份；三份 APK 只是 ABI 拆分。

验证：`flutter analyze` 无问题；Windows UI 集成测试切换英文 / 中文系统并分别断言 `Sylphy Music` 与「风灵音乐」，测试通过。重新打包后 `aapt dump badging` 显示 `application-label:'Sylphy Music'`、`application-label-zh:'风灵音乐'`；包名、versionCode、SDK、ABI 与 v2 签名均保持通过，SHA-256 / ZIP 完整性检查通过。产物尺寸保持不变：arm64-v8a 29.43 MB、armeabi-v7a 26.40 MB、x86_64 31.74 MB；Windows ZIP 21.84 MB。尚未在 Android 真机切换语言安装验证。

## 2026-10-28 Android 后台播放前台服务修复

应用 `SylphyMusic-android-background-playback.patch`。补丁与当前 `playback.dart` 的上下文已有差异，`git apply --check` 不能直接通过，因此按补丁逻辑逐处合并到现有实现：

- 新增 `_playRequested`，让“用户想播放”的意图独立于底层播放器在切歌间隙短暂上报的 `playing=false`；`audio_service` 的 `PlaybackState.playing` 改用该意图，避免 Android 在换曲时退出前台服务。
- 新增 `_finishingTrack`，完成回调期间上报 buffering，并防止同一完成事件重复触发切歌。
- `_loadCurrent` 在打开下一首和申请音频焦点前先发布状态；打开期间收到暂停则不再自动播放，并在 finally 重新发布最终状态。
- `play` / `pause` / 自动 `next` / `_finished` / `_failed` / 重连 / 清空队列 / shutdown 均同步维护播放意图；移除当前曲目时用播放意图决定是否继续。
- 用户暂停仍然立即把 `PlaybackState.playing` 置为 false，不会因为过渡保护而继续占用前台服务。

验证：`flutter analyze` 无问题；全量单元 / Widget 测试 **166 项通过、5 项默认跳过**（`build/test_logs/background-playback-full-suite.log`），包含真实 libmpv 播放、暂停、切歌、队列移除与恢复测试。日志 `build/test_logs/background-playback-analyze.log`。由于没有连接 Android 真机，尚未实测锁屏跨曲和 FGS 存活的系统行为；本轮未重新打包 APK。

## 2026-10-28 测试签名 0.2.1+3 首次发布

按用户「测试签名即可」的明确授权，完成首个可更新版本的本地构建和 GitHub Release：

- `pubspec.yaml` 版本从 0.2.0+2 提升到 **0.2.1+3**，提交 `54b5f84`，标签 `v0.2.1+3` 已推送。
- 使用 `tool/build_review.ps1` 以本机 Android Debug 测试证书构建三 ABI APK；`aapt` 核对包名 `com.ymltsh.sylphymusic`、versionName 0.2.1、versionCode 2003 / 1003 / 4003、minSdk 24、targetSdk 36，`apksigner` v2 验签通过。
- GitHub Release：https://github.com/ymltsh/SylphyMusic/releases/tag/v0.2.1%2B3
  - `sylphy-music-0.2.1-3-arm64-v8a.apk` 29.43 MB
  - `sylphy-music-0.2.1-3-armeabi-v7a.apk` 26.40 MB
  - `sylphy-music-0.2.1-3-x86_64.apk` 31.74 MB
  - `SHA256SUMS.txt`
- `version.json` 已更新为 stable 0.2.1+3 并指向上述资产；`version-beta.json` 保持 `latest: null`。
- 应用内更新入口保持手动检查；未接入自动下载 / 静默安装。

限制：这是**测试签名**的 stable 清单，不是正式签名发布；17 项正式发布门槛仍未通过。由于 applicationId 从旧包名变更，旧包用户不会自动升级且旧数据不会迁移。尚未在 Android 真机安装验证锁屏后台播放、覆盖安装和更新检查。发布脚本因生产签名 / 正式门槛被明确绕过，改由内部构建和 GitHub API 上传；后续正式发布应恢复 `release.py` 流程。
