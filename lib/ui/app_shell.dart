import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'cache_tasks.dart';
import 'cache_storage.dart';
import 'playlist_page.dart';
import 'player_bar.dart';
import 'playback_notice.dart';
import 'cover_art.dart';
import 'library_browser.dart';
import 'track_lookup.dart';
import 'home_page.dart';
import 'search_page.dart';
import 'app_background.dart';
import 'app_identity.dart';
import 'player_cover.dart';
import 'settings_page.dart';
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
  bool playerCollapsed = false;
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
    unawaited(_loadWelcome());
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    app.diagnostics.record('app', 'lifecycle', details: {'state': state.name});
    if (state == AppLifecycleState.resumed) unawaited(app.refreshIfStale());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    app.removeListener(_update);
    app.playback.removeListener(_update);
    super.dispose();
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
                backgroundColor: solidBackground
                    ? Colors.transparent
                    : customBackground
                    ? scheme.surfaceContainer.withValues(alpha: .90)
                    : null,
                surfaceTintColor: solidBackground ? Colors.transparent : null,
                height: 54,
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

  Widget _libraryFilterBar() {
    final scheme = Theme.of(context).colorScheme;
    Widget chip(int value, String label, IconData icon) {
      final selected = libraryView == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          key: ValueKey('library-filter-$value'),
          selected: selected,
          onSelected: (_) => setState(() => libraryView = value),
          showCheckmark: false,
          avatar: Icon(
            icon,
            size: 16,
            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
          ),
          label: Text(label),
          labelStyle: TextStyle(
            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          backgroundColor: scheme.surfaceContainerHighest.withValues(
            alpha: .72,
          ),
          selectedColor: scheme.primary,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    return Align(
      key: const ValueKey('library-filter-bar'),
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              chip(0, '歌曲', Icons.music_note_outlined),
              chip(1, '专辑', Icons.album_outlined),
              chip(2, '艺术家', Icons.person_outline),
            ],
          ),
        ),
      ),
    );
  }

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

  Widget _welcome() => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(28),
            children: [
              Icon(
                Icons.air_rounded,
                size: 76,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                '让音乐，轻盈相随',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                '欢迎使用风灵音乐\n连接私人音乐库，收藏喜欢的声音，离线也能自在聆听。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              const ListTile(
                leading: Icon(Icons.link),
                title: Text('01  连接音乐来源'),
                subtitle: Text('Emby · Navidrome / OpenSubsonic · WebDAV'),
              ),
              FilledButton.icon(
                onPressed: app.busy
                    ? null
                    : () async {
                        await _addSource();
                        if (app.sources.isNotEmpty) await _finishWelcome();
                      },
                icon: const Icon(Icons.add_link),
                label: const Text('连接我的音乐库'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: app.busy
                    ? null
                    : () async {
                        await _act(app.importLocalFiles);
                        if (app.sources.isNotEmpty) await _finishWelcome();
                      },
                icon: const Icon(Icons.folder_open),
                label: const Text('导入本地音乐'),
              ),
              if (app.busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const Text('正在验证连接并初始化音乐库…', textAlign: TextAlign.center),
              ],
              const SizedBox(height: 12),
              TextButton(
                onPressed: app.busy ? null : _finishWelcome,
                child: const Text('稍后设置，先进入首页'),
              ),
              const Text(
                '以后可在右上角「设置 → 音乐源管理」中继续添加。',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
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

  Widget _tracks(List<Track> tracks, {bool showPlayAll = true}) {
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
            onSelected: (v) => _trackAction(v, track),
            itemBuilder: (ctx) => [
              PopupMenuItem(value: 'favorite', child: Text('收藏 / 取消收藏')),
              const PopupMenuItem(value: 'playlist', child: Text('添加到歌单')),
              const PopupMenuItem(value: 'next', child: Text('下一首播放')),
              const PopupMenuItem(value: 'enqueue', child: Text('添加到播放队列末尾')),
              const PopupMenuItem(value: 'cache', child: Text('缓存整首歌曲')),
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

  Future<void> _trackAction(String action, Track track) async {
    if (action == 'favorite') {
      await _act(() => app.toggleFavorite(track));
    }
    if (action == 'cache') {
      await _act(() => app.cacheTrack(track));
    }
    if (action == 'next') {
      await _act(() => app.playback.enqueue(track.ref, next: true));
    }
    if (action == 'enqueue') {
      await _act(() => app.playback.enqueue(track.ref));
    }
    if (action == 'block') {
      await _act(() => app.toggleBlacklist(track));
    }
    if (action == 'playlist') await _choosePlaylist(track);
  }

  Future<void> _choosePlaylist(Track track) async {
    final candidates = app.playlists
        .where(
          (p) =>
              p.kind != PlaylistKind.cloud || p.sourceId == track.ref.sourceId,
        )
        .toList();
    final chosen = await showDialog<PlaylistModel>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('添加到歌单'),
        children: candidates
            .map(
              (p) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, p),
                child: Text(
                  '${p.name}${p.kind == PlaylistKind.cloud ? ' · 云端' : ''}',
                ),
              ),
            )
            .toList(),
      ),
    );
    if (chosen == null) return;
    await _act(() async {
      final keys = await app.db.playlistKeys(chosen.id);
      keys.add(track.ref.key);
      await app.setPlaylistKeys(chosen, keys);
    });
  }

  Widget _playlists() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '我的歌单',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
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
            FilledButton.icon(
              onPressed: _newPlaylist,
              icon: const Icon(Icons.add),
              label: const Text('新建歌单'),
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
                      .where((s) => s.enabled && s.kind.cloudPlaylists)
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
              .where((s) => s.enabled && s.kind.cloudPlaylists)
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

  Widget _sources() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: app.busy ? null : () => _act(app.syncAll),
              icon: const Icon(Icons.sync),
              label: const Text('同步所有来源'),
            ),
            FilledButton.icon(
              onPressed: _addSource,
              icon: const Icon(Icons.add),
              label: const Text('添加服务器'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _act(app.importLocalFiles),
              icon: const Icon(Icons.folder_open),
              label: const Text('导入本地文件'),
            ),
            OutlinedButton.icon(
              onPressed: () => _act(app.importLocalFolder),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('添加音乐文件夹'),
            ),
          ],
        ),
      ),
      Expanded(
        child: ListView(
          children: app.sources
              .map(
                (s) => ListTile(
                  leading: Icon(
                    s.kind == SourceKind.emby
                        ? Icons.storage
                        : s.kind == SourceKind.subsonic ||
                              s.kind == SourceKind.webdav
                        ? Icons.cloud
                        : Icons.folder,
                  ),
                  title: Text(s.name),
                  onTap: () => setState(() {
                    sourceFilter = s.id;
                    tab = 1;
                    libraryView = 0;
                    Navigator.pop(context);
                  }),
                  subtitle: Text(
                    s.kind == SourceKind.local
                        ? '本地音乐'
                        : '${s.url}${s.url.startsWith('http:') ? ' · 未加密' : ''}'
                              '${app.index.progress[s.id] == null ? '' : '\n${app.index.progress[s.id]!.message}'}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'sync') {
                        await _act(() => app.syncSource(s));
                      }
                      if (v == 'cancel_sync') app.index.cancel(s.id);
                      if (v == 'edit') await _editSource(s);
                      if (v == 'scan') await _act(() => app.rescanLocal(s));
                      if (v == 'delete' &&
                          await _confirm(
                            '删除 ${s.name} 及本机管理的相关数据？不会删除服务器上的音乐。',
                          )) {
                        await _act(() => app.deleteSource(s));
                      }
                      if (v == 'cache') {
                        await _act(() => app.clearCache(sourceId: s.id));
                      }
                      if (v == 'toggle') {
                        await _act(() => app.toggleSource(s));
                      }
                    },
                    itemBuilder: (ctx) => [
                      if (app.index.progress[s.id]?.state == 'reading')
                        const PopupMenuItem(
                          value: 'cancel_sync',
                          child: Text('取消索引同步'),
                        ),
                      if (s.kind != SourceKind.local)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('编辑连接 / 重新登录'),
                        ),
                      if (s.kind == SourceKind.local && s.url != 'file:///')
                        const PopupMenuItem(
                          value: 'scan',
                          child: Text('重新扫描文件夹'),
                        ),
                      if (s.kind != SourceKind.local)
                        const PopupMenuItem(
                          value: 'sync',
                          child: Text('同步此来源'),
                        ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(s.enabled ? '停用来源' : '重新启用'),
                      ),
                      const PopupMenuItem(
                        value: 'cache',
                        child: Text('清除此来源缓存'),
                      ),
                      const PopupMenuItem(value: 'delete', child: Text('删除来源')),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    ],
  );
  Future<void> _addSource() async {
    final name = TextEditingController(),
        url = TextEditingController(),
        username = TextEditingController(),
        password = TextEditingController();
    var kind = SourceKind.emby;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: const Text('添加服务器连接'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<SourceKind>(
                  initialValue: kind,
                  items: const [
                    DropdownMenuItem(
                      value: SourceKind.emby,
                      child: Text('Emby'),
                    ),
                    DropdownMenuItem(
                      value: SourceKind.subsonic,
                      child: Text('Navidrome / OpenSubsonic'),
                    ),
                    DropdownMenuItem(
                      value: SourceKind.webdav,
                      child: Text('WebDAV'),
                    ),
                  ],
                  onChanged: (v) => refresh(() => kind = v ?? SourceKind.emby),
                ),
                if (kind == SourceKind.webdav)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '递归读取音乐目录；支持本地歌单、同名 .lrc / .txt 歌词及 cover / folder 封面。',
                    ),
                  ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '连接名称'),
                ),
                TextField(
                  controller: url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: '服务器 URL（包含反向代理路径）',
                  ),
                ),
                TextField(
                  controller: username,
                  decoration: const InputDecoration(labelText: '用户名'),
                ),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码'),
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
              child: const Text('连接并同步'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      await _act(
        () => app.addSource(
          kind: kind,
          name: name.text.trim(),
          url: url.text.trim(),
          username: username.text.trim(),
          password: password.text,
        ),
      );
    }
    name.dispose();
    url.dispose();
    username.dispose();
    password.dispose();
  }

  Future<void> _editSource(SourceProfile source) async {
    final name = TextEditingController(text: source.name),
        url = TextEditingController(text: source.url),
        password = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('更新来源连接'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('账号：${source.username}'),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '连接名称'),
              ),
              TextField(
                controller: url,
                decoration: const InputDecoration(labelText: '服务器 URL'),
              ),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: '重新验证密码'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('验证并保存'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await _act(
        () => app.updateConnection(
          source,
          name: name.text,
          url: url.text,
          password: password.text,
        ),
      );
    }
    name.dispose();
    url.dispose();
    password.dispose();
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
      backgroundColor: const Color(0xff0d0d10),
      foregroundColor: Colors.white,
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
