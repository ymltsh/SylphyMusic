import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_controller.dart';
import '../services/llm_recommendations.dart';
import '../services/api_settings.dart';
import '../core/appearance.dart';
import '../core/player_layout.dart';
import 'cache_storage.dart';
import 'app_update_page.dart';
import 'launcher_icon_picker.dart';
import 'cache_tasks.dart';
import 'theme_color_dialog.dart';
import 'player_layout/layout_editor.dart';
import 'about_page.dart';
import 'recommendation_settings_page.dart';

enum _Section {
  playback,
  sync,
  lyrics,
  theme,
  background,
  player,
  icon,
  cache,
  api,
  diagnostics,
  about,
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.app, required this.onSources})
    : _section = null;
  const SettingsPage._({
    required this.app,
    required this.onSources,
    required this._section,
  });
  final SylphyApp app;
  final VoidCallback onSources;
  final _Section? _section;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SylphyApp get app => widget.app;
  bool _llmTestRunning = false;
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

  Future<void> _open(_Section section) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => section == _Section.about
            ? const AboutPage()
            : SettingsPage._(
                app: app,
                onSources: widget.onSources,
                section: section,
              ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _downloads() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => CacheTasksPage(app: app)));

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
      app.apiSettings,
    ]),
    builder: (context, _) {
      final section = widget._section;
      final title = switch (section) {
        null => '设置',
        _Section.playback => '播放器设置',
        _Section.sync => '同步与收藏',
        _Section.lyrics => '歌词设置',
        _Section.theme => '主题与配色',
        _Section.background => '页面背景',
        _Section.player => '播放器外观',
        _Section.icon => '应用图标',
        _Section.cache => '下载与缓存',
        _Section.api => 'API 设置',
        _Section.diagnostics => '诊断与反馈',
        _Section.about => '关于风灵音乐',
      };
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: section == _Section.icon
                  ? const LauncherIconPicker()
                  : ListView(
                      key: PageStorageKey(section ?? 'settings'),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: section == null
                          ? _directory(context)
                          : section == _Section.lyrics
                          ? _lyricCards()
                          : section == _Section.player
                          ? _playerAppearanceCards()
                          : section == _Section.api
                          ? _apiCards()
                          : [
                              Card(
                                margin: EdgeInsets.zero,
                                clipBehavior: Clip.antiAlias,
                                child: Column(children: _controls(section)),
                              ),
                            ],
                    ),
            ),
          ),
        ),
      );
    },
  );

  List<Widget> _playerAppearanceCards() => [
    _group('播放页面', [
      ListTile(
        key: const ValueKey('edit-player-layout'),
        leading: const Icon(Icons.dashboard_customize_outlined),
        title: const Text('编辑播放页面'),
        subtitle: Text(
          '当前布局：${app.playerLayouts.active?.name ?? '系统默认'} · '
          '可移动、隐藏或删除组件',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _editPlayerLayout,
      ),
    ]),
    _group('迷你播放器', [
      ListTile(
        title: const Text('默认播放器样式'),
        subtitle: const Text('选择底部横条或悬浮按钮'),
        trailing: DropdownButton<bool>(
          value: app.appearance.playerFab,
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: false, child: Text('横条')),
            DropdownMenuItem(value: true, child: Text('悬浮按钮')),
          ],
          onChanged: (value) =>
              _act(() => app.appearance.update(playerFab: value)),
        ),
      ),
      SwitchListTile(
        title: const Text('磨砂迷你播放器'),
        subtitle: const Text('为底部播放控件添加模糊质感'),
        value: app.appearance.glass,
        onChanged: (v) => _act(() => app.appearance.update(frost: v)),
      ),
    ]),
    _group('全屏播放页', [
      SwitchListTile(
        title: const Text('唱片播放样式'),
        subtitle: const Text('将封面显示为黑胶唱片'),
        value: app.appearance.disc,
        onChanged: (v) => _act(() => app.appearance.update(record: v)),
      ),
      SwitchListTile(
        title: const Text('唱片旋转'),
        subtitle: const Text('播放时旋转黑胶唱片'),
        value: app.appearance.discRotation,
        onChanged: app.appearance.disc
            ? (v) => _act(() => app.appearance.update(rotateDisc: v))
            : null,
      ),
      SwitchListTile(
        title: const Text('封面模糊背景'),
        subtitle: const Text('在全屏播放页使用封面氛围背景'),
        value: app.appearance.ambient,
        onChanged: (v) => _act(() => app.appearance.update(background: v)),
      ),
    ]),
  ];

  Widget _entry(
    IconData icon,
    String title,
    String summary,
    _Section section,
  ) => ListTile(
    leading: _entryIcon(icon),
    title: Text(title),
    subtitle: Text(summary),
    trailing: const Icon(Icons.chevron_right),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    onTap: () => _open(section),
  );

  Widget _entryIcon(IconData icon) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(
      icon,
      color: Theme.of(context).colorScheme.onPrimaryContainer,
      size: 22,
    ),
  );

  Widget _group(String title, List<Widget> entries) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 10),
        child: Text(
          title,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 68, endIndent: 16),
              entries[i],
            ],
          ],
        ),
      ),
    ],
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

  List<Widget> _apiCards() => [
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
    _group('在线歌词', [
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
    ]),
    _group('LLM 推荐', [
      SwitchListTile(
        key: const ValueKey('api-llm-enabled'),
        secondary: const Icon(Icons.auto_awesome_outlined),
        title: const Text('LLM 增强推荐'),
        subtitle: const Text('可选：AI 参与每日精选和专辑排序，并生成推荐词'),
        value: app.apiSettings.llmEnabled,
        onChanged: (value) => _act(() async {
          if (value &&
              !await _confirm(
                '开启后，候选歌曲名称、歌手、专辑及有限的本机听歌统计会发送给你配置的 LLM 服务。不会发送音乐源地址、账号或音频文件；第三方接口可能收费。是否开启？',
              ))
            return;
          await app.apiSettings.setLlmEnabled(value);
        }),
      ),
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
        subtitle: const Text('仅使用合成歌曲元数据；可能产生少量 API 用量'),
        trailing: const Icon(Icons.chevron_right),
        onTap: app.apiSettings.llmEnabled && !_llmTestRunning
            ? _testLlmConnection
            : null,
      ),
      ListTile(
        key: const ValueKey('api-llm-mode'),
        leading: const Icon(Icons.tune_outlined),
        title: const Text('LLM 推荐参与方式'),
        subtitle: Text(
          app.apiSettings.llmMode == 'lead'
              ? '主导：在扩展候选中选歌、重排和撰写推荐词'
              : '辅助：保留本地候选，LLM 重排并撰写推荐词',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _editLlmMode,
      ),
      ListTile(
        key: const ValueKey('api-llm-user-prompt'),
        leading: const Icon(Icons.edit_note_rounded),
        title: const Text('自定义 Prompt'),
        subtitle: Text(
          app.apiSettings.llmUserPrompt,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.edit_outlined),
        onTap: _editLlmPrompts,
      ),
    ]),
  ];

  List<Widget> _lyricCards() => [
    _group('歌词页面', [
      _controls(_Section.lyrics)[0],
      ListTile(
        leading: const Icon(Icons.palette_outlined),
        title: const Text('歌词取色'),
        subtitle: const Text('高亮歌词颜色'),
        trailing: DropdownButton<LyricColorMode>(
          value: app.appearance.lyricPageColorMode,
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: LyricColorMode.album, child: Text('专辑取色')),
            DropdownMenuItem(value: LyricColorMode.system, child: Text('跟随系统')),
            DropdownMenuItem(value: LyricColorMode.fixed, child: Text('固定颜色')),
          ],
          onChanged: (value) =>
              _act(() => app.appearance.update(lyricPageColorMode: value)),
        ),
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
    _group('播放页迷你歌词', [_controls(_Section.lyrics)[1]]),
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
        ListTile(
          leading: const Icon(Icons.format_color_text),
          title: const Text('桌面歌词取色'),
          trailing: DropdownButton<LyricColorMode>(
            value: app.appearance.desktopLyricColorMode,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(
                value: LyricColorMode.system,
                child: Text('跟随系统'),
              ),
              DropdownMenuItem(
                value: LyricColorMode.fixed,
                child: Text('固定颜色'),
              ),
            ],
            onChanged: (value) =>
                _act(() => app.appearance.update(desktopLyricColorMode: value)),
          ),
        ),
        ListTile(
          title: const Text('桌面歌词大小'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${app.appearance.desktopLyricFontSize.round()}'),
              Slider(
                min: 12,
                max: 40,
                divisions: 14,
                value: app.appearance.desktopLyricFontSize,
                onChanged: (value) => _act(
                  () => app.appearance.update(desktopLyricFontSize: value),
                ),
              ),
            ],
          ),
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

  List<Widget> _directory(BuildContext context) => [
    _group('音乐与存储', [
      ListTile(
        leading: _entryIcon(Icons.dns_outlined),
        title: const Text('音乐源管理'),
        subtitle: const Text('管理已连接的音乐源'),
        trailing: const Icon(Icons.chevron_right),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: widget.onSources,
      ),
      _entry(Icons.sync_outlined, '同步与收藏', '自动同步与收藏偏好', _Section.sync),
      _entry(Icons.storage_outlined, '下载与缓存', '管理离线音乐与空间', _Section.cache),
    ]),
    _group('播放与阅读', [
      _entry(Icons.tune_rounded, '播放器设置', '音量、播放速度与音效', _Section.playback),
      _entry(Icons.lyrics_outlined, '歌词设置', '调整歌词显示效果', _Section.lyrics),
    ]),
    _group('外观与个性化', [
      ListTile(
        leading: _entryIcon(Icons.auto_awesome_outlined),
        title: const Text('推荐设置'),
        subtitle: const Text('个性化、在线热度与收听统计'),
        trailing: const Icon(Icons.chevron_right),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => RecommendationSettingsPage(app: app),
          ),
        ),
      ),
      _entry(Icons.palette_outlined, '主题与配色', '打造你喜欢的色彩', _Section.theme),
      _entry(Icons.wallpaper_outlined, '页面背景', '自定义页面背景', _Section.background),
      _entry(Icons.album_outlined, '播放器外观', '编辑播放页、唱片与迷你播放器', _Section.player),
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        _entry(Icons.apps_outlined, '应用图标', '选择你喜欢的图标', _Section.icon),
    ]),
    _group('网络与接口', [
      _entry(Icons.api_outlined, 'API 设置', '管理在线服务', _Section.api),
    ]),
    _group('应用与支持', [
      ListTile(
        leading: _entryIcon(Icons.system_update_alt),
        title: const Text('检查更新'),
        subtitle: const Text('查看新版本与更新内容'),
        trailing: const Icon(Icons.chevron_right),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => AppUpdatePage(
              onCheck: app.checkForUpdates,
              mirror: app.apiSettings.githubMirror,
            ),
          ),
        ),
      ),
      _entry(
        Icons.bug_report_outlined,
        '诊断与反馈',
        '日志与问题反馈',
        _Section.diagnostics,
      ),
      _entry(
        Icons.info_outline_rounded,
        '关于风灵音乐',
        '应用信息与开源许可证',
        _Section.about,
      ),
    ]),
  ];

  List<Widget> _controls(_Section section) => switch (section) {
    _Section.sync => [
      ListTile(
        title: const Text('自动同步间隔'),
        subtitle: const Text('在前台自动更新音乐库'),
        trailing: DropdownButton<int>(
          value: app.autoSyncMinutes,
          items: const [
            DropdownMenuItem(value: 0, child: Text('关闭')),
            DropdownMenuItem(value: 5, child: Text('5 分钟')),
            DropdownMenuItem(value: 15, child: Text('15 分钟')),
            DropdownMenuItem(value: 30, child: Text('30 分钟')),
            DropdownMenuItem(value: 60, child: Text('1 小时')),
            DropdownMenuItem(value: 360, child: Text('6 小时')),
            DropdownMenuItem(value: 1440, child: Text('24 小时')),
          ],
          onChanged: (v) {
            if (v != null) _act(() => app.setAutoSyncMinutes(v));
          },
        ),
      ),
      SwitchListTile(
        title: const Text('同步完成通知'),
        subtitle: const Text('同步完成时通知我'),
        value: app.autoSyncNotice,
        onChanged: (v) => _act(() => app.setAutoSyncNotice(v)),
      ),
      ListTile(
        title: const Text('默认收藏位置'),
        subtitle: const Text('云端收藏自动跟随歌曲来源'),
        trailing: DropdownButton<bool>(
          value: app.cloudFavoritesByDefault,
          items: const [
            DropdownMenuItem(value: false, child: Text('本地')),
            DropdownMenuItem(value: true, child: Text('云端')),
          ],
          onChanged: (v) {
            if (v == null) return;
            _act(() async {
              if (v &&
                  !await _confirm(
                    '云端收藏会更新歌曲所属服务器账号的收藏；支持 Emby、Navidrome 和 OpenSubsonic，其他来源仍保存到本地。是否使用云端收藏？',
                  )) {
                return;
              }
              await app.setCloudFavoritesByDefault(v);
            });
          },
        ),
      ),
    ],
    _Section.playback => [
      ListTile(
        title: const Text('播放速度'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${app.playback.speed.toStringAsFixed(2)}×'),
            Slider(
              min: .5,
              max: 2,
              divisions: 30,
              value: app.playback.speed,
              onChanged: (v) => _act(() => app.playback.setSpeed(v)),
            ),
          ],
        ),
      ),
      ListTile(
        title: const Text('响度均衡'),
        trailing: DropdownButton<String>(
          value: app.playback.replayGain,
          underline: const SizedBox(),
          onChanged: (v) {
            if (v != null) _act(() => app.playback.setReplayGain(v));
          },
          items: const [
            DropdownMenuItem(value: 'no', child: Text('关闭')),
            DropdownMenuItem(value: 'track', child: Text('按曲目')),
            DropdownMenuItem(value: 'album', child: Text('按专辑')),
          ],
        ),
      ),
      ListTile(
        title: const Text('应用内音量'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${app.playback.volume.round()}%'),
            Slider(
              min: 0,
              max: 100,
              value: app.playback.volume,
              onChanged: (v) => _act(() => app.playback.setVolume(v)),
            ),
          ],
        ),
      ),
    ],
    _Section.lyrics => [
      ListTile(
        leading: const Icon(Icons.lyrics_outlined),
        title: const Text('完整歌词字号'),
        subtitle: Text(Appearance.lyricFontLabel(app.appearance.lyricFontSize)),
        trailing: DropdownButton<double>(
          value: app.appearance.lyricFontSize,
          underline: const SizedBox(),
          items: [
            for (final size in Appearance.lyricFontSizes)
              DropdownMenuItem(
                value: size,
                child: Text(Appearance.lyricFontLabel(size)),
              ),
          ],
          onChanged: (v) => _act(() => _setLyricFont(v!)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.text_fields_rounded),
        title: const Text('迷你歌词字号'),
        subtitle: Text(
          Appearance.miniLyricFontLabel(app.appearance.miniLyricFontSize),
        ),
        trailing: DropdownButton<double>(
          value: app.appearance.miniLyricFontSize,
          underline: const SizedBox(),
          items: [
            for (final size in Appearance.miniLyricFontSizes)
              DropdownMenuItem(
                value: size,
                child: Text(Appearance.miniLyricFontLabel(size)),
              ),
          ],
          onChanged: (v) =>
              _act(() => app.appearance.update(miniLyricFont: v!)),
        ),
      ),
    ],
    _Section.theme => [
      ListTile(
        title: const Text('外观模式'),
        leading: const Icon(Icons.palette_outlined),
        trailing: DropdownButton<ThemeMode>(
          value: app.appearance.mode,
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
            DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
            DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
          ],
          onChanged: (v) => _act(() => app.appearance.update(theme: v)),
        ),
      ),
      ListTile(
        title: const Text('主题颜色'),
        subtitle: Text(app.appearance.seedHex),
        leading: CircleAvatar(backgroundColor: app.appearance.seed, radius: 12),
        trailing: const Icon(Icons.chevron_right),
        onTap: _chooseThemeColor,
      ),
    ],
    _Section.background => [
      SwitchListTile(
        title: const Text('纯色背景'),
        subtitle: const Text('使用简洁的纯色背景'),
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
        ListTile(
          title: const Text('背景可见度'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${(app.appearance.backgroundVisibility * 100).round()}%'),
              Slider(
                min: .1,
                max: .4,
                divisions: 30,
                value: app.appearance.backgroundVisibility,
                onChanged: (v) =>
                    _act(() => app.appearance.update(visibility: v)),
              ),
            ],
          ),
        ),
    ],
    _Section.player => [],
    _Section.icon => [const LauncherIconPicker()],
    _Section.cache => [
      ListTile(
        title: const Text('管理音乐缓存'),
        leading: const Icon(Icons.storage),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CacheStoragePage(app: app)),
        ),
      ),
      ListTile(
        title: const Text('清理所有缓存资源'),
        trailing: const Icon(Icons.delete_outline),
        onTap: () async {
          if (await _confirm('清理音频、封面和远程歌词，并取消相关下载任务？手动歌词和原始音乐将保留。')) {
            await _act(() => app.clearCache());
          }
        },
      ),
      ListTile(
        title: const Text('最大缓存空间'),
        subtitle: Text(
          '当前 ${(app.cache.maxBytes / 1073741824).toStringAsFixed(1)} GiB',
        ),
        trailing: const Icon(Icons.edit),
        onTap: _changeBudget,
      ),
      ListTile(
        title: const Text('下载任务'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _downloads,
      ),
    ],
    _Section.api => _apiCards(),
    _Section.diagnostics => [
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
    _Section.about => const [],
  };
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

  Future<void> _editLlmMode() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('LLM 推荐参与方式'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'assist'),
            child: const Text('辅助推荐 · 重排现有精选并撰写推荐词'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'lead'),
            child: const Text('主导推荐 · 从扩展候选中选择并撰写推荐词'),
          ),
        ],
      ),
    );
    if (value != null && mounted) {
      await _act(() => app.apiSettings.setLlmMode(value));
    }
  }

  Future<void> _editLlmPrompts() async {
    final value = await showDialog<({String system, String user})>(
      context: context,
      builder: (_) => _LlmPromptDialog(
        system: app.apiSettings.llmSystemPrompt,
        user: app.apiSettings.llmUserPrompt,
      ),
    );
    if (value == null || !mounted) return;
    await _act(
      () =>
          app.apiSettings.setLlmPrompts(system: value.system, user: value.user),
    );
  }

  Future<void> _chooseThemeColor() async {
    final chosen = await showDialog<Color>(
      context: context,
      builder: (_) => ThemeColorDialog(initial: app.appearance.seed),
    );
    if (chosen != null) await _act(() => app.appearance.update(color: chosen));
  }

  Future<void> _setLyricFont(double size) =>
      app.appearance.update(lyricFont: size);

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
class _LlmPromptDialog extends StatefulWidget {
  const _LlmPromptDialog({required this.system, required this.user});
  final String system;
  final String user;

  @override
  State<_LlmPromptDialog> createState() => _LlmPromptDialogState();
}

class _LlmPromptDialogState extends State<_LlmPromptDialog> {
  late final system = TextEditingController(text: widget.system);
  late final user = TextEditingController(text: widget.user);
  String? error;

  @override
  void dispose() {
    system.dispose();
    user.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final value = (
        system: ApiSettings.validateLlmSystemPrompt(system.text),
        user: ApiSettings.validateLlmUserPrompt(user.text),
      );
      Navigator.pop(context, value);
    } on FormatException catch (exception) {
      setState(() => error = exception.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('自定义 Prompt'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('可调整推荐角色、选曲侧重和文案风格。真实候选范围、禁止编造和 JSON 输出格式由应用固定。'),
            const SizedBox(height: 16),
            TextField(
              controller: system,
              minLines: 4,
              maxLines: 7,
              maxLength: 2000,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'System Prompt（推荐角色与策略）',
                helperText: '作为 System 指导发送，固定约束仍会追加；留空恢复默认。',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: user,
              minLines: 4,
              maxLines: 7,
              maxLength: 2000,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'User Prompt（个人偏好）',
                hintText: '例如：偏好华语独立音乐；文案带一点诗意。',
                helperText: '随候选数据发送；留空恢复默认。请勿填写密钥。',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text('保存后会重新生成推荐，可能产生 API 费用。'),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          system.text = ApiSettings.defaultLlmSystemPrompt;
          user.text = ApiSettings.defaultLlmUserPrompt;
          setState(() => error = null);
        },
        child: const Text('恢复默认'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存')),
    ],
  );
}
