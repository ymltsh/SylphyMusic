import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../data/library_catalog.dart';
import 'batch_selection.dart';
import 'cover_flow.dart';
import 'cover_art.dart';
import 'design_system/adaptive_collapsing_chrome.dart';
import 'design_system/miuix_adaptive.dart';
import 'playing_song_tile.dart';
import 'route_player_bar.dart';
import 'wide_card_ratio.dart';

/// Space after the final item. The floating dock is allowed to overlay rows
/// while scrolling, but the last song must scroll completely above it.
/// The shell passes its floating dock reserve as [overlayPadding].
@visibleForTesting
double libraryListBottomPadding({
  required double viewportWidth,
  double? basePadding,
  required double overlayPadding,
}) => (basePadding ?? (viewportWidth > 750 ? 24.0 : 96.0)) + overlayPadding;

/// Actions are produced by the existing LibraryBrowser State. The collapsed
/// menu only forwards them, keeping paging and playback in one place.
class LibraryCollapsedActions {
  const LibraryCollapsedActions({
    required this.total,
    required this.countUnit,
    required this.playAll,
    required this.locateCurrent,
    required this.batchActive,
    required this.selectionCount,
    required this.allSelected,
    required this.exitSelection,
    required this.toggleSelectAll,
  });

  final int? total;
  final String countUnit;
  final VoidCallback? playAll;
  final VoidCallback? locateCurrent;
  final bool batchActive;
  final int selectionCount;
  final bool allSelected;
  final VoidCallback? exitSelection;
  final VoidCallback? toggleSelectAll;
}

class LibraryBrowser extends StatefulWidget {
  const LibraryBrowser({
    super.key,
    required this.app,
    required this.query,
    required this.onAction,
    this.songActions,
    this.viewControls,
    this.compactToolbar = false,
    this.drawBehindHeader = false,
    this.onToolbarActionsChanged,
    this.coverFlow = false,
    this.bottomPadding,
    this.bottomOverlayPadding = 0,
    this.batchSelection,
    this.selected,
    this.onSelection,
  });
  final SylphyApp app;
  final CatalogQuery query;
  final Future<void> Function(String, Track) onAction;
  final Widget? songActions;
  final Widget? viewControls;
  final bool compactToolbar;
  final bool drawBehindHeader;
  final ValueChanged<LibraryCollapsedActions>? onToolbarActionsChanged;
  final bool coverFlow;

  /// Space owned by an overlay; a docked route player needs no extra reserve.
  final double? bottomPadding;
  final double bottomOverlayPadding;
  final BatchSelection? batchSelection;
  final Set<String>? selected;
  final void Function(Track, bool)? onSelection;
  @override
  State<LibraryBrowser> createState() => _LibraryBrowserState();
}

class _LibraryBrowserState extends State<LibraryBrowser> {
  bool get _toolbarFolded =>
      widget.compactToolbar && widget.selected == null && !widget.query.blocked;

  double get _headerPadding =>
      widget.drawBehindHeader ? MediaQuery.paddingOf(context).top : 0;

  int revision = 0;
  late Future<CatalogPage> page;
  int generation = 0;
  int _catalogRefreshEpoch = 0;
  final batches = <int, List<CatalogRow>>{};
  final pending = <int>{};
  final failed = <int>{};
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: false,
  );

  // A hard reset is appropriate only when the user's query actually changes.
  void _reset() {
    generation++;
    _catalogRefreshEpoch++;
    batches.clear();
    pending.clear();
    failed.clear();
    page = _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  // Metadata/index updates refresh the currently cached SQL pages in place.
  // Neither the ScrollController nor ListView key changes during this refresh.
  Future<void> _refreshCatalog() async {
    final refresh = ++_catalogRefreshEpoch;
    final requestedGeneration = generation;
    final signature = widget.query.signature;
    final cachedOffsets = batches.keys.where((offset) => offset != 0).toList();
    // Older in-flight page requests must not overwrite the new rows.
    pending.clear();
    try {
      final latest = await Future.wait([
        widget.app.catalog.page(widget.query),
        for (final offset in cachedOffsets)
          widget.app.catalog.page(widget.query, offset: offset),
      ]);
      if (!mounted ||
          refresh != _catalogRefreshEpoch ||
          requestedGeneration != generation ||
          signature != widget.query.signature) {
        return;
      }
      setState(() {
        // SynchronousFuture avoids a loading frame between refreshed snapshots.
        page = SynchronousFuture(latest.first);
        batches.clear();
        batches[0] = latest.first.rows;
        for (var index = 0; index < cachedOffsets.length; index++) {
          final offset = cachedOffsets[index];
          if (offset < latest.first.total) {
            batches[offset] = latest[index + 1].rows;
          }
        }
        while (batches.length > 6) {
          batches.remove(batches.keys.first);
        }
        failed.removeWhere((offset) => offset >= latest.first.total);
      });
    } catch (_) {
      // Keep existing rows and scroll position on a transient SQL failure.
    }
  }

  double get _rowExtent =>
      (MediaQuery.sizeOf(context).width > 750 ? 64 : 76) *
      MediaQuery.textScalerOf(context).scale(14) /
      14;

  // Virtual rows keep only six SQL batches of metadata, even in a huge library.
  Widget _virtualRow(int index) {
    final start = index ~/ 100 * 100;
    final rows = batches.remove(start);
    if (rows != null) {
      batches[start] = rows;
      final at = index - start;
      if (at < rows.length) {
        final tile = _row(rows[at]);
        // Each scrolling group owns and clips its own ink. Drawing on the
        // Scaffold material can leave a wide highlight between visible rows.
        return widget.query.view == 0
            ? tile
            : Material(
                type: MaterialType.transparency,
                clipBehavior: Clip.hardEdge,
                child: tile,
              );
      }
      return const SizedBox.shrink();
    }
    if (failed.contains(start)) {
      return SizedBox(
        height: _rowExtent,
        child: Center(
          child: TextButton(
            onPressed: () => setState(() {
              failed.remove(start);
              _request(start);
            }),
            child: const Text('加载失败，点击重试'),
          ),
        ),
      );
    }
    _request(start);
    return SizedBox(
      height: _rowExtent,
      child: const Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  void _request(int start) {
    if (!pending.add(start)) return;
    final requestedGeneration = generation;
    final requestedRefresh = _catalogRefreshEpoch;
    widget.app.catalog
        .page(widget.query, offset: start)
        .then(
          (result) {
            if (!mounted ||
                requestedGeneration != generation ||
                requestedRefresh != _catalogRefreshEpoch) {
              return;
            }
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
            if (!mounted ||
                requestedGeneration != generation ||
                requestedRefresh != _catalogRefreshEpoch) {
              return;
            }
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
    widget.app.catalogListenable.addListener(_changed);
  }

  Future<CatalogPage> _load() async {
    final query = widget.query, requestedGeneration = generation;
    final requestedRefresh = _catalogRefreshEpoch;
    final result = await widget.app.catalog.page(query);
    if (mounted &&
        requestedGeneration == generation &&
        requestedRefresh == _catalogRefreshEpoch) {
      batches[0] = result.rows;
      widget.app.metadataEnricher.prioritize(
        result.rows.map((row) => row.track),
      );
    }
    return result;
  }

  void _changed() {
    if (!mounted || revision == widget.app.catalogRevision) return;
    revision = widget.app.catalogRevision;
    unawaited(_refreshCatalog());
  }

  @override
  void didUpdateWidget(covariant LibraryBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.app, widget.app)) {
      oldWidget.app.catalogListenable.removeListener(_changed);
      widget.app.catalogListenable.addListener(_changed);
      revision = widget.app.catalogRevision;
      _reset();
    } else if (oldWidget.query.signature != widget.query.signature) {
      _reset();
    }
  }

  @override
  void dispose() {
    widget.app.catalogListenable.removeListener(_changed);
    _scrollController.dispose();
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
  Future<void> _locateCurrentTrack() async {
    final current = widget.app.playback.currentRef;
    if (current == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前没有播放歌曲')));
      return;
    }

    final signature = widget.query.signature;
    // Fetch only ordered identities, not the whole catalog's metadata.
    final refs = await widget.app.catalog.queue(widget.query.songs);
    if (!mounted || signature != widget.query.signature) return;

    final index = refs.indexOf(current);
    if (index < 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前歌曲不在此音乐库筛选结果中')));
      return;
    }
    if (!_scrollController.hasClients) return;

    final extent =
        (MediaQuery.sizeOf(context).width > 750 ? 64 : 76) *
        MediaQuery.textScalerOf(context).scale(14) /
        14;
    final position = _scrollController.position;
    final contentOffset =
        index * extent + (_toolbarFolded ? _headerPadding : 0);
    final offset = (contentOffset - (position.viewportDimension - extent) / 2)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    await _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _play([Track? track]) async {
    final refs = await widget.app.catalog.queue(widget.query.songs);
    final start = track == null ? 0 : refs.indexOf(track.ref);
    if (start < 0) throw StateError('音乐库已变更，请重新选择歌曲');
    await widget.app.playback.setQueue(refs, start: start);
  }

  void _group(CatalogRow row) {
    final album = widget.query.view == 1;
    final folder = widget.query.view == 3 && row.isFolder;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: sylphyGradientAppBar(
            title: Text(
              folder
                  ? row.folderTitle
                  : album
                  ? row.track.album
                  : row.track.artist,
            ),
          ),
          extendBody: true,
          bottomNavigationBar: RoutePlayerBar(app: widget.app),
          body: Column(
            children: [
              if (folder)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_source(row.track)} · ${row.folderLocation}',
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              Expanded(
                child: Builder(
                  builder: (context) => LibraryBrowser(
                    app: widget.app,
                    query: folder
                        ? widget.query.folderIn(row.key)
                        : widget.query.songsIn(widget.query.groupType, row.key),
                    bottomPadding: folder ? 12 : 16,
                    bottomOverlayPadding: MediaQuery.paddingOf(context).bottom,
                    onAction: widget.onAction,
                  ),
                ),
              ),
            ],
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
    final folder = widget.query.view == 3 && row.isFolder;
    final album = widget.query.view == 1;
    final artist = widget.query.view == 2;
    final grouped = album || artist || folder;
    final batch = widget.batchSelection;
    final batchKey = grouped ? row.key : track.ref.key;
    final selecting = batch?.active == true;
    if (!grouped && !widget.query.blocked) {
      return PlayingSongTile(
        app: widget.app,
        track: track,
        title: track.title,
        subtitle: '${track.artist} · ${track.album} · ${_source(track)}',
        contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 16),
        selectedInBatch: selecting && batch!.contains(batchKey),
        onLongPress: batch == null ? null : () => batch.begin(batchKey),
        onTap: selecting
            ? () => batch!.toggle(batchKey)
            : () => _act(() => _play(track)),
        trailing: SizedBox.square(
          dimension: 48,
          child: selecting
              ? Checkbox(
                  value: batch!.contains(batchKey),
                  onChanged: (_) => batch.toggle(batchKey),
                )
              : PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'multi_select' && batch != null) {
                      batch.begin(batchKey);
                    } else {
                      _act(() => widget.onAction(v, track));
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'multi_select', child: Text('多选')),
                    PopupMenuItem(value: 'favorite', child: Text('收藏 / 取消收藏')),
                    PopupMenuItem(value: 'playlist', child: Text('添加到歌单')),
                    PopupMenuItem(value: 'next', child: Text('下一首播放')),
                    PopupMenuItem(value: 'enqueue', child: Text('添加到播放队列')),
                    PopupMenuItem(value: 'cache', child: Text('缓存整首歌曲')),
                    PopupMenuItem(value: 'block', child: Text('加入黑名单')),
                  ],
                ),
        ),
      );
    }
    return ListTile(
      selected: selecting && batch!.contains(batchKey),
      onLongPress: batch == null || widget.query.blocked
          ? null
          : () => batch.begin(batchKey),
      leading: folder
          ? const Icon(Icons.folder_outlined)
          : artist
          ? CoverArt(
              app: widget.app,
              track: row.portraitTrack,
              artist: true,
              borderRadius: 24,
            )
          : CoverArt(app: widget.app, track: track),
      title: Text(
        folder
            ? row.folderTitle
            : album
            ? (track.album.isEmpty ? '未知专辑' : track.album)
            : widget.query.view == 2
            ? track.artist
            : track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        folder
            ? '${_source(track)} · ${row.count} 首'
            : grouped
            ? '${album ? '${track.albumArtist.isEmpty ? track.artist : track.albumArtist} · ' : ''}${row.count} 首 · ${row.sources} 个来源'
            : '${track.artist} · ${track.album} · ${_source(track)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: widget.query.blocked
          ? null
          : selecting
          ? () => batch!.toggle(batchKey)
          : grouped
          ? () => _group(row)
          : () => _act(() => _play(track)),
      trailing: selecting
          ? SizedBox.square(
              dimension: 48,
              child: Checkbox(
                value: batch!.contains(batchKey),
                onChanged: (_) => batch.toggle(batchKey),
              ),
            )
          : grouped
          ? const Icon(Icons.chevron_right_rounded)
          : widget.query.blocked
          ? IconButton(
              tooltip: '取消屏蔽',
              icon: const Icon(Icons.restore),
              onPressed: () => _act(() => widget.onAction('block', track)),
            )
          : PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'multi_select' && batch != null) {
                  batch.begin(batchKey);
                } else {
                  _act(() => widget.onAction(v, track));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'multi_select', child: Text('多选')),
                PopupMenuItem(value: 'favorite', child: Text('收藏 / 取消收藏')),
                PopupMenuItem(value: 'playlist', child: Text('添加到歌单')),
                PopupMenuItem(value: 'next', child: Text('下一首播放')),
                PopupMenuItem(value: 'enqueue', child: Text('添加到播放队列')),
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
    bottom: widget.bottomOverlayPadding == 0,
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
        final showCoverFlow =
            widget.coverFlow &&
            widget.query.view == 1 &&
            widget.selected == null &&
            !widget.query.blocked;
        final listBehindHeader =
            _toolbarFolded && result.total > 0 && !showCoverFlow;
        final emptyMessage = widget.query.blocked
            ? '尚未屏蔽歌曲'
            : widget.query.search.isNotEmpty
            ? '没有找到匹配的音乐'
            : '暂无音乐，可以在设置中添加音乐来源或导入本地音乐。';
        return _withViewControls(
          result.total == 0
              ? Center(child: Text(emptyMessage))
              : showCoverFlow
              ? CoverFlowView(
                  key: const ValueKey('album-cover-flow'),
                  itemCount: result.total,
                  coverBuilder: _coverFlowCover,
                  titleBuilder: _coverFlowTitle,
                  subtitleBuilder: _coverFlowSubtitle,
                  onActivate: _activateCoverFlow,
                  bottomPadding:
                      (MediaQuery.sizeOf(context).width > 750 ? 16 : 84) +
                      widget.bottomOverlayPadding,
                  emptyMessage: emptyMessage,
                )
              : LayoutBuilder(
                  builder: (context, viewport) {
                    final compactGrid =
                        useWideCardRatio(
                          context,
                          widget.app.desktopPreferences.compactPageCards,
                        ) &&
                        viewport.maxWidth >= 620 &&
                        widget.query.view != 0 &&
                        widget.selected == null &&
                        !widget.query.blocked;
                    final miuix = SylphyMiuixStyle.enabled(context);
                    Widget compactCard(Widget row) => miuix
                        ? SylphyAdaptiveCard(cornerRadius: 18, child: row)
                        : Card.outlined(margin: EdgeInsets.zero, child: row);

                    return RawScrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      interactive: true,
                      thickness: 5,
                      radius: const Radius.circular(8),
                      thumbColor: miuix
                          ? MiuixTheme.of(context)
                                .colors
                                .onSurfaceVariantActions
                                .withValues(alpha: .38)
                          : Theme.of(context).colorScheme.onSurfaceVariant
                                .withValues(alpha: .38),
                      child: ListView.builder(
                        key: ValueKey('${widget.query.signature}:$generation'),
                        controller: _scrollController,
                        cacheExtent: 0,
                        clipBehavior: Clip.hardEdge,
                        padding: EdgeInsets.only(
                          top: listBehindHeader ? _headerPadding : 0,
                          bottom: libraryListBottomPadding(
                            viewportWidth: MediaQuery.sizeOf(context).width,
                            basePadding: widget.bottomPadding,
                            overlayPadding: widget.bottomOverlayPadding,
                          ),
                        ),
                        itemExtent: compactGrid
                            ? 92 *
                                  MediaQuery.textScalerOf(context).scale(14) /
                                  14
                            : widget.query.view == 0
                            ? _rowExtent
                            : null,
                        itemCount: compactGrid
                            ? (result.total + 1) ~/ 2
                            : result.total,
                        itemBuilder: (_, i) {
                          if (!compactGrid) return _virtualRow(i);
                          final first = i * 2;
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: compactCard(_virtualRow(first)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: first + 1 < result.total
                                      ? compactCard(_virtualRow(first + 1))
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
          result: result,
          listBehindHeader: listBehindHeader,
        );
      },
    ),
  );

  Widget _withViewControls(
    Widget content, {
    CatalogPage? result,
    bool listBehindHeader = false,
  }) {
    final batch = widget.batchSelection;
    final canAct = result != null && result.total > 0;
    final foldedActions = LibraryCollapsedActions(
      total: result?.total,
      countUnit: widget.query.countUnit,
      playAll: canAct ? () => _act(_play) : null,
      locateCurrent: canAct && widget.query.view == 0
          ? () => _act(_locateCurrentTrack)
          : null,
      batchActive: batch?.active ?? false,
      selectionCount: batch?.count ?? 0,
      allSelected: batch?.all ?? false,
      exitSelection: batch?.active == true ? batch?.clear : null,
      toggleSelectAll: !canAct || batch?.active != true
          ? null
          : batch!.all
          ? batch.deselectAll
          : () => batch.selectAll(result!.total),
    );
    // Keep menu callbacks in the LibraryBrowser State. Publishing after the
    // frame avoids mutating AppBar listeners during a FutureBuilder build.
    final onToolbarActionsChanged = widget.onToolbarActionsChanged;
    if (onToolbarActionsChanged != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.onToolbarActionsChanged == onToolbarActionsChanged) {
          onToolbarActionsChanged(foldedActions);
        }
      });
    }
    final expanded = Column(
      key: const ValueKey('library-expanded-controls'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.selected == null &&
            !widget.query.blocked &&
            batch?.active == true)
          ListTile(
            key: const ValueKey('batch-summary'),
            contentPadding: const EdgeInsetsDirectional.only(
              start: 16,
              end: 12,
            ),
            leading: IconButton(
              tooltip: '退出多选',
              icon: const Icon(Icons.close),
              onPressed: batch!.clear,
            ),
            title: Text('已选 ${batch!.count} ${widget.query.countUnit}'),
            trailing: TextButton(
              onPressed: result == null
                  ? null
                  : batch!.all
                  ? batch.deselectAll
                  : () => batch.selectAll(result.total),
              child: Text(batch!.all ? '取消全选' : '全选'),
            ),
          )
        else if (widget.selected == null && !widget.query.blocked)
          ListTile(
            key: const ValueKey('song-summary'),
            contentPadding: const EdgeInsetsDirectional.only(
              start: 16,
              end: 16,
            ),
            leading: IconButton(
              key: const ValueKey('play-all-library-tracks'),
              tooltip: '播放全部',
              icon: const Icon(Icons.play_circle),
              onPressed: canAct ? () => _act(_play) : null,
            ),
            title: Text(result == null ? '—' : '${result.total}', maxLines: 1),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.query.view == 0)
                  SizedBox.square(
                    dimension: 48,
                    child: IconButton(
                      key: const ValueKey('locate-current-library-track'),
                      tooltip: '定位当前播放歌曲',
                      icon: const Icon(Icons.gps_fixed_rounded, size: 24),
                      onPressed: canAct
                          ? () => _act(_locateCurrentTrack)
                          : null,
                    ),
                  ),
                if (widget.songActions != null) widget.songActions!,
              ],
            ),
          ),
        if (widget.viewControls != null) widget.viewControls!,
      ],
    );
    return Padding(
      padding: EdgeInsets.only(top: listBehindHeader ? 0 : _headerPadding),
      child: Column(
        children: [
          SylphyAnimatedToolbar(
            collapsed: _toolbarFolded,
            expanded: expanded,
            compact: const SizedBox(width: double.infinity, height: 0),
          ),
          Expanded(child: content),
        ],
      ),
    );
  }
}
