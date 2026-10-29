import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'cache_tasks.dart';
import 'cache_storage.dart';
import 'playlist_page.dart';
import 'player_bar.dart';
import 'playback_notice.dart';
import 'capsule_toggle.dart';
import 'cover_art.dart';
import 'cover_flow.dart';
import 'library_browser.dart';
import 'track_lookup.dart';
import 'track_actions.dart';
import 'home_page.dart';
import 'search_page.dart';
import 'app_background.dart';
import 'app_identity.dart';
import 'player_cover.dart';
import 'settings_page.dart';
import 'music_sources_panel.dart';
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
  int libraryView = 0;
  bool albumCoverFlow = false;
  bool playlistCoverFlow = false;
  bool playerCollapsed = false;
  late bool _defaultPlayerFab;
  bool? onboarding;
  String? sourceFilter;
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
      unawaited(app.apiSettings.refreshQuote());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    app.removeListener(_update);
    app.playback.removeListener(_update);
    app.appearance.removeListener(_appearanceChanged);
    super.dispose();
  }

  void _appearanceChanged() {
    if (_defaultPlayerFab != app.appearance.playerFab) {
      playerCollapsed = _defaultPlayerFab = app.appearance.playerFab;
    }
    _update();
  }

  void _update() {
    if (mounted) setState(() {});
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
          ),
        ),
      ),
    );
  }

  void _library([int view = 0]) => setState(() {
    tab = 1;
    libraryView = view;
  });
  void _favorites() {
    final favorite = app.playlists
        .where((p) => p.kind == PlaylistKind.favorites)
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
          child: Stack(
            children: [
              Positioned.fill(child: _page()),
              Positioned(
                left: 12,
                right: 12,
                bottom: wide ? 16 : 8,
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
                      child: wide
                          ? SafeArea(top: false, child: _playerBar())
                          : _playerBar(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
          actions: [
            IconButton(
              tooltip: '搜索',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SearchPage(
                    app: app,
                    onAction: _trackAction,
                    initialSource: sourceFilter,
                  ),
                ),
              ),
              icon: const Icon(Icons.search),
            ),
            IconButton(
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
          ],
        ),
        body: wide
            ? Row(
                children: [
                  NavigationRail(
                    extended: MediaQuery.sizeOf(context).width > 1050,
                    backgroundColor: solidBackground
                        ? Colors.transparent
                        : null,
                    selectedIndex: tab,
                    onDestinationSelected: (v) => setState(() => tab = v),
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
            : NavigationBar(
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
                onDestinationSelected: (v) => setState(() => tab = v),
                destinations: List.generate(
                  labels.length,
                  (i) => NavigationDestination(
                    icon: Icon(icons[i]),
                    label: labels[i],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _libraryFilterBar() => Align(
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
              onChanged: (value) => setState(() => libraryView = value),
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
          if (libraryView == 1)
            IconButton(
              key: const ValueKey('album-cover-flow-toggle'),
              tooltip: albumCoverFlow ? '切换到列表' : '切换到 Cover Flow',
              isSelected: albumCoverFlow,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              onPressed: () => setState(() => albumCoverFlow = !albumCoverFlow),
              icon: const Icon(Icons.view_carousel_outlined),
              selectedIcon: const Icon(Icons.view_list_rounded),
            ),
        ],
      ),
    ),
  );

  Widget _sourceFilterControl() => PopupMenuButton<String>(
    tooltip: '音乐来源',
    icon: const Icon(Icons.filter_list),
    onSelected: (v) => setState(() => sourceFilter = v == 'all' ? null : v),
    itemBuilder: (ctx) => [
      const PopupMenuItem(value: 'all', child: Text('全部来源')),
      ...app.sources.map(
        (s) => PopupMenuItem(value: s.id, child: Text(s.name)),
      ),
    ],
  );

  Widget _sortControls() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      PopupMenuButton<String>(
        tooltip: '排序',
        icon: const Icon(Icons.sort),
        onSelected: (v) => setState(() => sort = v),
        itemBuilder: (ctx) => const [
          PopupMenuItem(value: 'name', child: Text('名称')),
          PopupMenuItem(value: 'artist', child: Text('艺术家')),
          PopupMenuItem(value: 'album', child: Text('专辑')),
          PopupMenuItem(value: 'duration', child: Text('时长')),
          PopupMenuItem(value: 'year', child: Text('年份')),
        ],
      ),
      IconButton(
        tooltip: '升序 / 降序',
        onPressed: () => setState(() => descending = !descending),
        icon: Icon(descending ? Icons.arrow_downward : Icons.arrow_upward),
      ),
    ],
  );

  Widget _page() {
    switch (tab) {
      case 0:
        return HomePage(
          app: app,
          onLibrary: _library,
          onFavorites: _favorites,
          onDownloads: _downloads,
          onSources: () => _open('音乐源管理', _sources),
          onAction: _trackAction,
        );
      case 1:
        return LibraryBrowser(
          app: app,
          query: CatalogQuery(
            view: libraryView,
            sourceId: sourceFilter,
            sort: sort,
            descending: descending,
          ),
          onAction: _trackAction,
          coverFlow: libraryView == 1 && albumCoverFlow,
          viewControls: _libraryFilterBar(),
          songActions: Row(
            mainAxisSize: MainAxisSize.min,
            children: [_sourceFilterControl(), _sortControls()],
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

  Widget _personal() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 116),
    children: [
      Card.filled(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.air_rounded, size: 40),
              const SizedBox(height: 16),
              Text('我的音乐空间', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('${app.playlists.length} 个歌单 · ${app.sources.length} 个音乐来源'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      ListTile(
        leading: const Icon(Icons.favorite_outline),
        title: const Text('我的收藏'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _favorites,
      ),
      ListTile(
        leading: const Icon(Icons.queue_music),
        title: const Text('最近播放'),
        subtitle: const Text('最近听过的 50 首歌曲'),
        onTap: () => _open('最近播放', () => ListeningHistoryPage(app: app)),
      ),
      ListTile(
        leading: const Icon(Icons.download_outlined),
        title: const Text('下载管理'),
        onTap: _downloads,
      ),
      ListTile(
        leading: const Icon(Icons.storage_outlined),
        title: const Text('缓存与存储'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CacheStoragePage(app: app)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.block_outlined),
        title: const Text('歌曲黑名单'),
        onTap: _showBlacklist,
      ),
    ],
  );

  Widget _tracks(
    List<Track> tracks, {
    bool showPlayAll = true,
    Future<void> Function(int)? onRemove,
    bool favorites = false,
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
        return ListTile(
          leading: CoverArt(app: app, track: track),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${track.artist} · ${track.album} · ${_sourceName(track.ref.sourceId)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _act(
            () => app.playback.setQueue(
              tracks.map((t) => t.ref).toList(),
              start: i - (showPlayAll ? 1 : 0),
            ),
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'remove_entry' && onRemove != null) {
                unawaited(_act(() => onRemove(i - (showPlayAll ? 1 : 0))));
              } else {
                unawaited(_trackAction(v, track));
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(value: 'favorite', child: Text('收藏 / 取消收藏')),
              const PopupMenuItem(value: 'playlist', child: Text('添加到歌单')),
              const PopupMenuItem(value: 'next', child: Text('下一首播放')),
              const PopupMenuItem(value: 'enqueue', child: Text('添加到播放队列末尾')),
              const PopupMenuItem(value: 'cache', child: Text('缓存整首歌曲')),
              if (onRemove != null)
                PopupMenuItem(
                  value: 'remove_entry',
                  child: Text(favorites ? '从收藏移除' : '从此歌单移除'),
                ),
              PopupMenuItem(
                value: 'block',
                child: Text(
                  app.blacklist.contains(track.ref.key) ? '取消屏蔽' : '加入黑名单',
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
            : LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1200
                      ? 5
                      : constraints.maxWidth >= 900
                      ? 4
                      : constraints.maxWidth >= 640
                      ? 3
                      : 2;
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 16,
                      mainAxisExtent:
                          (constraints.maxWidth - 32 - (columns - 1) * 14) /
                              columns +
                          MediaQuery.textScalerOf(context).scale(14) * 2 * 1.5 +
                          MediaQuery.textScalerOf(context).scale(12) * 2 * 1.3 +
                          16,
                    ),
                    itemCount: app.playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = app.playlists[index];
                      return PlaylistGridCard(
                        key: ValueKey('playlist/${playlist.id}'),
                        app: app,
                        playlist: playlist,
                        sourceName: _sourceName(playlist.sourceId ?? ''),
                        onOpen: () => _playlistDetails(playlist),
                        onAction: (value) => _playlistAction(value, playlist),
                      );
                    },
                  );
                },
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
          buildEntryTracks: (tracks, entryIds) => _tracks(
            tracks,
            showPlayAll: false,
            favorites: latest().kind == PlaylistKind.favorites,
            onRemove: playlistCanEdit(app, latest())
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
    onSelect: (source) => setState(() {
      sourceFilter = source.id;
      tab = 1;
      libraryView = 0;
      Navigator.pop(context);
    }),
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
        builder: (_) => MusicSourceConnectionPage(initialKind: initialKind),
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
      ),
    );
  }

  Future<void> _editSource(SourceProfile source) async {
    final draft = await Navigator.of(context).push<MusicSourceConnectionDraft>(
      MaterialPageRoute(
        builder: (_) => MusicSourceConnectionPage(source: source),
      ),
    );
    if (!mounted || draft == null) return;
    await _act(
      () => app.updateConnection(
        source,
        name: draft.name,
        url: draft.url,
        password: draft.password,
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
