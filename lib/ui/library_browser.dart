import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../data/library_catalog.dart';
import 'cover_flow.dart';
import 'cover_art.dart';

class LibraryBrowser extends StatefulWidget {
  const LibraryBrowser({
    super.key,
    required this.app,
    required this.query,
    required this.onAction,
    this.songActions,
    this.viewControls,
    this.coverFlow = false,
    this.selected,
    this.onSelection,
  });
  final SylphyApp app;
  final CatalogQuery query;
  final Future<void> Function(String, Track) onAction;
  final Widget? songActions;
  final Widget? viewControls;
  final bool coverFlow;
  final Set<String>? selected;
  final void Function(Track, bool)? onSelection;
  @override
  State<LibraryBrowser> createState() => _LibraryBrowserState();
}

class _LibraryBrowserState extends State<LibraryBrowser> {
  int revision = 0;
  late Future<CatalogPage> page;
  int generation = 0;
  final batches = <int, List<CatalogRow>>{};
  final pending = <int>{};
  final failed = <int>{};

  void _reset() {
    generation++;
    batches.clear();
    pending.clear();
    failed.clear();
    page = _load();
  }

  // Virtual rows keep only six SQL batches of metadata, even in a huge library.
  Widget _virtualRow(int index) {
    final start = index ~/ 100 * 100;
    final rows = batches.remove(start);
    if (rows != null) {
      batches[start] = rows;
      final at = index - start;
      if (at < rows.length) return _row(rows[at]);
      return const SizedBox.shrink();
    }
    if (failed.contains(start)) {
      return Center(
        child: TextButton(
          onPressed: () => setState(() {
            failed.remove(start);
            _request(start);
          }),
          child: const Text('加载失败，点击重试'),
        ),
      );
    }
    _request(start);
    return const Center(
      child: SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  void _request(int start) {
    if (!pending.add(start)) return;
    final requestedGeneration = generation;
    widget.app.catalog
        .page(widget.query, offset: start)
        .then(
          (result) {
            if (!mounted || requestedGeneration != generation) return;
            setState(() {
              pending.remove(start);
              batches[start] = result.rows;
              widget.app.metadataEnricher.prioritize(
                result.rows.map((row) => row.track),
              );
              while (batches.length > 6) {
                batches.remove(batches.keys.first);
              }
            });
          },
          onError: (Object error, StackTrace stack) {
            if (!mounted || requestedGeneration != generation) return;
            setState(() {
              pending.remove(start);
              failed.add(start);
            });
          },
        );
  }

  @override
  void initState() {
    super.initState();
    revision = widget.app.catalogRevision;
    page = _load();
    widget.app.addListener(_changed);
  }

  Future<CatalogPage> _load() async {
    final query = widget.query, requestedGeneration = generation;
    final result = await widget.app.catalog.page(query);
    if (mounted && requestedGeneration == generation) {
      batches[0] = result.rows;
      widget.app.metadataEnricher.prioritize(
        result.rows.map((row) => row.track),
      );
    }
    return result;
  }

  void _changed() {
    if (mounted && revision != widget.app.catalogRevision) {
      revision = widget.app.catalogRevision;
      setState(() {
        _reset();
      });
    }
  }

  @override
  void didUpdateWidget(covariant LibraryBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query.signature != widget.query.signature) {
      _reset();
    }
  }

  @override
  void dispose() {
    widget.app.removeListener(_changed);
    super.dispose();
  }

  CatalogRow? _coverFlowRow(int index) {
    final start = index ~/ 100 * 100;
    final rows = batches.remove(start);
    if (rows != null) {
      batches[start] = rows;
      final at = index - start;
      return at < rows.length ? rows[at] : null;
    }
    if (!failed.contains(start)) _request(start);
    return null;
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
    final refs = await widget.app.catalog.queue(widget.query.songs);
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

  Widget _coverFlowCover(BuildContext context, int index, double size) {
    final row = _coverFlowRow(index);
    if (row == null) {
      final scheme = Theme.of(context).colorScheme;
      final failedBatch = failed.contains(index ~/ 100 * 100);
      return ColoredBox(
        color: scheme.surfaceContainerHigh,
        child: Center(
          child: failedBatch
              ? Icon(Icons.refresh_rounded, color: scheme.onSurfaceVariant)
              : const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
        ),
      );
    }
    return CoverArt(
      app: widget.app,
      track: row.track,
      size: size,
      borderRadius: 8,
    );
  }

  String _coverFlowTitle(int index) {
    final row = _coverFlowRow(index);
    if (row == null) {
      return failed.contains(index ~/ 100 * 100) ? '加载失败' : '正在加载…';
    }
    return row.track.album.isEmpty ? '未知专辑' : row.track.album;
  }

  String _coverFlowSubtitle(int index) {
    final row = _coverFlowRow(index);
    if (row == null) return '';
    final artist = row.track.albumArtist.isEmpty
        ? row.track.artist
        : row.track.albumArtist;
    return '$artist · ${row.count} 首 · ${row.sources} 个来源';
  }

  void _activateCoverFlow(int index) {
    final start = index ~/ 100 * 100;
    if (failed.contains(start)) {
      setState(() => failed.remove(start));
      _request(start);
      return;
    }
    final row = _coverFlowRow(index);
    if (row != null) _group(row);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: FutureBuilder<CatalogPage>(
      future: page,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _withViewControls(
            Center(
              child: TextButton(
                onPressed: () => setState(() {
                  page = _load();
                }),
                child: const Text('读取音乐库失败，点击重试'),
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done ||
            !snapshot.hasData) {
          return _withViewControls(
            const Center(child: CircularProgressIndicator()),
          );
        }
        final result = snapshot.data!;
        final emptyMessage = widget.query.blocked
            ? '尚未屏蔽歌曲'
            : widget.query.search.isNotEmpty
            ? '没有找到匹配的音乐'
            : '暂无音乐，可以在设置中添加音乐来源或导入本地音乐。';
        return _withViewControls(
          result.total == 0
              ? Center(child: Text(emptyMessage))
              : widget.coverFlow &&
                    widget.query.view == 1 &&
                    widget.selected == null &&
                    !widget.query.blocked
              ? CoverFlowView(
                  key: const ValueKey('album-cover-flow'),
                  itemCount: result.total,
                  coverBuilder: _coverFlowCover,
                  titleBuilder: _coverFlowTitle,
                  subtitleBuilder: _coverFlowSubtitle,
                  onActivate: _activateCoverFlow,
                  bottomPadding: 84,
                  emptyMessage: emptyMessage,
                )
              : ListView.builder(
                  key: ValueKey('${widget.query.signature}:$generation'),
                  padding: const EdgeInsets.only(bottom: 96),
                  itemExtent:
                      76 * MediaQuery.textScalerOf(context).scale(14) / 14,
                  itemCount: result.total,
                  itemBuilder: (_, i) => _virtualRow(i),
                ),
          result: result,
        );
      },
    ),
  );

  Widget _withViewControls(Widget content, {CatalogPage? result}) => Column(
    children: [
      if (widget.selected == null && !widget.query.blocked)
        ListTile(
          key: const ValueKey('song-summary'),
          leading: const Tooltip(
            message: '播放全部',
            child: Icon(Icons.play_circle),
          ),
          title: Text(result == null ? '—' : '${result.total}', maxLines: 1),
          trailing: widget.songActions,
          onTap: result == null || result.total == 0 ? null : () => _act(_play),
        ),
      if (widget.viewControls != null) widget.viewControls!,
      Expanded(child: content),
    ],
  );
}
