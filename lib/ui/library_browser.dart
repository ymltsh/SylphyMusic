import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../data/library_catalog.dart';
import 'cover_art.dart';

class LibraryBrowser extends StatefulWidget {
  const LibraryBrowser({
    super.key,
    required this.app,
    required this.query,
    required this.onAction,
    this.selected,
    this.onSelection,
  });
  final SylphyApp app;
  final CatalogQuery query;
  final Future<void> Function(String, Track) onAction;
  final Set<String>? selected;
  final void Function(Track, bool)? onSelection;
  @override
  State<LibraryBrowser> createState() => _LibraryBrowserState();
}

class _LibraryBrowserState extends State<LibraryBrowser> {
  int offset = 0, revision = 0;
  late Future<CatalogPage> page;
  @override
  void initState() {
    super.initState();
    revision = widget.app.catalogRevision;
    page = _load();
    widget.app.addListener(_changed);
  }

  Future<CatalogPage> _load() async {
    final query = widget.query, requestedOffset = offset;
    final result = await widget.app.catalog.page(
      query,
      offset: requestedOffset,
    );
    if (query.signature != widget.query.signature ||
        requestedOffset != offset) {
      return result;
    }
    if (result.total > 0 && offset >= result.total) {
      offset = (result.total - 1) ~/ 100 * 100;
      return widget.app.catalog.page(widget.query, offset: offset);
    }
    return result;
  }

  void _changed() {
    if (mounted && revision != widget.app.catalogRevision) {
      revision = widget.app.catalogRevision;
      setState(() {
        page = _load();
      });
    }
  }

  @override
  void didUpdateWidget(covariant LibraryBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query.signature != widget.query.signature) {
      offset = 0;
      page = _load();
    }
  }

  @override
  void dispose() {
    widget.app.removeListener(_changed);
    super.dispose();
  }

  Future<void> _act(Future<void> Function() work) async {
    try {
      await work();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  String _source(Track track) =>
      widget.app.sources
          .where((s) => s.id == track.ref.sourceId)
          .firstOrNull
          ?.name ??
      '来源已移除';
  Future<void> _play([Track? track]) async {
    final refs = await widget.app.catalog.queue(widget.query);
    final start = track == null ? 0 : refs.indexOf(track.ref);
    if (start < 0) throw StateError('音乐库已变更，请重新选择歌曲');
    await widget.app.playback.setQueue(refs, start: start);
  }

  void _group(CatalogRow row) {
    final album = widget.query.view == 1;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(album ? row.track.album : row.track.artist),
          ),
          body: LibraryBrowser(
            app: widget.app,
            query: widget.query.songsIn(album ? 'album' : 'artist', row.key),
            onAction: widget.onAction,
          ),
        ),
      ),
    );
  }

  Widget _row(CatalogRow row) {
    final track = row.track;
    if (widget.selected != null) {
      return CheckboxListTile(
        title: Text(track.title),
        subtitle: Text(track.artist),
        value: widget.selected!.contains(track.ref.key),
        onChanged: (v) => widget.onSelection?.call(track, v == true),
      );
    }
    final album = widget.query.view == 1, grouped = widget.query.view != 0;
    return ListTile(
      leading: widget.query.view == 2
          ? const Icon(Icons.person_outline)
          : CoverArt(app: widget.app, track: track),
      title: Text(
        album
            ? (track.album.isEmpty ? '未知专辑' : track.album)
            : widget.query.view == 2
            ? track.artist
            : track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        grouped
            ? '${album ? '${track.albumArtist.isEmpty ? track.artist : track.albumArtist} · ' : ''}${row.count} 首 · ${row.sources} 个来源'
            : '${track.artist} · ${track.album} · ${_source(track)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: widget.query.blocked
          ? null
          : grouped
          ? () => _group(row)
          : () => _act(() => _play(track)),
      trailing: grouped
          ? null
          : widget.query.blocked
          ? IconButton(
              tooltip: '取消屏蔽',
              icon: const Icon(Icons.restore),
              onPressed: () => _act(() => widget.onAction('block', track)),
            )
          : PopupMenuButton<String>(
              onSelected: (v) => _act(() => widget.onAction(v, track)),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'favorite', child: Text('收藏 / 取消收藏')),
                PopupMenuItem(value: 'playlist', child: Text('添加到歌单')),
                PopupMenuItem(value: 'next', child: Text('下一首播放')),
                PopupMenuItem(value: 'enqueue', child: Text('添加到播放队列末尾')),
                PopupMenuItem(value: 'cache', child: Text('缓存整首歌曲')),
                PopupMenuItem(value: 'block', child: Text('加入黑名单')),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CatalogPage>(
    future: page,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: TextButton(
            onPressed: () => setState(() {
              page = _load();
            }),
            child: const Text('读取音乐库失败，点击重试'),
          ),
        );
      }
      if (snapshot.connectionState != ConnectionState.done ||
          !snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final result = snapshot.data!;
      if (result.total == 0) {
        return Center(
          child: Text(
            widget.query.blocked ? '尚未屏蔽歌曲' : '暂无音乐。可以先添加 Emby 或 Navidrome 来源。',
          ),
        );
      }
      final playAll =
          widget.query.view == 0 &&
          widget.selected == null &&
          !widget.query.blocked;
      return Column(
        children: [
          if (playAll)
            ListTile(
              leading: const Icon(Icons.play_circle),
              title: Text('播放全部 · ${result.total} 首'),
              onTap: () => _act(_play),
            ),
          Expanded(
            child: ListView.builder(
              key: ValueKey('${widget.query.signature}:$offset'),
              itemCount: result.rows.length,
              itemBuilder: (_, i) => _row(result.rows[i]),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '上一页',
                onPressed: offset == 0
                    ? null
                    : () => setState(() {
                        offset -= 100;
                        page = _load();
                      }),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                '${offset + 1}–${offset + result.rows.length} / ${result.total}',
              ),
              IconButton(
                tooltip: '下一页',
                onPressed: offset + result.rows.length >= result.total
                    ? null
                    : () => setState(() {
                        offset += 100;
                        page = _load();
                      }),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      );
    },
  );
}
