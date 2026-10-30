import 'dart:math';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'cover_art.dart';
import 'player_bar.dart';

/// Cover-first playlist card used by the playlist grid.
class PlaylistGridCard extends StatefulWidget {
  const PlaylistGridCard({
    super.key,
    required this.app,
    required this.playlist,
    required this.sourceName,
    required this.onOpen,
    required this.onAction,
  });

  final SylphyApp app;
  final PlaylistModel playlist;
  final String sourceName;
  final VoidCallback onOpen;
  final ValueChanged<String> onAction;

  @override
  State<PlaylistGridCard> createState() => _PlaylistGridCardState();
}

class _PlaylistGridCardState extends State<PlaylistGridCard> {
  late Future<_PlaylistPreview> preview = _loadPreview();

  Future<_PlaylistPreview> _loadPreview() async {
    final info = await widget.app.db.playlistPreview(widget.playlist.id);
    final cover = info.firstKey == null
        ? null
        : await widget.app.db.track(TrackRef.parse(info.firstKey!));
    return _PlaylistPreview(count: info.count, cover: cover);
  }

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_refresh);
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      preview = _loadPreview();
    });
  }

  @override
  void didUpdateWidget(covariant PlaylistGridCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != widget.app) {
      oldWidget.app.removeListener(_refresh);
      widget.app.addListener(_refresh);
    }
    if (oldWidget.playlist.id != widget.playlist.id ||
        oldWidget.app != widget.app) {
      preview = _loadPreview();
    }
  }

  @override
  void dispose() {
    widget.app.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_PlaylistPreview>(
    future: preview,
    builder: (context, snapshot) {
      final data = snapshot.data;
      final scheme = Theme.of(context).colorScheme;
      final count = snapshot.hasError
          ? '读取失败'
          : data == null
          ? '正在读取…'
          : '${data.count} 首';
      final subtitle = widget.playlist.kind == PlaylistKind.cloud
          ? '$count · ${widget.sourceName}\n${_syncStatusLabel(widget.playlist.status)}'
                '${widget.playlist.message.isEmpty ? '' : ' · ${widget.playlist.message}'}'
          : count;

      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, constraints) => ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (data != null && data.cover != null)
                          CoverArt(
                            app: widget.app,
                            track: data.cover!,
                            size: constraints.maxWidth,
                            borderRadius: 0,
                          )
                        else
                          ColoredBox(
                            color: scheme.surfaceContainerHigh,
                            child: Center(
                              child: Icon(
                                _playlistIcon(widget.playlist.kind),
                                size: constraints.maxWidth * .34,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Material(
                            color: Colors.transparent,
                            child: PopupMenuButton<String>(
                              tooltip: '歌单操作',
                              onSelected: widget.onAction,
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                Icons.more_vert,
                                size: 21,
                                color: Colors.white,
                                shadows: [
                                  Shadow(color: Colors.black87, blurRadius: 4),
                                ],
                              ),
                              itemBuilder: (context) => playlistMenuItems(
                                widget.app,
                                widget.playlist,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  widget.playlist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _PlaylistPreview {
  const _PlaylistPreview({required this.count, required this.cover});

  final int count;
  final Track? cover;
}

/// Loads the first track's artwork for a playlist Cover Flow item.
class PlaylistCoverFlowArt extends StatefulWidget {
  const PlaylistCoverFlowArt({
    super.key,
    required this.app,
    required this.playlist,
    required this.size,
  });

  final SylphyApp app;
  final PlaylistModel playlist;
  final double size;

  @override
  State<PlaylistCoverFlowArt> createState() => _PlaylistCoverFlowArtState();
}

class _PlaylistCoverFlowArtState extends State<PlaylistCoverFlowArt> {
  late Future<Track?> cover = _loadCover();

  Future<Track?> _loadCover() async {
    final info = await widget.app.db.playlistPreview(widget.playlist.id);
    if (info.firstKey == null) return null;
    return widget.app.db.track(TrackRef.parse(info.firstKey!));
  }

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_refresh);
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => cover = _loadCover());
  }

  @override
  void didUpdateWidget(covariant PlaylistCoverFlowArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != widget.app) {
      oldWidget.app.removeListener(_refresh);
      widget.app.addListener(_refresh);
    }
    if (oldWidget.app != widget.app ||
        oldWidget.playlist.id != widget.playlist.id) {
      cover = _loadCover();
    }
  }

  @override
  void dispose() {
    widget.app.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Track?>(
    future: cover,
    builder: (context, snapshot) {
      final track = snapshot.data;
      final scheme = Theme.of(context).colorScheme;
      return SizedBox.square(
        dimension: widget.size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: track == null
              ? ColoredBox(
                  color: scheme.surfaceContainerHigh,
                  child: Center(
                    child: Icon(
                      _playlistIcon(widget.playlist.kind),
                      size: widget.size * .34,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : CoverArt(
                  app: widget.app,
                  track: track,
                  size: widget.size,
                  borderRadius: 0,
                ),
        ),
      );
    },
  );
}

IconData _playlistIcon(PlaylistKind kind) => switch (kind) {
  PlaylistKind.favorites => Icons.favorite_outline_rounded,
  PlaylistKind.local => Icons.queue_music_rounded,
  PlaylistKind.cloud => Icons.cloud_outlined,
};

String _syncStatusLabel(SyncStatus status) => switch (status) {
  SyncStatus.synced => '已同步',
  SyncStatus.pending => '等待同步',
  SyncStatus.syncing => '正在同步',
  SyncStatus.conflict => '存在冲突',
  SyncStatus.failed => '同步失败',
  SyncStatus.readonly => '只读',
};

bool playlistCanEdit(SylphyApp app, PlaylistModel playlist) {
  if (playlist.kind == PlaylistKind.favorites && playlist.sourceId != null) {
    return false;
  }
  if (playlist.kind != PlaylistKind.cloud) return true;
  final source = app.sources
      .where((s) => s.id == playlist.sourceId)
      .firstOrNull;
  return source != null &&
      source.kind.cloudPlaylistWritable &&
      playlist.status != SyncStatus.readonly &&
      playlist.status != SyncStatus.syncing;
}

List<PopupMenuEntry<String>> playlistMenuItems(
  SylphyApp app,
  PlaylistModel playlist,
) {
  final cloud = playlist.kind == PlaylistKind.cloud;
  final editable = playlistCanEdit(app, playlist);
  final source = app.sources
      .where((s) => s.id == playlist.sourceId)
      .firstOrNull;
  final online = source != null && source.enabled;
  return [
    const PopupMenuItem(value: 'cache', child: Text('缓存歌单')),
    if (playlist.kind != PlaylistKind.favorites && editable)
      const PopupMenuItem(value: 'rename', child: Text('重命名歌单')),
    if (playlist.kind != PlaylistKind.local)
      const PopupMenuItem(value: 'copy_local', child: Text('复制为本地歌单')),
    if (!cloud &&
        app.sources.any((s) => s.enabled && s.kind.cloudPlaylistWritable))
      const PopupMenuItem(value: 'copy_cloud', child: Text('复制为云端歌单')),
    if (cloud && online && playlist.status != SyncStatus.syncing)
      const PopupMenuItem(value: 'sync', child: Text('同步此云歌单')),
    if (cloud && editable && playlist.status == SyncStatus.conflict)
      const PopupMenuItem(value: 'resolve', child: Text('解决同步冲突')),
    if (playlist.kind != PlaylistKind.favorites)
      PopupMenuItem(value: 'remove', child: Text(cloud ? '从本设备移除' : '删除本地歌单')),
    if (cloud && editable && online)
      const PopupMenuItem(value: 'delete_remote', child: Text('从服务器删除（在线）')),
  ];
}

class PlaylistPage extends StatefulWidget {
  const PlaylistPage({
    super.key,
    required this.app,
    required this.id,
    required this.buildTracks,
    required this.onEdit,
    required this.onAdd,
    required this.onCache,
    this.buildEntryTracks,
    this.onAction,
  });

  final SylphyApp app;
  final String id;
  final Widget Function(List<Track>) buildTracks;
  final Widget Function(List<Track>, List<String>)? buildEntryTracks;
  final ValueChanged<String>? onAction;
  final VoidCallback onEdit, onAdd, onCache;

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  late Future<({List<Track> tracks, List<String> entryIds})> tracks = _load();
  bool starting = false;

  Future<({List<Track> tracks, List<String> entryIds})> _load() async {
    final entries = await widget.app.db.playlistEntries(widget.id);
    final items = <Track>[];
    for (final entry in entries) {
      items.add(
        await widget.app.db.track(TrackRef.parse(entry.key)) ??
            Track(
              ref: TrackRef.parse(entry.key),
              title: '不可用歌曲',
              artist: '来源已移除',
              album: '',
              missing: true,
            ),
      );
    }
    return (tracks: items, entryIds: entries.map((e) => e.id).toList());
  }

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant PlaylistPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != widget.app) {
      oldWidget.app.removeListener(_refresh);
      widget.app.addListener(_refresh);
    }
    if (oldWidget.id != widget.id || oldWidget.app != widget.app) {
      tracks = _load();
    }
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      tracks = _load();
    });
  }

  @override
  void dispose() {
    widget.app.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _startPlayback(List<Track> items, {bool shuffle = false}) async {
    if (starting || items.isEmpty) return;
    setState(() => starting = true);
    try {
      await widget.app.playback.setPlaybackMode(
        shuffle ? PlaybackMode.shuffle : PlaybackMode.listLoop,
      );
      await widget.app.playback.setQueue(
        items.map((track) => track.ref).toList(),
        start: shuffle ? Random().nextInt(items.length) : 0,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法开始播放，请重试')));
      }
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  Widget _cover(List<Track> items, double size) {
    final scheme = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: scheme.surfaceContainerHigh,
          child: Center(
            child: Icon(
              Icons.queue_music_rounded,
              size: size * .34,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return CoverArt(
      app: widget.app,
      track: items.first,
      size: size,
      borderRadius: 12,
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlist = widget.app.playlists
        .where((item) => item.id == widget.id)
        .firstOrNull;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('歌单详情'),
        actions: [
          if (playlist != null && playlistCanEdit(widget.app, playlist))
            IconButton(
              tooltip: '编辑歌单',
              onPressed:
                  playlist == null || playlist.status == SyncStatus.readonly
                  ? null
                  : widget.onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
          if (playlist != null && playlistCanEdit(widget.app, playlist))
            IconButton(
              tooltip: '添加歌曲',
              onPressed:
                  playlist == null || playlist.status == SyncStatus.readonly
                  ? null
                  : widget.onAdd,
              icon: const Icon(Icons.playlist_add),
            ),
          IconButton(
            tooltip: '缓存歌单',
            onPressed: playlist == null ? null : widget.onCache,
            icon: const Icon(Icons.download_outlined),
          ),
          if (playlist != null && widget.onAction != null)
            PopupMenuButton<String>(
              tooltip: '歌单操作',
              onSelected: widget.onAction,
              itemBuilder: (_) => playlistMenuItems(widget.app, playlist),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: FutureBuilder<({List<Track> tracks, List<String> entryIds})>(
          future: tracks,
          builder: (context, snapshot) {
            if (playlist == null) return const Center(child: Text('歌单已移除'));
            if (snapshot.hasError) {
              return Center(
                child: TextButton(
                  onPressed: _refresh,
                  child: const Text('读取歌单失败，点击重试'),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snapshot.data!.tracks;
            return NestedScrollView(
              headerSliverBuilder: (context, innerScrolled) => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final coverSize = (constraints.maxWidth * .42).clamp(
                          100.0,
                          220.0,
                        );
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox.square(
                              dimension: coverSize,
                              child: _cover(items, coverSize),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Tooltip(
                                    message: playlist.name,
                                    child: Text(
                                      playlist.name,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${items.length} 首歌曲${playlist.kind == PlaylistKind.cloud ? ' · 云端' : ''}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                  if (playlist.kind == PlaylistKind.cloud)
                                    Text(
                                      '${_syncStatusLabel(playlist.status)}${playlist.message.isEmpty ? '' : ' · ${playlist.message}'}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      IconButton.filledTonal(
                                        tooltip: '随机播放歌单',
                                        onPressed: items.isEmpty || starting
                                            ? null
                                            : () => _startPlayback(
                                                items,
                                                shuffle: true,
                                              ),
                                        icon: const Icon(Icons.shuffle_rounded),
                                      ),
                                      FilledButton.icon(
                                        key: const ValueKey('playlist-play'),
                                        onPressed: items.isEmpty || starting
                                            ? null
                                            : () => _startPlayback(items),
                                        icon: const Icon(
                                          Icons.play_arrow_rounded,
                                        ),
                                        label: const Text('播放'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Row(
                      children: [
                        Text(
                          '歌曲',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        Text(
                          '${items.length} 首',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              body: items.isEmpty
                  ? const Center(child: Text('这个歌单暂无歌曲'))
                  : widget.buildEntryTracks?.call(
                          items,
                          snapshot.data!.entryIds,
                        ) ??
                        widget.buildTracks(items),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: ListenableBuilder(
            listenable: Listenable.merge([
              widget.app.playback,
              widget.app.appearance,
            ]),
            builder: (context, _) => PlayerBar(app: widget.app, compact: true),
          ),
        ),
      ),
    );
  }
}
