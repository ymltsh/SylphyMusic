import 'package:flutter/material.dart';

import '../core/models.dart';

class PlaylistReorderGrid extends StatefulWidget {
  const PlaylistReorderGrid({
    super.key,
    required this.playlists,
    required this.cardBuilder,
    required this.onMove,
  });

  final List<PlaylistModel> playlists;
  final Widget Function(BuildContext, PlaylistModel) cardBuilder;
  final Future<void> Function(String id, String targetId) onMove;

  @override
  State<PlaylistReorderGrid> createState() => _PlaylistReorderGridState();
}

class _PlaylistReorderGridState extends State<PlaylistReorderGrid> {
  EdgeDraggingAutoScroller? _autoScroller;
  String? _draggedId;
  bool _saving = false;

  @override
  void dispose() {
    _autoScroller?.stopAutoScroll();
    super.dispose();
  }

  void _endDrag() {
    _autoScroller?.stopAutoScroll();
    _autoScroller = null;
    if (mounted) setState(() => _draggedId = null);
  }

  Future<void> _move(String id, String targetId) async {
    if (_saving || id == targetId) return;
    _endDrag();
    setState(() => _saving = true);
    try {
      await widget.onMove(id, targetId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存歌单顺序失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1200
          ? 5
          : constraints.maxWidth >= 900
          ? 4
          : constraints.maxWidth >= 640
          ? 3
          : 2;
      final width = (constraints.maxWidth - 32 - (columns - 1) * 14) / columns;
      final height =
          width +
          MediaQuery.textScalerOf(context).scale(14) * 2 * 1.5 +
          MediaQuery.textScalerOf(context).scale(12) * 2 * 1.3 +
          16;
      return GridView.builder(
        key: const PageStorageKey('playlist-reorder-grid'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 14,
          mainAxisSpacing: 16,
          mainAxisExtent: height,
        ),
        itemCount: widget.playlists.length,
        findChildIndexCallback: (key) {
          if (key is! ValueKey<String>) return null;
          final index = widget.playlists.indexWhere((p) => p.id == key.value);
          return index < 0 ? null : index;
        },
        itemBuilder: (itemContext, index) {
          final playlist = widget.playlists[index];
          final card = widget.cardBuilder(itemContext, playlist);
          return DragTarget<String>(
            key: ValueKey(playlist.id),
            onWillAcceptWithDetails: (details) =>
                !_saving &&
                details.data == _draggedId &&
                details.data != playlist.id,
            onAcceptWithDetails: (details) => _move(details.data, playlist.id),
            builder: (context, candidates, rejected) =>
                LongPressDraggable<String>(
                  data: playlist.id,
                  maxSimultaneousDrags: _saving || widget.playlists.length < 2
                      ? 0
                      : 1,
                  onDragStarted: () {
                    _autoScroller = EdgeDraggingAutoScroller(
                      Scrollable.of(itemContext),
                      velocityScalar: 12,
                    );
                    setState(() => _draggedId = playlist.id);
                  },
                  onDragUpdate: (details) {
                    _autoScroller?.startAutoScrollIfNecessary(
                      Rect.fromCenter(
                        center: details.globalPosition,
                        width: 48,
                        height: 96,
                      ),
                    );
                  },
                  onDragEnd: (_) => _endDrag(),
                  feedback: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    color: Theme.of(context).colorScheme.surface,
                    child: SizedBox(width: width, height: height, child: card),
                  ),
                  childWhenDragging: Opacity(opacity: .25, child: card),
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: candidates.isEmpty
                          ? null
                          : Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 3,
                            ),
                    ),
                    child: card,
                  ),
                ),
          );
        },
      );
    },
  );
}
