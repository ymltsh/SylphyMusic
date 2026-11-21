import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_controller.dart';
import '../core/appearance.dart';
import '../core/player_layout.dart';
import '../services/llm_recommendations.dart';
import 'about_page.dart';
import 'app_update_page.dart';
import 'cache_storage.dart';
import 'cache_tasks.dart';
import 'design_system/miuix_adaptive.dart';
import 'design_system/ui_style_availability.dart';
import 'desktop_settings_page.dart';
import 'device_transfer_page.dart';
import 'miuix/miuix_settings_preview_page.dart';
import 'launcher_icon_picker.dart';
import 'player_layout/layout_editor.dart';
import 'recommendation_letters_page.dart';
import 'recommendation_settings_page.dart';
import 'settings_cache_overview.dart';
import 'settings_controls.dart';
import 'theme_color_dialog.dart';

part 'settings_directory.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.app, required this.onSources})
    : _destination = null;
  const SettingsPage.llmConnection({super.key, required this.app})
    : onSources = null,
      _destination = _Destination.llmConnection;

  const SettingsPage._({required this.app, required this._destination})
    : onSources = null;

  final SylphyApp app;
  final VoidCallback? onSources;
  final _Destination? _destination;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SylphyApp get app => widget.app;
  bool _llmTestRunning = false;
  final _searchController = TextEditingController();

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _act(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _open(_Destination destination) async {
    FocusScope.of(context).unfocus();
    if (destination == _Destination.sources) {
      widget.onSources?.call();
      return;
    }
    if (destination == _Destination.playerEditor) {
      await _editPlayerLayout();
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => switch (destination) {
          _Destination.transfer => DeviceTransferPage(app: app),
          _Destination.desktop => DesktopSettingsPage(app: app),
          _Destination.recommendation => RecommendationSettingsPage(app: app),
          _Destination.letters => RecommendationLettersPage(app: app),
          _Destination.cacheStorage => CacheStoragePage(app: app),
          _Destination.downloads => CacheTasksPage(app: app),
          _Destination.updates => AppUpdatePage(
            onCheck: app.checkForUpdates,
            mirror: app.apiSettings.githubMirror,
          ),
          _Destination.about => const AboutPage(),
          _ => SettingsPage._(app: app, destination: destination),
        },
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _editPlayerLayout() async {
    final track = app.playback.current;
    final theme = Theme.of(context);
    final layout = app.playerLayouts.active ?? playerTemplate();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PlayerLayoutEditor(
          app: app,
          initial: layout,
          theme: theme,
          track: track,
          lyrics: track == null ? null : app.loadLyrics(track),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      app,
      app.appearance,
      app.playback,
      app.playerLayouts,
      app.apiSettings,
    ]),
    builder: (context, _) {
      final destination = widget._destination;
      return Scaffold(
        appBar: AppBar(title: Text(destination?.title ?? '设置')),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: destination == _Destination.icon
                  ? LauncherIconPicker(apiSettings: app.apiSettings)
                  : ListView(
                      key: PageStorageKey(destination ?? 'settings'),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: _pageContent(destination),
                    ),
            ),
          ),
        ),
      );
    },
  );

  List<Widget> _pageContent(_Destination? destination) => switch (destination) {
    null => _directory(),
    _Destination.library => _libraryCards(),
    _Destination.playback => _playbackCards(),
    _Destination.lyrics => _lyricCards(),
    _Destination.theme => _themeCards(),
    _Destination.player => _playerAppearanceCards(),
    _Destination.cache => _cacheCards(),
    _Destination.onlineServices => _onlineServiceCards(),
    _Destination.onlineLyrics => [_onlineLyricsCard()],
    _Destination.llmConnection => [_llmConnectionCard()],
    _Destination.diagnostics => _diagnosticCards(),
    _ => throw StateError('No settings content for $destination'),
  };

  List<Widget> _themeCards() => [
    if (UiStyleAvailability.miuixAvailable)
      _group('界面风格 · 实验性', [
        for (final style in UiStyle.values)
          ListTile(
            leading: Icon(
              style == UiStyle.material3
                  ? Icons.widgets_outlined
                  : Icons.auto_awesome_outlined,
            ),
            title: Text(style == UiStyle.material3 ? 'Material 3' : 'Miuix'),
            subtitle: Text(
              style == UiStyle.material3 ? '经典界面 · 默认' : 'HyperOS 风格 · 实验性',
            ),
            trailing: app.appearance.uiStyle == style
                ? const Icon(
                    Icons.check_circle,
                    key: ValueKey('ui-style-selected'),
                  )
                : null,
            onTap: () => _act(() => app.appearance.setUiStyle(style)),
          ),
        if (app.appearance.uiStyle == UiStyle.miuix)
          ListTile(
            title: const Text('Miuix 组件预览'),
            subtitle: const Text('查看真实的 HyperOS 风格卡片、设置项与动画'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MiuixSettingsPreviewPage(),
              ),
            ),
          ),
      ]),
    SettingsGroup(
      title: '主题与配色',
      children: [
        SettingsSelect<ThemeMode>(
          title: '外观模式',
          icon: Icons.palette_outlined,
          value: app.appearance.mode,
          labels: const {
            ThemeMode.system: '跟随系统',
            ThemeMode.light: '浅色',
            ThemeMode.dark: '深色',
          },
          onChanged: (value) => _act(() => app.appearance.update(theme: value)),
        ),
        ListTile(
          title: const Text('主题颜色'),
          subtitle: Text(app.appearance.seedHex),
          leading: CircleAvatar(
            backgroundColor: app.appearance.seed,
            radius: 12,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _chooseThemeColor,
        ),
      ],
    ),
    _group('页面背景', [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text('主题颜色对所有页面生效；背景图片显示在首页、音乐库、歌单和我的页面。'),
      ),
      ..._backgroundControls(),
    ]),
  ];

  List<Widget> _backgroundControls() => [
    SwitchListTile(
      secondary: const Icon(Icons.format_color_fill_outlined),
      title: const Text('纯色底色'),
      subtitle: const Text('浅色纯白、深色炭灰；关闭后使用背景图片或主题底色'),
      value: app.appearance.solidBackground,
      onChanged: (v) => _act(() => app.appearance.update(solid: v)),
    ),
    ListTile(
      title: const Text('自定义背景图'),
      subtitle: Text(
        app.appearance.backgroundFile == null
            ? '选择背景图片'
            : app.appearance.solidBackground
            ? '已选择 · 关闭纯色背景后显示'
            : '已设置背景图片',
      ),
      leading: const Icon(Icons.wallpaper_outlined),
      trailing: app.appearance.backgroundFile == null
          ? const Icon(Icons.chevron_right)
          : IconButton(
              tooltip: '移除背景',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _act(app.appearance.clearBackground),
            ),
      onTap: () => _act(app.appearance.pickBackground),
    ),
    if (app.appearance.backgroundFile != null &&
        !app.appearance.solidBackground)
      SettingsSlider(
        title: '背景可见度',
        formatValue: (value) => '${(value * 100).round()}%',
        min: .1,
        max: .4,
        divisions: 30,
        value: app.appearance.backgroundVisibility,
        onChanged: (value) =>
            _act(() => app.appearance.update(visibility: value)),
      ),
  ];

  List<Widget> _playerAppearanceCards() => [
    SettingsGroup(
      title: '播放页面',
      children: [
        ListTile(
          key: const ValueKey('edit-player-layout'),
          leading: const Icon(Icons.dashboard_customize_outlined),
          title: Text(_Destination.playerEditor.title),
          subtitle: Text('当前布局：${app.playerLayouts.active?.name ?? '系统默认'}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(_Destination.playerEditor),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text('在编辑器中逐个调整组件，包括圆角、黑胶、沉浸封面，以及渐隐和羽化。'),
        ),
        SwitchListTile(
          title: const Text('封面模糊背景'),
          subtitle: const Text('用当前专辑封面营造全屏播放页的背景'),
          value: app.appearance.ambient,
          onChanged: (v) => _act(() => app.appearance.update(background: v)),
        ),
      ],
    ),
    SettingsGroup(
      title: '迷你播放器',
      children: [
        SettingsSelect<bool>(
          title: '默认播放器样式',
          value: app.appearance.playerFab,
          labels: const {false: '底部横条', true: '悬浮按钮'},
          onChanged: (value) =>
              _act(() => app.appearance.update(playerFab: value)),
        ),
        SwitchListTile(
          title: const Text('磨砂迷你播放器'),
          subtitle: const Text('为播放控件添加模糊质感'),
          value: app.appearance.glass,
          onChanged: (v) => _act(() => app.appearance.update(frost: v)),
        ),
        SettingsSelect<MiniPlayerBarStyle>(
          key: const ValueKey('mini-player-bar-style'),
          title: '横条样式',
          description: '调整底部播放器在不同屏幕下的外观',
          value: app.appearance.miniPlayerBarStyle,
          labels: const {
            MiniPlayerBarStyle.automatic: '自动',
            MiniPlayerBarStyle.pc: 'PC 横条',
            MiniPlayerBarStyle.standard: '普通横条',
          },
          onChanged: (value) =>
              _act(() => app.appearance.update(miniPlayerBarStyle: value)),
        ),
      ],
    ),
  ];

  Widget _entry(_SettingEntry entry, String detail) => ListTile(
    leading: SylphyMiuixStyle.enabled(context)
        ? SizedBox(
            width: 28,
            child: Icon(
              entry.icon,
              size: 24,
              color: MiuixTheme.of(context).colors.primary,
            ),
          )
        : Icon(entry.icon, color: Theme.of(context).colorScheme.primary),
    title: Text(entry.title),
    subtitle: Text(detail),
    trailing: const Icon(Icons.chevron_right),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    onTap: () => _open(entry.destination),
  );

  Widget _serviceEntry(
    _Destination destination,
    IconData icon,
    String summary,
  ) => ListTile(
    leading: Icon(icon),
    title: Text(destination.title),
    subtitle: Text(summary),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => _open(destination),
  );

  Widget _onlineLyricsEntry() => _serviceEntry(
    _Destination.onlineLyrics,
    Icons.cloud_outlined,
    app.apiSettings.lrcApiEnabled ? '已开启自动补充' : '已关闭自动补充',
  );

  Future<void> _testLlmConnection() async {
    if (_llmTestRunning) return;
    setState(() => _llmTestRunning = true);
    final future = app.recommendations.checkLlmConnection();
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => FutureBuilder<LlmConnectionTestResult>(
          future: future,
          builder: (context, snapshot) {
            final result = snapshot.data;
            final waiting = snapshot.connectionState != ConnectionState.done;
            Widget detail(String title, String value) => Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  SelectableText(value),
                ],
              ),
            );
            return AlertDialog(
              title: Text(waiting ? '正在测试 LLM 连接' : 'LLM 连接测试结果'),
              content: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (waiting) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 16),
                        const Text('正在发送合成歌曲元数据并验证模型输出，请稍候…'),
                      ] else if (result != null) ...[
                        Text(result.success ? '连接成功，已验证推荐 JSON 输出。' : '测试失败'),
                        const SizedBox(height: 8),
                        Text('HTTP 状态：${result.statusCode ?? "未收到响应"}'),
                        Text(
                          '耗时：${(result.elapsed.inMilliseconds / 1000).toStringAsFixed(2)} 秒',
                        ),
                        if (result.error.isNotEmpty)
                          detail('具体错误', result.error),
                        if (result.modelContent.isNotEmpty)
                          detail('模型响应内容', result.modelContent),
                        detail(
                          '服务响应正文',
                          result.responseBody.isEmpty
                              ? '未收到响应正文'
                              : result.responseBody,
                        ),
                      ] else
                        const Text('测试未能完成，请重试。'),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      // Closing the dialog does not start another request while this one runs.
      await future;
      if (mounted) setState(() => _llmTestRunning = false);
    }
  }

  List<Widget> _onlineServiceCards() => [
    _group('每日一言', [
      ListTile(
        key: const ValueKey('api-quote'),
        leading: const Icon(Icons.format_quote_rounded),
        title: const Text('每日一言 API'),
        subtitle: Text(app.apiSettings.quoteUrl),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => _editApiUrl(quote: true),
      ),
    ]),
    _group('GitHub 加速', [
      ListTile(
        key: const ValueKey('api-github-mirror'),
        leading: const Icon(Icons.cloud_download_outlined),
        title: const Text('GitHub 加速 API'),
        subtitle: Text(app.apiSettings.githubMirror),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => _editApiUrl(quote: false),
      ),
    ]),
    _group('在线歌词', [_onlineLyricsEntry()]),
    _group('LLM 模型', [
      _serviceEntry(
        _Destination.llmConnection,
        Icons.hub_outlined,
        app.apiSettings.llmModel,
      ),
    ]),
  ];

  Widget _onlineLyricsCard() => _group('自动补充歌词', [
    SwitchListTile(
      key: const ValueKey('api-lrc-enabled'),
      secondary: const Icon(Icons.lyrics_outlined),
      title: const Text('补充在线歌词'),
      subtitle: const Text('自动补充缺失的歌词'),
      value: app.apiSettings.lrcApiEnabled,
      onChanged: (value) => _act(() async {
        if (value &&
            !await _confirm('开启后，将歌曲名称、艺术家和专辑发送到歌词服务，以查找缺失的歌词。是否开启？')) {
          return;
        }
        await app.apiSettings.setLrcApiEnabled(value);
      }),
    ),
    ListTile(
      key: const ValueKey('api-lrc-url'),
      leading: const Icon(Icons.link_outlined),
      title: const Text('歌词服务地址'),
      subtitle: Text(app.apiSettings.lrcApiUrl),
      trailing: const Icon(Icons.edit_outlined),
      onTap: _editLrcApiUrl,
    ),
    ListTile(
      key: const ValueKey('api-lrc-auth'),
      leading: const Icon(Icons.key_outlined),
      title: const Text('歌词服务密钥'),
      subtitle: const Text('可选'),
      trailing: const Icon(Icons.edit_outlined),
      onTap: _editLrcApiToken,
    ),
  ]);

  Widget _llmConnectionCard() => _group('接口配置', [
    ListTile(
      key: const ValueKey('api-llm-url'),
      leading: const Icon(Icons.link_outlined),
      title: const Text('LLM 接口地址'),
      subtitle: Text(app.apiSettings.llmUrl),
      trailing: const Icon(Icons.edit_outlined),
      onTap: _editLlmUrl,
    ),
    ListTile(
      key: const ValueKey('api-llm-model'),
      leading: const Icon(Icons.psychology_outlined),
      title: const Text('LLM 模型'),
      subtitle: Text(app.apiSettings.llmModel),
      trailing: const Icon(Icons.edit_outlined),
      onTap: _editLlmModel,
    ),
    ListTile(
      key: const ValueKey('api-llm-token'),
      leading: const Icon(Icons.key_outlined),
      title: const Text('LLM API Key'),
      subtitle: const Text('保存在系统安全存储；留空清除'),
      trailing: const Icon(Icons.edit_outlined),
      onTap: _editLlmToken,
    ),
    ListTile(
      key: const ValueKey('api-llm-test'),
      leading: const Icon(Icons.network_check_outlined),
      title: Text(_llmTestRunning ? '正在测试 LLM 连接…' : '测试 LLM 连接'),
      subtitle: const Text('仅发送合成歌曲元数据，不会开启增强推荐；可能产生少量 API 用量'),
      trailing: const Icon(Icons.chevron_right),
      onTap: _llmTestRunning ? null : _testLlmConnection,
    ),
  ]);

  List<Widget> _lyricCards() => [
    _group('歌词页面', [
      SettingsSlider(
        icon: Icons.lyrics_outlined,
        title: '完整歌词字号',
        formatValue: Appearance.lyricFontLabel,
        value: app.appearance.lyricFontSize,
        min: Appearance.lyricFontSizes.first,
        max: Appearance.lyricFontSizes.last,
        divisions: Appearance.lyricFontSizes.length - 1,
        onChanged: (size) => _act(() => app.appearance.update(lyricFont: size)),
      ),
      SettingsSelect<LyricColorMode>(
        icon: Icons.palette_outlined,
        title: '歌词取色',
        description: '决定当前歌词行的高亮颜色',
        value: app.appearance.lyricPageColorMode,
        labels: const {
          LyricColorMode.album: '专辑取色',
          LyricColorMode.system: '跟随系统',
          LyricColorMode.fixed: '固定颜色',
        },
        onChanged: (value) =>
            _act(() => app.appearance.update(lyricPageColorMode: value)),
      ),
      if (app.appearance.lyricPageColorMode == LyricColorMode.fixed)
        ListTile(
          leading: CircleAvatar(
            radius: 12,
            backgroundColor: app.appearance.lyricPageFixedColor,
          ),
          title: const Text('选择歌词颜色'),
          onTap: () => _pickLyricsColor(desktop: false),
          trailing: const Icon(Icons.chevron_right),
        ),
    ]),
    _group('播放页迷你歌词', [
      SettingsSlider(
        icon: Icons.text_fields_rounded,
        title: '迷你歌词字号',
        formatValue: Appearance.miniLyricFontLabel,
        value: app.appearance.miniLyricFontSize,
        min: Appearance.miniLyricFontSizes.first,
        max: Appearance.miniLyricFontSizes.last,
        divisions: Appearance.miniLyricFontSizes.length - 1,
        onChanged: (size) =>
            _act(() => app.appearance.update(miniLyricFont: size)),
      ),
    ]),
    if (app.desktopLyrics.supported)
      _group('桌面歌词', [
        SwitchListTile(
          secondary: const Icon(Icons.picture_in_picture_alt_outlined),
          title: const Text('显示桌面歌词'),
          subtitle: Text(
            Platform.isWindows ? '置顶显示歌词，可拖动调整位置，点击右侧 × 关闭' : '在其他应用上方显示歌词',
          ),
          value: app.appearance.desktopLyricsEnabled,
          onChanged: (value) => _act(() async {
            final enabled = await app.desktopLyrics.setEnabled(value);
            if (value && !enabled && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请在系统设置中授权悬浮窗，返回后将自动开启')),
              );
            }
          }),
        ),
        SettingsSelect<LyricColorMode>(
          icon: Icons.format_color_text,
          title: '桌面歌词取色',
          value: app.appearance.desktopLyricColorMode,
          labels: const {
            LyricColorMode.system: '跟随系统',
            LyricColorMode.fixed: '固定颜色',
          },
          onChanged: (value) =>
              _act(() => app.appearance.update(desktopLyricColorMode: value)),
        ),
        SettingsSlider(
          title: '桌面歌词大小',
          formatValue: (value) => '${value.round()}',
          min: 12,
          max: 40,
          divisions: 14,
          value: app.appearance.desktopLyricFontSize,
          onChanged: (value) =>
              _act(() => app.appearance.update(desktopLyricFontSize: value)),
        ),
        if (app.appearance.desktopLyricColorMode == LyricColorMode.fixed)
          ListTile(
            leading: CircleAvatar(
              radius: 12,
              backgroundColor: app.appearance.desktopLyricFixedColor,
            ),
            title: const Text('选择桌面歌词颜色'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickLyricsColor(desktop: true),
          ),
      ]),
    _group('在线补充', [_onlineLyricsEntry()]),
  ];

  Future<void> _pickLyricsColor({required bool desktop}) async {
    final initial = desktop
        ? app.appearance.desktopLyricFixedColor
        : app.appearance.lyricPageFixedColor;
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => ThemeColorDialog(initial: initial),
    );
    if (picked == null || !mounted) return;
    await _act(
      () => desktop
          ? app.appearance.update(desktopLyricFixedColor: picked)
          : app.appearance.update(lyricPageFixedColor: picked),
    );
  }

  List<Widget> _directory() {
    final query = _searchController.text.trim().toLowerCase();
    final clearButton = _searchController.text.isEmpty
        ? null
        : IconButton(
            tooltip: '清空搜索',
            icon: const Icon(Icons.clear),
            onPressed: () => setState(_searchController.clear),
          );
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          decoration: SylphyMiuixStyle.enabled(context)
              ? SylphyMiuixStyle.searchDecoration(
                  context,
                  hintText: '搜索设置',
                  suffixIcon: clearButton,
                )
              : InputDecoration(
                  labelText: '搜索设置',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: clearButton,
                ),
        ),
      ),
      if (query.isEmpty)
        for (final group in _settingsGroups)
          SettingsGroup(
            title: group.title,
            children: [
              for (final entry in group.entries)
                if (entry.available) _entry(entry, entry.summary),
            ],
          )
      else
        _searchResults(query),
    ];
  }

  Widget _searchResults(String query) {
    final terms = query
        .split(RegExp(r'[\s、，,]+'))
        .where((term) => term.isNotEmpty)
        .toList();
    final results = <({_SettingEntry entry, String path, int rank})>[];

    void addMatches(List<_SettingEntry> entries, String path) {
      for (final entry in entries) {
        if (!entry.available) continue;
        final rank = entry.match(terms);
        if (rank > 0) results.add((entry: entry, path: path, rank: rank));
        addMatches(entry.children, '$path → ${entry.title}');
      }
    }

    if (terms.isNotEmpty) {
      for (final group in _settingsGroups) {
        addMatches(group.entries, group.title);
      }
    }
    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('没有找到匹配的设置，试试其他关键词。'),
      );
    }
    return SettingsGroup(
      children: [
        for (final rank in [4, 3, 2, 1])
          for (final result in results)
            if (result.rank == rank) _entry(result.entry, result.path),
      ],
    );
  }

  List<Widget> _libraryCards() => [
    _group('音乐库显示', [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text('选择音乐库显示的分类，至少保留一项。隐藏分类不会删除音乐。'),
      ),
      for (var category = 0; category < 4; category++)
        SwitchListTile(
          title: Text(Appearance.libraryCategoryNames[category]),
          secondary: Icon(Appearance.libraryCategoryIcons[category]),
          value: app.appearance.libraryCategories.contains(category),
          onChanged:
              app.appearance.libraryCategories.length == 1 &&
                  app.appearance.libraryCategories.contains(category)
              ? null
              : (enabled) => _act(
                  () => app.appearance.setLibraryCategory(category, enabled),
                ),
        ),
    ]),
    _group('自动同步', [
      SettingsSelect<int>(
        title: '自动同步间隔',
        description: '在前台自动更新音乐库',
        value: app.autoSyncMinutes,
        labels: const {
          0: '关闭',
          5: '5 分钟',
          15: '15 分钟',
          30: '30 分钟',
          60: '1 小时',
          360: '6 小时',
          1440: '24 小时',
        },
        onChanged: (value) => _act(() => app.setAutoSyncMinutes(value)),
      ),
      if (_isAndroid ||
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows))
        SwitchListTile(
          title: const Text('同步完成通知'),
          subtitle: const Text('同步完成时通知我'),
          value: app.autoSyncNotice,
          onChanged: (v) => _act(() => app.setAutoSyncNotice(v)),
        ),
    ]),
    _group('收藏偏好', [
      SettingsSelect<bool>(
        title: '默认收藏位置',
        description: '云端收藏会保存到歌曲所属的服务器',
        value: app.cloudFavoritesByDefault,
        labels: const {false: '本地', true: '云端'},
        onChanged: (value) => _act(() async {
          if (value &&
              !await _confirm(
                '云端收藏会更新歌曲所属服务器账号的收藏；支持 Emby、Navidrome 和 OpenSubsonic，其他来源仍保存到本地。是否使用云端收藏？',
              )) {
            return;
          }
          await app.setCloudFavoritesByDefault(value);
        }),
      ),
    ]),
  ];

  List<Widget> _playbackCards() => [
    _group('音量与速度', [
      SettingsSlider(
        title: '应用内音量',
        formatValue: (value) => '${value.round()}%',
        min: 0,
        max: 100,
        value: app.playback.volume,
        onChanged: (v) => _act(() => app.playback.setVolume(v)),
      ),
      SettingsSlider(
        title: '播放速度',
        formatValue: (value) => '${value.toStringAsFixed(2)}×',
        min: .5,
        max: 2,
        divisions: 30,
        value: app.playback.speed,
        onChanged: (v) => _act(() => app.playback.setSpeed(v)),
      ),
    ]),
    _group('声音处理', [
      SettingsSelect<String>(
        title: '响度均衡',
        description: '减小不同歌曲之间的音量差异',
        value: app.playback.replayGain,
        labels: const {'no': '关闭', 'track': '按曲目', 'album': '按专辑'},
        onChanged: (value) => _act(() => app.playback.setReplayGain(value)),
      ),
      if (_isAndroid)
        SwitchListTile(
          title: const Text('De-click 平滑跳转（实验）'),
          subtitle: const Text('减少播放开始和跳转时的突兀声音；跳转可能稍有延迟'),
          value: app.playback.deClickEnabled,
          onChanged: (enabled) => _act(() => app.playback.setDeClick(enabled)),
        ),
    ]),
  ];

  List<Widget> _cacheCards() => [
    SettingsCacheOverview(
      app: app,
      onManage: () => _open(_Destination.cacheStorage),
      onTasks: () => _open(_Destination.downloads),
      onLimit: _changeBudget,
      onClearAll: () async {
        if (await _confirm('清理音频、封面和远程歌词，并取消相关下载任务？手动歌词和原始音乐将保留。') && mounted) {
          await _act(app.clearCache);
        }
      },
    ),
  ];

  List<Widget> _diagnosticCards() => [
    SettingsGroup(
      children: [
        SwitchListTile(
          key: const ValueKey('diagnostics-toggle'),
          secondary: const Icon(Icons.bug_report_outlined),
          title: const Text('记录诊断日志'),
          subtitle: const Text('记录播放问题，便于排查'),
          value: app.diagnostics.enabled,
          onChanged: (v) => _act(() => app.setDiagnosticLogging(v)),
        ),
        ListTile(
          key: const ValueKey('diagnostics-export'),
          leading: const Icon(Icons.save_alt),
          title: const Text('导出诊断日志'),
          subtitle: const Text('保存到文件'),
          onTap: () => _act(_exportDiagnosticLogs),
        ),
        ListTile(
          key: const ValueKey('diagnostics-share'),
          leading: const Icon(Icons.share_outlined),
          title: const Text('分享诊断日志'),
          subtitle: Text(Platform.isLinux ? '保存到文件' : '通过系统分享'),
          onTap: () => _act(_shareDiagnosticLogs),
        ),
        ListTile(
          key: const ValueKey('diagnostics-clear'),
          leading: const Icon(Icons.delete_outline),
          title: const Text('清除诊断日志'),
          onTap: () async {
            if (await _confirm('确认删除全部已记录的诊断日志？')) {
              await _act(app.clearDiagnosticLogs);
            }
          },
        ),
      ],
    ),
  ];

  SettingsGroup _group(String title, List<Widget> children) =>
      SettingsGroup(title: title, children: children);

  Future<void> _editApiUrl({required bool quote}) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _ApiValueDialog(
        title: quote ? '每日一言 API' : 'GitHub 加速 API',
        initial: quote
            ? app.apiSettings.quoteUrl
            : app.apiSettings.githubMirror,
        label: 'HTTPS URL',
        helper: quote
            ? '返回 hitokoto/text/content 字段的 JSON'
            : '例如 https://hub.wgen.top/ （GitHub URL 前缀）',
      ),
    );
    if (value == null || !mounted) return;
    await _act(
      () => quote
          ? app.apiSettings.setQuoteUrl(value)
          : app.apiSettings.setGitHubMirror(value),
    );
  }

  Future<void> _editLrcApiUrl() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _ApiValueDialog(
        title: 'LrcApi 接口地址',
        initial: app.apiSettings.lrcApiUrl,
        label: 'HTTP(S) URL',
        helper:
            '公开接口默认 https://api.lrc.cx/lyrics；自部署可填写服务根地址、/lyrics 或 /jsonapi',
      ),
    );
    if (value != null && mounted) {
      await _act(() => app.apiSettings.setLrcApiUrl(value));
    }
  }

  Future<void> _editLrcApiToken() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => const _ApiValueDialog(
        title: 'LrcApi 鉴权密钥',
        label: '鉴权密钥（可选）',
        helper: '保存空值会清除已保存的密钥',
        secret: true,
      ),
    );
    if (value == null || !mounted) return;
    await _act(() async {
      if (value.trim().isEmpty) {
        await app.vault.delete('lrcapi');
      } else {
        await app.vault.write('lrcapi', 'token', value.trim());
      }
    });
  }

  Future<void> _editLlmUrl() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _ApiValueDialog(
        title: 'LLM Chat Completions 地址',
        label: 'HTTP(S) URL',
        helper: '例如 https://api.openai.com/v1/chat/completions；本机回环允许 HTTP',
        initial: app.apiSettings.llmUrl,
      ),
    );
    if (value != null && mounted) {
      await _act(() => app.apiSettings.setLlmUrl(value));
    }
  }

  Future<void> _editLlmModel() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _ApiValueDialog(
        title: 'LLM 模型名称',
        label: '模型 ID',
        helper: '填服务提供商支持的模型名称',
        initial: app.apiSettings.llmModel,
      ),
    );
    if (value != null && mounted) {
      await _act(() => app.apiSettings.setLlmModel(value));
    }
  }

  Future<void> _editLlmToken() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => const _ApiValueDialog(
        title: 'LLM API Key',
        label: '密钥（可选，本地模型可留空）',
        helper: '保存空值会清除旧密钥，界面不回显已保存的密钥',
        secret: true,
      ),
    );
    if (value == null || !mounted) return;
    await _act(() async {
      if (value.trim().isEmpty) {
        await app.vault.delete('llm');
      } else {
        await app.vault.write('llm', 'token', value.trim());
      }
      await app.apiSettings.llmCredentialChanged();
    });
  }

  Future<void> _chooseThemeColor() async {
    final chosen = await showDialog<Color>(
      context: context,
      builder: (_) => ThemeColorDialog(initial: app.appearance.seed),
    );
    if (chosen != null) await _act(() => app.appearance.update(color: chosen));
  }

  Future<void> _exportDiagnosticLogs() async {
    final bytes = await app.diagnostics.exportBytes();
    final saved = await FilePicker.saveFile(
      dialogTitle: '导出诊断日志',
      fileName: app.diagnostics.exportFileName,
      bytes: bytes,
      mimeType: 'text/plain',
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('诊断日志已导出')));
    }
  }

  Future<void> _shareDiagnosticLogs() async {
    // share_plus does not support file sharing on Linux.
    if (Platform.isLinux) {
      await _exportDiagnosticLogs();
      return;
    }
    final bytes = await app.diagnostics.exportBytes();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'text/plain')],
        fileNameOverrides: [app.diagnostics.exportFileName],
        title: 'SylphyMusic 诊断日志',
      ),
    );
  }

  Future<void> _changeBudget() async {
    var amount = '${(app.cache.maxBytes / 1073741824).round()}';
    final form = GlobalKey<FormState>();
    final answer = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('缓存上限（GiB）'),
        content: Form(
          key: form,
          child: TextFormField(
            initialValue: amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(helperText: '可设置 1–200 GiB'),
            onChanged: (value) => amount = value,
            validator: (value) {
              final n = int.tryParse(value ?? '');
              return n == null || n < 1 || n > 200 ? '请输入 1–200 的整数' : null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(ctx, int.parse(amount));
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (answer != null) {
      await _act(() async {
        app.cache.maxBytes = answer * 1073741824;
        await app.db.setSetting('cache_limit', '${app.cache.maxBytes}');
        await app.cache.enforceQuota();
      });
    }
  }

  Future<bool> _confirm(String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('请确认'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;
}

/// Own the controller until the dialog's reverse transition has unmounted it.
class _ApiValueDialog extends StatefulWidget {
  const _ApiValueDialog({
    required this.title,
    required this.label,
    required this.helper,
    this.initial = '',
    this.secret = false,
  });
  final String title, label, helper, initial;
  final bool secret;
  @override
  State<_ApiValueDialog> createState() => _ApiValueDialogState();
}

class _ApiValueDialogState extends State<_ApiValueDialog> {
  late final controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: controller,
      obscureText: widget.secret,
      keyboardType: widget.secret ? TextInputType.text : TextInputType.url,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        helperMaxLines: 3,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: const Text('保存'),
      ),
    ],
  );
}

/// Editable recommendation guidance; candidate and output contracts stay fixed.
