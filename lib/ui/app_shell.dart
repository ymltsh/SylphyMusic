import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/listening_history.dart';
import '../core/models.dart';
import 'cache_tasks.dart';
import 'cache_storage.dart';
import 'playlist_page.dart';
import 'playlist_reorder_grid.dart';
import 'player_bar.dart';
import 'playing_song_tile.dart';
import 'route_player_bar.dart';
import 'playback_notice.dart';
import 'capsule_toggle.dart';
import 'cover_art.dart';
import 'cover_flow.dart';
import 'library_browser.dart';
import 'track_lookup.dart';
import 'track_actions.dart';
import 'batch_selection.dart';
import 'home_page.dart';
import 'search_page.dart';
import 'app_background.dart';
import 'app_identity.dart';
import 'player_cover.dart';
import 'settings_page.dart';
import 'music_sources_panel.dart';
import 'music_space_card.dart';
import 'music_source_connection_page.dart';
import 'quick_start_wizard.dart';
import '../data/library_catalog.dart';

class SylphyShell extends StatefulWidget {
  const SylphyShell({super.key, required this.app});
  final SylphyApp app;
  @override
  State<SylphyShell> createState() => _SylphyShellState();
}

class _SylphyShellState extends State<SylphyShell> with WidgetsBindingObserver {
  int tab = 0;
  final BatchSelection _librarySelection = BatchSelection();
  int libraryView = 0;
  bool albumCoverFlow = false;
  bool playlistCoverFlow = false;
  bool playerCollapsed = false;
  late bool _defaultPlayerFab;
  bool? onboarding;
  bool descending = false;
  String sort = 'name';
  static const labels = ['首页', '音乐库', '歌单', '我的'];
  static const icons = [
    Icons.home_outlined,
    Icons.library_music_outlined,
    Icons.queue_music_outlined,
    Icons.person_outline,
  ];
  SylphyApp get app => widget.app;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    app.addListener(_update);
    app.playback.addListener(_update);
    playerCollapsed = _defaultPlayerFab = app.appearance.playerFab;
    app.appearance.addListener(_appearanceChanged);
    unawaited(_loadWelcome());
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    app.diagnostics.record('app', 'lifecycle', details: {'state': state.name});
    if (state == AppLifecycleState.resumed) {
      unawaited(app.refreshIfStale());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    app.removeListener(_update);
    app.playback.removeListener(_update);
    app.appearance.removeListener(_appearanceChanged);
    _librarySelection.dispose();
    super.dispose();
  }

  void _appearanceChanged() {
    if (_defaultPlayerFab != app.appearance.playerFab) {
      playerCollapsed = _defaultPlayerFab = app.appearance.playerFab;
    }
    _update();
  }

  void _update() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _act(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), duration: const Duration(seconds: 6)),
        );
      }
    }
  }

  Future<void> _loadWelcome() async {
    final done = await app.db.setting('ui_onboarded') == 'true';
    if (mounted) setState(() => onboarding = !done && app.sources.isEmpty);
  }

  Future<void> _finishWelcome() async {
    await _act(() async {
      await app.db.setSetting('ui_onboarded', 'true');
      if (mounted) setState(() => onboarding = false);
    });
  }

  void _open(String title, Widget Function() page) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnimatedBuilder(
          animation: Listenable.merge([app, app.appearance, app.playback]),
          builder: (context, _) => Scaffold(
            appBar: AppBar(title: Text(title)),
            body: SafeArea(top: false, child: page()),
            bottomNavigationBar: RoutePlayerBar(app: app),
          ),
        ),
      ),
    );
  }

  void _library([int view = 0]) {
    _librarySelection.clear();
    setState(() {
      tab = 1;
      libraryView = view;
    });
  }

  void _favorites() {
    final favorite = app.playlists
        .where((p) => p.id == 'favorites')
        .firstOrNull;
    if (favorite != null) _playlistDetails(favorite);
  }

  void _downloads() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => CacheTasksPage(app: app)),
  );

  @override
  Widget build(BuildContext context) {
    return PlaybackNotice(
      playback: app.playback,
      readError: () => app.playback.error,
      child: _buildContent(context),
    );
  }

  double _navigationBarHeight(BuildContext context) {
    // NavigationBar.height excludes the bottom system inset. Keep icons and
    // labels comfortable while adapting to accessibility text scaling.
    final labelHeight = MediaQuery.textScalerOf(context).scale(12);
    final extra = ((labelHeight - 12) * 2).clamp(0.0, 32.0).toDouble();
    final shortScreen = MediaQuery.sizeOf(context).height < 600;
    return (72.0 + extra - (shortScreen ? 4.0 : 0.0))
        .clamp(68.0, 104.0)
        .toDouble();
  }

  Widget _buildContent(BuildContext context) {
    if (onboarding == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (onboarding!) return _welcome();
    final wide = MediaQuery.sizeOf(context).width > 750;
    final playerAnimation = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);
    final main = Column(
      children: [
        if (app.busy) const LinearProgressIndicator(),
        Expanded(
          // The desktop player is docked below the content, never painted over
          // the scrolled page. Keep the mobile overlay unchanged.
          child: wide
              ? _page()
              : Stack(
                  children: [
                    Positioned.fill(child: _page()),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 8,
                      child: IgnorePointer(
                        ignoring: playerCollapsed,
                        child: AnimatedSlide(
                          offset: playerCollapsed
                              ? const Offset(0, 1.4)
                              : Offset.zero,
                          duration: playerAnimation,
                          curve: Curves.easeOutCubic,
                          child: AnimatedOpacity(
                            opacity: playerCollapsed ? 0 : 1,
                            duration: playerAnimation,
                            curve: Curves.easeOutCubic,
                            child: _playerBar(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        if (wide && !playerCollapsed) _desktopPlayerBar(),
      ],
    );
    final solidBackground = app.appearance.solidBackground;
    final customBackground =
        app.appearance.backgroundFile != null && !solidBackground;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AppBackground(
      appearance: app.appearance,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: solidBackground
              ? Colors.transparent
              : customBackground
              ? scheme.surface.withValues(alpha: .90)
              : null,
          surfaceTintColor: solidBackground ? Colors.transparent : null,
          title: Text(
            tab == 0 ? appDisplayName() : labels[tab],
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          actionsPadding: const EdgeInsetsDirectional.only(end: 16),
          actions: [
            SizedBox.square(
              dimension: 48,
              child: IconButton(
                tooltip: '搜索',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SearchPage(app: app, onAction: _trackAction),
                  ),
                ),
                icon: const Icon(Icons.search),
              ),
            ),
            SizedBox.square(
              dimension: 48,
              child: IconButton(
                tooltip: '设置',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsPage(
                      app: app,
                      onSources: () => _open('音乐源管理', _sources),
                    ),
                  ),
                ),
                icon: const Icon(Icons.settings_outlined),
              ),
            ),
          ],
        ),
        body: wide
            ? Row(
                children: [
                  NavigationRail(
                    extended: MediaQuery.sizeOf(context).width > 1050,
                    minExtendedWidth: 208,
                    minWidth: 72,
                    backgroundColor: solidBackground
                        ? Colors.transparent
                        : null,
                    selectedIndex: tab,
                    onDestinationSelected: (v) {
                      if (v != 1) _librarySelection.clear();
                      setState(() => tab = v);
                    },
                    destinations: List.generate(
                      labels.length,
                      (i) => NavigationRailDestination(
                        icon: Icon(icons[i]),
                        label: Text(labels[i]),
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: main),
                ],
              )
            : main,
        floatingActionButton: playerCollapsed ? _collapsedPlayerFab() : null,
        bottomNavigationBar: wide
            ? null
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  NavigationBar(
                    elevation: 0,
                    backgroundColor: dark
                        ? scheme.surfaceContainerLow.withValues(
                            alpha: customBackground ? .92 : 1,
                          )
                        : solidBackground
                        ? Colors.transparent
                        : customBackground
                        ? scheme.surfaceContainer.withValues(alpha: .90)
                        : null,
                    surfaceTintColor: dark || solidBackground
                        ? Colors.transparent
                        : null,
                    height: _navigationBarHeight(context),
                    maintainBottomViewPadding: true,
                    selectedIndex: tab,
                    onDestinationSelected: (v) {
                      if (v != 1) _librarySelection.clear();
                      setState(() => tab = v);
                    },
                    destinations: List.generate(
                      labels.length,
                      (i) => NavigationDestination(
                        icon: Icon(icons[i]),
                        label: labels[i],
                      ),
                    ),
                  ),
                  Positioned(
                    top: -6,
                    left: 0,
                    right: 0,
                    height: 6,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: dark ? .18 : .07),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _libraryFilterBar() => ListenableBuilder(
    listenable: _librarySelection,
    builder: (context, _) => Align(
      key: const ValueKey('library-filter-bar'),
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: CapsuleToggle<int>(
                keyPrefix: 'library-filter',
                selected: libraryView,
                onChanged: (value) {
                  _librarySelection.clear();
                  setState(() => libraryView = value);
                },
                options: const [
                  CapsuleOption(
                    value: 0,
                    label: '歌曲',
                    icon: Icons.music_note_outlined,
                  ),
                  CapsuleOption(
                    value: 1,
                    label: '专辑',
                    icon: Icons.album_outlined,
                  ),
                  CapsuleOption(
                    value: 2,
                    label: '艺术家',
                    icon: Icons.person_outline,
                  ),
                ],
              ),
            ),
            if (_librarySelection.active)
              IconButton(
                key: const ValueKey('library-batch-more'),
                tooltip: '多选的更多操作',
                icon: const Icon(Icons.more_vert),
                onPressed: _librarySelection.count == 0
                    ? null
                    : () => unawaited(_libraryBatchActions()),
              )
            else if (libraryView == 1)
              SizedBox.square(
                dimension: 48,
                child: IconButton(
                  key: const ValueKey('album-cover-flow-toggle'),
                  tooltip: albumCoverFlow ? '切换到列表' : '切换到 Cover Flow',
                  isSelected: albumCoverFlow,
                  onPressed: () =>
                      setState(() => albumCoverFlow = !albumCoverFlow),
                  icon: const Icon(Icons.view_carousel_outlined),
                  selectedIcon: const Icon(Icons.view_list_rounded),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _sortControls() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox.square(
        dimension: 48,
        child: PopupMenuButton<String>(
          tooltip: '排序',
          icon: const Icon(Icons.sort),
          onSelected: (v) {
            _librarySelection.clear();
            setState(() => sort = v);
          },
          itemBuilder: (ctx) => const [
            PopupMenuItem(value: 'name', child: Text('名称')),
            PopupMenuItem(value: 'artist', child: Text('艺术家')),
            PopupMenuItem(value: 'album', child: Text('专辑')),
            PopupMenuItem(value: 'duration', child: Text('时长')),
            PopupMenuItem(value: 'year', child: Text('年份')),
          ],
        ),
      ),
      SizedBox.square(
        dimension: 48,
        child: IconButton(
          tooltip: '升序 / 降序',
          onPressed: () {
            _librarySelection.clear();
            setState(() => descending = !descending);
          },
          icon: Icon(descending ? Icons.arrow_downward : Icons.arrow_upward),
        ),
      ),
    ],
  );

  Widget _page() {
    switch (tab) {
      case 0:
        return HomePage(
          app: app,
          onLibrary: _library,
          onSources: () => _open('音乐源管理', _sources),
          onAction: _trackAction,
        );
      case 1:
        return ListenableBuilder(
          listenable: _librarySelection,
          builder: (context, _) => LibraryBrowser(
            app: app,
            query: CatalogQuery(
              view: libraryView,
              sort: sort,
              descending: descending,
            ),
            onAction: _trackAction,
            batchSelection: _librarySelection,
            coverFlow:
                libraryView == 1 && albumCoverFlow && !_librarySelection.active,
            viewControls: _libraryFilterBar(),
            songActions: _sortControls(),
          ),
        );
      case 2:
        return _playlists();
      default:
        return _personal();
    }
  }

  Widget _welcome() => QuickStartWizard(
    app: app,
    onConnect: (kind) => _addSource(initialKind: kind),
    onImportFiles: () => _act(app.importLocalFiles),
    onImportFolder: () => _act(app.importLocalFolder),
    onFinish: _finishWelcome,
  );

  Widget _personalShortcut(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      icon,
                      color: scheme.onPrimaryContainer,
                      size: 23,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _personalHeading(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w600),
    ),
  );

  Widget _personal() => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1040),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.sizeOf(context).width > 750 ? 32 : 116,
        ),
        children: [
          MusicSpaceCard(
            sources: app.sources,
            playlistCount: app.playlists.length,
            onTap: () => _open('音乐来源', _sources),
          ),
          _personalHeading('我的音乐'),
          LayoutBuilder(
            builder: (context, size) {
              final columns = size.maxWidth >= 760 ? 4 : 2;
              final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio:
                    size.maxWidth /
                    columns /
                    (158 + (textScale - 1).clamp(0.0, 3.0) * 65),
                children: [
                  _personalShortcut(
                    Icons.history_rounded,
                    '最近播放',
                    '最多 ${ListeningHistory.maxEntries} 首播放记录',
                    () => _open('最近播放', () => ListeningHistoryPage(app: app)),
                  ),
                  _personalShortcut(
                    Icons.favorite_outline,
                    '我的收藏',
                    '喜欢的歌曲集中收藏',
                    _favorites,
                  ),
                  _personalShortcut(
                    Icons.library_music_outlined,
                    '全部音乐',
                    '浏览曲库中的所有歌曲',
                    () => _library(0),
                  ),
                  _personalShortcut(
                    Icons.download_outlined,
                    '本地下载',
                    '查看下载与缓存任务',
                    _downloads,
                  ),
                ],
              );
            },
          ),
          _personalHeading('音乐管理'),
          Card.outlined(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                  leading: const Icon(Icons.storage_outlined),
                  title: const Text('缓存与存储'),
                  subtitle: const Text('查看空间占用，管理离线资源'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CacheStoragePage(app: app),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 62, endIndent: 18),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                  leading: const Icon(Icons.block_outlined),
                  title: const Text('歌曲黑名单'),
                  subtitle: const Text('管理不希望在曲库中显示的歌曲'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showBlacklist,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _tracks(
    List<Track> tracks, {
    bool showPlayAll = true,
    Future<void> Function(int)? onRemove,
    bool favorites = false,
    List<String>? entryIds,
    BatchSelection? batchSelection,
  }) {
    if (tracks.isEmpty) {
      return const Center(
        child: Text('暂无音乐。可以先添加 Emby、Navidrome 或 WebDAV 来源。'),
      );
    }
    return ListView.builder(
      itemCount: tracks.length + (showPlayAll ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (showPlayAll && i == 0) {
          return ListTile(
            leading: const Tooltip(
              message: '播放全部',
              child: Icon(Icons.play_circle),
            ),
            title: Text('${tracks.length}'),
            onTap: () => _act(
              () => app.playback.setQueue(tracks.map((t) => t.ref).toList()),
            ),
          );
        }
        final track = tracks[i - (showPlayAll ? 1 : 0)];
        final entryKey = entryIds == null
            ? track.ref.key
            : entryIds[i - (showPlayAll ? 1 : 0)];
        final selecting = batchSelection?.active == true;
        return PlayingSongTile(
          app: app,
          track: track,
          title: track.title,
          subtitle:
              '${track.artist} · ${track.album} · ${_sourceName(track.ref.sourceId)}',
          selectedInBatch: selecting && batchSelection!.contains(entryKey),
          onLongPress: batchSelection == null
              ? null
              : () => batchSelection.begin(entryKey),
          onTap: selecting
              ? () => batchSelection!.toggle(entryKey)
              : () => _act(
                  () => app.playback.setQueue(
                    tracks.map((t) => t.ref).toList(),
                    start: i - (showPlayAll ? 1 : 0),
                  ),
                ),
          trailing: selecting
              ? SizedBox.square(
                  dimension: 48,
                  child: Checkbox(
                    value: batchSelection!.contains(entryKey),
                    onChanged: (_) => batchSelection.toggle(entryKey),
                  ),
                )
              : PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'multi_select' && batchSelection != null) {
                      batchSelection.begin(entryKey);
                    } else if (v == 'remove_entry' && onRemove != null) {
                      unawaited(
                        _act(() => onRemove(i - (showPlayAll ? 1 : 0))),
                      );
                    } else {
                      unawaited(_trackAction(v, track));
                    }
                  },
                  itemBuilder: (ctx) => [
                    if (batchSelection != null)
                      const PopupMenuItem(
                        value: 'multi_select',
                        child: Text('多选'),
                      ),
                    PopupMenuItem(value: 'favorite', child: Text('收藏 / 取消收藏')),
                    const PopupMenuItem(
                      value: 'playlist',
                      child: Text('添加到歌单'),
                    ),
                    const PopupMenuItem(value: 'next', child: Text('下一首播放')),
                    const PopupMenuItem(
                      value: 'enqueue',
                      child: Text('添加到播放队列'),
                    ),
                    const PopupMenuItem(value: 'cache', child: Text('缓存整首歌曲')),
                    if (onRemove != null)
                      PopupMenuItem(
                        value: 'remove_entry',
                        child: Text(favorites ? '从收藏移除' : '从此歌单移除'),
                      ),
                    PopupMenuItem(
                      value: 'block',
                      child: Text(
                        app.blacklist.contains(track.ref.key)
                            ? '取消屏蔽'
                            : '加入黑名单',
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  String _sourceName(String sourceId) {
    for (final s in app.sources) {
      if (s.id == sourceId) return s.name;
    }
    return sourceId;
  }

  Future<void> _trackAction(String action, Track track) =>
      _act(() => performTrackAction(context, app, action, track));

  Future<void> _libraryBatchActions() async {
    final selection = _librarySelection;
    final query = CatalogQuery(
      view: libraryView,
      sort: sort,
      descending: descending,
    );
    final all = selection.all;
    final chosen = selection.selectedKeys;
    final excluded = selection.excludedKeys;
    final count = selection.count;
    final success = await showBatchTrackActions(
      context,
      app,
      count: count,
      countUnit: query.view == 0
          ? '首'
          : query.view == 1
          ? '张专辑'
          : '位艺术家',
      resolve: () async {
        if (query.view == 0) {
          final refs = await app.catalog.queue(query.songs);
          return [
            for (final ref in refs)
              if (all ? !excluded.contains(ref.key) : chosen.contains(ref.key))
                ref,
          ];
        }
        final kind = query.view == 1 ? 'album' : 'artist';
        if (all) {
          final refs = await app.catalog.queue(query.songs);
          final omitted = <String>{};
          for (final key in excluded) {
            final group = await app.catalog.queue(query.songsIn(kind, key));
            omitted.addAll(group.map((ref) => ref.key));
          }
          return [
            for (final ref in refs)
              if (!omitted.contains(ref.key)) ref,
          ];
        }
        final seen = <String>{};
        final refs = <TrackRef>[];
        for (final key in chosen) {
          final group = await app.catalog.queue(query.songsIn(kind, key));
          for (final ref in group) {
            if (seen.add(ref.key)) refs.add(ref);
          }
        }
        return refs;
      },
    );
    if (success) selection.clear();
  }

  Widget _playlists() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            FilledButton.icon(
              key: const ValueKey('new-playlist'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _newPlaylist,
              icon: const Icon(Icons.add),
              label: const Text('新建歌单'),
            ),
            const Spacer(),
            IconButton(
              tooltip: playlistCoverFlow ? '切换到歌单网格' : '切换到歌单 Cover Flow',
              isSelected: playlistCoverFlow,
              onPressed: () =>
                  setState(() => playlistCoverFlow = !playlistCoverFlow),
              icon: const Icon(Icons.view_carousel_outlined),
              selectedIcon: const Icon(Icons.grid_view_rounded),
            ),
            IconButton(
              tooltip: '同步云歌单',
              onPressed: app.busy
                  ? null
                  : () => _act(() async {
                      await app.cloud.syncAll();
                      await app.reload();
                    }),
              icon: const Icon(Icons.cloud_sync_outlined),
            ),
          ],
        ),
      ),
      Expanded(
        child: app.playlists.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.queue_music_rounded,
                      size: 56,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    const Text('还没有歌单'),
                    const SizedBox(height: 4),
                    const Text('创建一个歌单，收纳喜欢的音乐。'),
                  ],
                ),
              )
            : playlistCoverFlow
            ? CoverFlowView(
                key: const ValueKey('playlist-cover-flow'),
                itemCount: app.playlists.length,
                coverBuilder: (context, index, size) => PlaylistCoverFlowArt(
                  app: app,
                  playlist: app.playlists[index],
                  size: size,
                ),
                titleBuilder: (index) => app.playlists[index].name,
                subtitleBuilder: (index) {
                  final playlist = app.playlists[index];
                  return switch (playlist.kind) {
                    PlaylistKind.favorites => '我的收藏',
                    PlaylistKind.local => '本地歌单',
                    PlaylistKind.cloud =>
                      '云端 · ${_sourceName(playlist.sourceId ?? '')}',
                  };
                },
                onActivate: (index) => _playlistDetails(app.playlists[index]),
                bottomPadding: 84,
                emptyMessage: '还没有歌单',
              )
            : PlaylistReorderGrid(
                playlists: app.playlists,
                onMove: app.movePlaylistDisplay,
                cardBuilder: (context, playlist) => PlaylistGridCard(
                  key: ValueKey('playlist/${playlist.id}'),
                  app: app,
                  playlist: playlist,
                  sourceName: _sourceName(playlist.sourceId ?? ''),
                  onOpen: () => _playlistDetails(playlist),
                  onAction: (value) => _playlistAction(value, playlist),
                ),
              ),
      ),
    ],
  );
  Future<void> _newPlaylist() async {
    final name = TextEditingController();
    String id = 'local';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('新建歌单'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '歌单名称'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: id,
                decoration: const InputDecoration(labelText: '保存位置'),
                items: [
                  const DropdownMenuItem(value: 'local', child: Text('本地歌单')),
                  ...app.sources
                      .where((s) => s.enabled && s.kind.cloudPlaylistWritable)
                      .map(
                        (s) => DropdownMenuItem(
                          value: s.id,
                          child: Text('云端 · ${s.name}'),
                        ),
                      ),
                ],
                onChanged: (v) => setDialog(() => id = v ?? 'local'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    if (result != true || name.text.trim().isEmpty) return;
    final source = id == 'local'
        ? null
        : app.sources.where((s) => s.id == id).firstOrNull;
    await _act(() => app.addPlaylist(name.text.trim(), cloudSource: source));
    name.dispose();
  }

  Future<void> _playlistDetails(PlaylistModel playlist) async {
    PlaylistModel latest() =>
        app.playlists.where((p) => p.id == playlist.id).firstOrNull ?? playlist;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistPage(
          app: app,
          id: playlist.id,
          buildTracks: (tracks) => _tracks(tracks, showPlayAll: false),
          buildEntryTracks: (tracks, entryIds, selection) => _tracks(
            tracks,
            showPlayAll: false,
            entryIds: entryIds,
            batchSelection: selection,
            favorites: latest().kind == PlaylistKind.favorites,
            onRemove:
                (latest().kind == PlaylistKind.favorites ||
                    playlistCanEdit(app, latest()))
                ? (index) => app.removePlaylistEntry(latest(), entryIds[index])
                : null,
          ),
          onAction: (action) => _playlistAction(action, latest()),
          onEdit: () => _editPlaylist(latest()),
          onAdd: () => _addToPlaylist(latest()),
          onCache: () => _act(() => app.cachePlaylist(latest())),
        ),
      ),
    );
  }

  Future<void> _editPlaylist(PlaylistModel p) async {
    final keys = await app.db.playlistKeys(p.id);
    if (!mounted) return;
    final working = [...keys];
    final accept = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: Text('编辑歌单 · ${p.name}'),
          content: SizedBox(
            width: 520,
            height: 420,
            child: ReorderableListView.builder(
              itemCount: working.length,
              buildDefaultDragHandles: true,
              onReorderItem: (oldIndex, newIndex) {
                refresh(() {
                  final item = working.removeAt(oldIndex);
                  working.insert(newIndex, item);
                });
              },
              itemBuilder: (ctx, index) {
                final key = working[index];
                return TrackLookup(
                  key: ValueKey('$index-$key'),
                  app: app,
                  ref: TrackRef.parse(key),
                  builder: (ctx, track) => ListTile(
                    title: Text(track?.title ?? '不可用歌曲'),
                    subtitle: Text(track?.artist ?? key),
                    trailing: IconButton(
                      tooltip: '移除这条歌单记录',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => refresh(() => working.removeAt(index)),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存修改'),
            ),
          ],
        ),
      ),
    );
    if (accept == true) await _act(() => app.setPlaylistKeys(p, working));
  }

  Future<void> _addToPlaylist(PlaylistModel p) async {
    var search = '';
    final additions = <String>{};
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: const Text('添加歌曲'),
          content: SizedBox(
            width: 500,
            height: 420,
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(labelText: '搜索歌曲'),
                  onChanged: (value) => refresh(() => search = value),
                ),
                Expanded(
                  child: LibraryBrowser(
                    app: app,
                    query: CatalogQuery(
                      search: search,
                      sourceId: p.kind == PlaylistKind.cloud
                          ? p.sourceId
                          : null,
                    ),
                    onAction: _trackAction,
                    selected: additions,
                    onSelection: (track, selected) => refresh(() {
                      if (selected) {
                        additions.add(track.ref.key);
                      } else {
                        additions.remove(track.ref.key);
                      }
                    }),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || additions.isEmpty) return;
    await _act(() async {
      final keys = await app.db.playlistKeys(p.id);
      await app.setPlaylistKeys(p, [...keys, ...additions]);
    });
  }

  Future<void> _playlistAction(String action, PlaylistModel p) async {
    if (action == 'enqueue') {
      await _act(() async {
        final count = await app.enqueuePlaylist(p);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(count == 0 ? '歌单为空，未添加歌曲' : '已将 $count 首歌曲添加到播放队列'),
          ),
        );
      });
      return;
    }
    if (action == 'rename') {
      final name = TextEditingController(text: p.name);
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('重命名歌单'),
          content: TextField(controller: name, autofocus: true, maxLength: 120),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (accepted == true) {
        await _act(() async {
          await app.cloud.renameLocal(p.id, name.text);
          await app.reload();
        });
      }
      name.dispose();
      return;
    }
    if (action == 'cache') {
      await _act(() => app.cachePlaylist(p));
      return;
    }
    if (action == 'sync') {
      await _act(() => app.syncPlaylist(p));
      return;
    }
    if (action == 'resolve') {
      await _resolveConflict(p);
      return;
    }
    if (action == 'copy_local') {
      await _act(() => app.copyPlaylist(p));
      return;
    }
    if (action == 'copy_cloud') {
      final source = await showDialog<SourceProfile>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('选择云歌单目标来源'),
          children: app.sources
              .where((s) => s.enabled && s.kind.cloudPlaylistWritable)
              .map(
                (s) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, s),
                  child: Text(s.name),
                ),
              )
              .toList(),
        ),
      );
      if (source != null) await _act(() => app.copyPlaylist(p, target: source));
      return;
    }
    if (action == 'remove' || action == 'delete_remote') {
      final allow = await _confirm(
        action == 'delete_remote'
            ? '确定从服务器删除歌单「${p.name}」？'
            : '仅从此设备移除「${p.name}」？',
      );
      if (allow) {
        await _act(
          () => app.deletePlaylist(p, remote: action == 'delete_remote'),
        );
      }
    }
  }

  Future<void> _resolveConflict(PlaylistModel p) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('歌单同步冲突'),
        content: Text('${p.name}：${p.message}\n不会静默丢弃任一版本。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后处理'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'server'),
            child: const Text('保留云端，另存本地草稿'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'local'),
            child: const Text('保留本地，备份云端'),
          ),
        ],
      ),
    );
    if (choice != null) {
      await _act(() async {
        await app.cloud.resolveConflict(p.id, useLocal: choice == 'local');
        await app.reload();
      });
    }
  }

  Widget _sources() => MusicSourcesPanel(
    app: app,
    onAdd: () => _addSource(),
    onSyncAll: () => _act(app.syncAllForeground),
    onImportFiles: () => _act(app.importLocalFiles),
    onImportFolder: () => _act(app.importLocalFolder),
    onSelect: (source) {
      setState(() {
        tab = 1;
        libraryView = 0;
      });
      // Sources can be opened above nested settings routes. Reveal the shell's
      // library rather than just exposing the previous settings page.
      Navigator.of(context).popUntil((route) => route.isFirst);
    },
    onAction: _handleSourceAction,
  );

  Future<void> _handleSourceAction(SourceProfile source, String action) async {
    if (action == 'cancel_sync') {
      app.cancelActiveSync(source.id);
    } else if (action == 'sync') {
      await _act(() => app.syncSourceForeground(source));
    } else if (action == 'tags') {
      await _act(() => app.enrichSourceForeground(source));
    } else if (action == 'edit') {
      await _editSource(source);
    } else if (action == 'scan') {
      await _act(() => app.rescanLocal(source));
    } else if (action == 'toggle') {
      await _act(() => app.toggleSource(source));
    } else if (action == 'cache') {
      await _act(() => app.clearCache(sourceId: source.id));
    } else if (action == 'delete' &&
        await _confirm('删除 ${source.name} 及本机管理的相关数据？不会删除服务器上的音乐。')) {
      await _act(() => app.deleteSource(source));
    }
  }

  Future<void> _addSource({SourceKind initialKind = SourceKind.emby}) async {
    final draft = await Navigator.of(context).push<MusicSourceConnectionDraft>(
      MaterialPageRoute(
        builder: (_) => MusicSourceConnectionPage(
          initialKind: initialKind,
          browseWebDavDirectories: app.browseWebDavDirectories,
        ),
      ),
    );
    if (!mounted || draft == null) return;
    await _act(
      () => app.addSource(
        kind: draft.kind,
        name: draft.name,
        url: draft.url,
        username: draft.username,
        password: draft.password,
        webdavBasePath: draft.webdavBasePath,
        webdavMaxDepth: draft.webdavMaxDepth,
      ),
    );
  }

  Future<void> _editSource(SourceProfile source) async {
    final draft = await Navigator.of(context).push<MusicSourceConnectionDraft>(
      MaterialPageRoute(
        builder: (_) => MusicSourceConnectionPage(
          source: source,
          browseWebDavDirectories: app.browseWebDavDirectories,
        ),
      ),
    );
    if (!mounted || draft == null) return;
    await _act(
      () => app.updateConnection(
        source,
        name: draft.name,
        url: draft.url,
        password: draft.password,
        webdavBasePath: draft.webdavBasePath,
        webdavMaxDepth: draft.webdavMaxDepth,
      ),
    );
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
  void _showBlacklist() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('歌曲黑名单'),
        content: SizedBox(
          width: 450,
          height: 350,
          child: LibraryBrowser(
            app: app,
            query: const CatalogQuery(blocked: true),
            onAction: _trackAction,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _playerBar() => ListenableBuilder(
    listenable: app.appearance,
    builder: (context, _) => PlayerBar(
      app: app,
      compact: true,
      onCollapse: () => setState(() => playerCollapsed = true),
    ),
  );

  Widget _desktopPlayerBar() => ListenableBuilder(
    listenable: app.appearance,
    builder: (context, _) => PlayerBar(
      app: app,
      compact: true,
      docked: true,
      onCollapse: () => setState(() => playerCollapsed = true),
    ),
  );

  Widget _collapsedPlayerFab() {
    final player = app.playback, track = player.current;
    return FloatingActionButton(
      key: const ValueKey('collapsed-player-fab'),
      heroTag: 'collapsed-player-fab',
      tooltip: '展开播放器',
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      elevation: 4,
      shape: const CircleBorder(),
      onPressed: () => setState(() => playerCollapsed = false),
      child: track == null
          ? const Icon(Icons.headphones_rounded, size: 22)
          : PlayerCover(
              app: app,
              track: track,
              size: 48,
              circle: app.appearance.disc,
              radius: 16,
              rotate: true,
              playing: player.playing,
            ),
    );
  }
}
