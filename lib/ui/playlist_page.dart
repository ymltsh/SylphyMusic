import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';

class PlaylistPage extends StatefulWidget {
  const PlaylistPage({
    super.key,
    required this.app,
    required this.id,
    required this.buildTracks,
    required this.onEdit,
    required this.onAdd,
    required this.onCache,
  });
  final SylphyApp app;
  final String id;
  final Widget Function(List<Track>) buildTracks;
  final VoidCallback onEdit, onAdd, onCache;
  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  late Future<List<Track>> tracks = _load();
  Future<List<Track>> _load() async => [
    for (final key in await widget.app.db.playlistKeys(widget.id))
      await widget.app.db.track(TrackRef.parse(key)) ??
          Track(
            ref: TrackRef.parse(key),
            title: '不可用歌曲',
            artist: '来源已移除',
            album: '',
            missing: true,
          ),
  ];
  @override
  void initState() {
    super.initState();
    widget.app.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) {
      setState(() {
        tracks = _load();
      });
    }
  }

  @override
  void dispose() {
    widget.app.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlist = widget.app.playlists
        .where((p) => p.id == widget.id)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(playlist?.name ?? '歌单已移除'),
        actions: [
          IconButton(
            tooltip: '编辑歌单',
            onPressed:
                playlist == null || playlist.status == SyncStatus.readonly
                ? null
                : widget.onEdit,
            icon: const Icon(Icons.edit),
          ),
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
            icon: const Icon(Icons.download),
          ),
        ],
      ),
      body: FutureBuilder<List<Track>>(
        future: tracks,
        builder: (context, snapshot) => snapshot.hasData
            ? widget.buildTracks(snapshot.data!)
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
