import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';

Future<void> _act(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('收藏操作失败，请重试')));
    }
  }
}

class PlayerFavorite extends StatefulWidget {
  const PlayerFavorite({super.key, required this.app, required this.track});
  final SylphyApp app;
  final Track track;
  @override
  State<PlayerFavorite> createState() => _PlayerFavoriteState();
}

class _PlayerFavoriteState extends State<PlayerFavorite> {
  late Future<List<String>> keys = _loadKeys();
  Future<List<String>> _loadKeys() =>
      widget.app.db.playlistKeys(widget.app.favoritePlaylistId(widget.track));
  bool busy = false;
  @override
  void initState() {
    super.initState();
    widget.app.addListener(_changed);
  }

  void _changed() {
    if (mounted) {
      setState(() {
        keys = _loadKeys();
      });
    }
  }

  @override
  void dispose() {
    widget.app.removeListener(_changed);
    super.dispose();
  }

  @override
  void didUpdateWidget(PlayerFavorite oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != widget.app) {
      oldWidget.app.removeListener(_changed);
      widget.app.addListener(_changed);
      _changed();
    }
    if (oldWidget.track.ref != widget.track.ref) {
      keys = _loadKeys();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<String>>(
    future: keys,
    builder: (context, snapshot) {
      final selected = snapshot.data?.contains(widget.track.ref.key) ?? false;
      return IconButton(
        tooltip: selected ? '取消收藏' : '收藏',
        icon: Icon(
          selected ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        ),
        onPressed: busy
            ? null
            : () async {
                setState(() => busy = true);
                await _act(
                  context,
                  () => widget.app.toggleFavorite(widget.track),
                );
                if (mounted) {
                  setState(() {
                    keys = _loadKeys();
                    busy = false;
                  });
                }
              },
      );
    },
  );
}
