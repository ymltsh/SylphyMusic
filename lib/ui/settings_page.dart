import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_controller.dart';
import '../core/appearance.dart';
import 'cache_storage.dart';
import 'app_update_page.dart';
import 'launcher_icon_picker.dart';
import 'cache_tasks.dart';
import 'theme_color_dialog.dart';
import 'about_page.dart';
import 'openlist_lite_settings.dart';

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
  String get _themeLabel => switch (app.appearance.mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
  };

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
              child: ListView(
                key: PageStorageKey(section ?? 'settings'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: section == null
                    ? _directory(context)
                    : section == _Section.lyrics
                    ? _lyricCards()
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
    if (!kIsWeb && Platform.isAndroid)
      _group('Android 桌面歌词（悬浮窗）', [
        SwitchListTile(
          secondary: const Icon(Icons.picture_in_picture_alt_outlined),
          title: const Text('显示桌面歌词'),
          subtitle: const Text('需授予悬浮窗权限；背景自动隐藏，触摸歌词后可拖动或点 × 关闭'),
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
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        ListTile(
          leading: _entryIcon(Icons.cloud_outlined),
          title: const Text('OpenList Lite · 网盘管理'),
          subtitle: const Text('内置 Web UI · 智能 / 持续运行'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const OpenListLiteSettingsPage(),
            ),
          ),
        ),
      ListTile(
        leading: _entryIcon(Icons.dns_outlined),
        title: const Text('音乐源管理'),
        subtitle: Text('${app.sources.length} 个来源 · 连接与同步'),
        trailing: const Icon(Icons.chevron_right),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: widget.onSources,
      ),
      _entry(
        Icons.sync_outlined,
        '同步与收藏',
        '${app.autoSyncMinutes == 0 ? '不自动同步' : '每 ${app.autoSyncMinutes} 分钟同步'} · 默认${app.cloudFavoritesByDefault ? '云端' : '本地'}收藏',
        _Section.sync,
      ),
      _entry(
        Icons.storage_outlined,
        '下载与缓存',
        '缓存上限 ${(app.cache.maxBytes / 1073741824).toStringAsFixed(1)} GiB · 任务与清理',
        _Section.cache,
      ),
    ]),
    _group('播放与阅读', [
      _entry(
        Icons.tune_rounded,
        '播放器设置',
        '${app.playback.speed.toStringAsFixed(2)}× · 音量 ${app.playback.volume.round()}% · ReplayGain',
        _Section.playback,
      ),
      _entry(
        Icons.lyrics_outlined,
        '歌词设置',
        '完整歌词 ${Appearance.lyricFontLabel(app.appearance.lyricFontSize)} · 迷你歌词 ${Appearance.miniLyricFontLabel(app.appearance.miniLyricFontSize)}',
        _Section.lyrics,
      ),
    ]),
    _group('外观与个性化', [
      _entry(
        Icons.palette_outlined,
        '主题与配色',
        '$_themeLabel · ${app.appearance.seedHex}',
        _Section.theme,
      ),
      _entry(
        Icons.wallpaper_outlined,
        '页面背景',
        app.appearance.solidBackground
            ? '纯色背景 · 跟随深浅色'
            : app.appearance.backgroundFile != null
            ? '自定义图片 · 可见度 ${(app.appearance.backgroundVisibility * 100).round()}%'
            : '默认主题背景',
        _Section.background,
      ),
      _entry(
        Icons.album_outlined,
        '播放器外观',
        '${app.appearance.disc ? '唱片样式' : '方形封面'} · 封面模糊${app.appearance.ambient ? '开启' : '关闭'}',
        _Section.player,
      ),
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        _entry(
          Icons.apps_outlined,
          '应用图标',
          '选择桌面启动图标 · 仅 Android',
          _Section.icon,
        ),
    ]),
    _group('网络与接口', [
      _entry(
        Icons.api_outlined,
        'API 设置',
        '每日一言 · GitHub 加速 · 在线歌词',
        _Section.api,
      ),
    ]),
    _group('应用与支持', [
      ListTile(
        leading: _entryIcon(Icons.system_update_alt),
        title: const Text('检查更新'),
        subtitle: const Text('手动检查新版本与发布说明'),
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
        app.diagnostics.enabled ? '诊断日志记录中 · 导出或分享日志' : '默认关闭 · 记录、导出与分享本机日志',
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
        subtitle: const Text('仅在应用前台检查，按需更新到期音源'),
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
        title: const Text('自动同步系统通知'),
        subtitle: const Text('同步结束时发送系统通知，需允许系统通知权限'),
        value: app.autoSyncNotice,
        onChanged: (v) => _act(() => app.setAutoSyncNotice(v)),
      ),
      ListTile(
        title: const Text('默认收藏位置'),
        subtitle: const Text(
          '云端收藏支持 Emby、Navidrome / OpenSubsonic，其余来源仍使用本地收藏',
        ),
        trailing: DropdownButton<bool>(
          value: app.cloudFavoritesByDefault,
          items: const [
            DropdownMenuItem(value: false, child: Text('本地')),
            DropdownMenuItem(value: true, child: Text('云端')),
          ],
          onChanged: (v) {
            if (v != null) _act(() => app.setCloudFavoritesByDefault(v));
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
        title: const Text('ReplayGain 响度调整'),
        subtitle: const Text('默认关闭，可选按曲目或按专辑调整'),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.equalizer),
          onSelected: (v) => _act(() => app.playback.setReplayGain(v)),
          itemBuilder: (ctx) => const [
            PopupMenuItem(value: 'no', child: Text('关闭')),
            PopupMenuItem(value: 'track', child: Text('Track')),
            PopupMenuItem(value: 'album', child: Text('Album')),
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
          '${Appearance.miniLyricFontLabel(app.appearance.miniLyricFontSize)} · 仅播放页迷你歌词区',
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
        subtitle: const Text('一级页面与播放页基础底色跟随深浅色使用白 / 黑；播放页封面模糊开启时叠加封面模糊'),
        value: app.appearance.solidBackground,
        onChanged: (v) => _act(() => app.appearance.update(solid: v)),
      ),
      ListTile(
        title: const Text('自定义背景图'),
        subtitle: Text(
          app.appearance.backgroundFile == null
              ? '选择图片，仅在四个主页面显示'
              : app.appearance.solidBackground
              ? '已选择图片 · 纯色背景开启时不显示'
              : '四个主页面 · 保持比例自适应铺满',
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
    _Section.player => [
      ListTile(
        title: const Text('播放器控制'),
        subtitle: const Text('每次启动的默认样式，使用中可手动切换'),
        trailing: DropdownButton<bool>(
          value: app.appearance.playerFab,
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: false, child: Text('横条')),
            DropdownMenuItem(value: true, child: Text('FAB 悬浮按钮')),
          ],
          onChanged: (value) =>
              _act(() => app.appearance.update(playerFab: value)),
        ),
      ),
      SwitchListTile(
        title: const Text('唱片播放样式'),
        subtitle: const Text('系统默认与自定义播放页共用；关闭时使用方形封面'),
        value: app.appearance.disc,
        onChanged: (v) => _act(() => app.appearance.update(record: v)),
      ),
      SwitchListTile(
        title: const Text('封面模糊背景'),
        subtitle: const Text('播放页布局背景为封面模糊时生效；关闭时使用主题 / 纯色底色'),
        value: app.appearance.ambient,
        onChanged: (v) => _act(() => app.appearance.update(background: v)),
      ),
      SwitchListTile(
        title: const Text('磨砂迷你播放器'),
        subtitle: const Text('实验性效果，默认关闭'),
        value: app.appearance.glass,
        onChanged: (v) => _act(() => app.appearance.update(frost: v)),
      ),
      SwitchListTile(
        title: const Text('唱片旋转'),
        subtitle: const Text('播放时旋转唱片，暂停时保持角度'),
        value: app.appearance.discRotation,
        onChanged: app.appearance.disc
            ? (v) => _act(() => app.appearance.update(rotateDisc: v))
            : null,
      ),
    ],
    _Section.icon => [const LauncherIconPicker()],
    _Section.cache => [
      ListTile(
        title: const Text('缓存空间与逐曲清理'),
        leading: const Icon(Icons.storage),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CacheStoragePage(app: app)),
        ),
      ),
      ListTile(
        title: const Text('清理全部完整歌曲缓存'),
        subtitle: const Text('同时取消受到影响的任务；不会删除服务器或本地原始音频'),
        trailing: const Icon(Icons.delete_outline),
        onTap: () async {
          if (await _confirm('确认清理全部音频缓存？')) {
            await _act(() => app.clearCache());
          }
        },
      ),
      ListTile(
        title: const Text('缓存预算'),
        subtitle: Text(
          '当前 ${(app.cache.maxBytes / 1073741824).toStringAsFixed(1)} GiB',
        ),
        trailing: const Icon(Icons.edit),
        onTap: _changeBudget,
      ),
      ListTile(
        title: const Text('查看缓存任务与进度'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _downloads,
      ),
    ],
    _Section.api => [
      ListTile(
        key: const ValueKey('api-quote'),
        leading: const Icon(Icons.format_quote_rounded),
        title: const Text('每日一言 API'),
        subtitle: Text(app.apiSettings.quoteUrl),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => _editApiUrl(quote: true),
      ),
      const Divider(height: 1),
      ListTile(
        key: const ValueKey('api-github-mirror'),
        leading: const Icon(Icons.cloud_download_outlined),
        title: const Text('GitHub 加速 API'),
        subtitle: Text(app.apiSettings.githubMirror),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => _editApiUrl(quote: false),
      ),
      const Divider(height: 1),
      SwitchListTile(
        key: const ValueKey('api-lrc-enabled'),
        secondary: const Icon(Icons.lyrics_outlined),
        title: const Text('LrcApi 在线歌词补充'),
        subtitle: const Text('现有来源无歌词时，将歌名、艺术家和专辑发送至所配置接口'),
        value: app.apiSettings.lrcApiEnabled,
        onChanged: (value) =>
            _act(() => app.apiSettings.setLrcApiEnabled(value)),
      ),
      ListTile(
        key: const ValueKey('api-lrc-url'),
        leading: const Icon(Icons.link_outlined),
        title: const Text('LrcApi 接口地址'),
        subtitle: Text(app.apiSettings.lrcApiUrl),
        trailing: const Icon(Icons.edit_outlined),
        onTap: _editLrcApiUrl,
      ),
      ListTile(
        key: const ValueKey('api-lrc-auth'),
        leading: const Icon(Icons.key_outlined),
        title: const Text('LrcApi 鉴权密钥'),
        subtitle: const Text('可选；保存在系统安全存储中'),
        trailing: const Icon(Icons.edit_outlined),
        onTap: _editLrcApiToken,
      ),
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'GitHub 加速地址使用 HTTPS。LrcApi 默认使用 HTTPS；自部署支持 HTTP，带鉴权密钥时仅允许 HTTPS 或本机回环地址。',
        ),
      ),
    ],
    _Section.diagnostics => [
      SwitchListTile(
        key: const ValueKey('diagnostics-toggle'),
        secondary: const Icon(Icons.bug_report_outlined),
        title: const Text('记录诊断日志'),
        subtitle: const Text(
          '默认关闭。开启后记录播放、切歌、缓冲与网络代理事件；不记录歌曲名、账号和地址。最多保留约 1.5 MiB。',
        ),
        value: app.diagnostics.enabled,
        onChanged: (v) => _act(() => app.setDiagnosticLogging(v)),
      ),
      ListTile(
        key: const ValueKey('diagnostics-export'),
        leading: const Icon(Icons.save_alt),
        title: const Text('导出诊断日志'),
        subtitle: const Text('保存为可阅读的文本文件，关闭记录后也可导出'),
        onTap: () => _act(_exportDiagnosticLogs),
      ),
      ListTile(
        key: const ValueKey('diagnostics-share'),
        leading: const Icon(Icons.share_outlined),
        title: const Text('分享诊断日志'),
        subtitle: Text(
          Platform.isLinux ? 'Linux 不支持直接分享附件，改为导出文件' : '通过系统分享面板发送日志附件',
        ),
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
