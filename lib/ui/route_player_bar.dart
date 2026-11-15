import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import 'player_bar.dart';
import 'player_cover.dart';

/// Mini player for pushed routes, which otherwise cover the root shell's bar.
class RoutePlayerBar extends StatelessWidget {
  const RoutePlayerBar({super.key, required this.app});

  final SylphyApp app;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([app.playback, app.appearance]),
    builder: (context, _) => app.playback.current == null
        ? const SizedBox.shrink()
        : SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: PlayerBar(app: app, compact: true),
            ),
          ),
  );
}

/// A route-local mini player; it starts collapsed independently of the shell.
class RoutePlayerFab extends StatefulWidget {
  const RoutePlayerFab({super.key, required this.app});
  final SylphyApp app;
  @override
  State<RoutePlayerFab> createState() => _RoutePlayerFabState();
}

class _RoutePlayerFabState extends State<RoutePlayerFab> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.app.playback, widget.app.appearance]),
    builder: (context, _) {
      final app = widget.app;
      final track = app.playback.current;
      if (_expanded) {
        return SizedBox(
          width: (MediaQuery.sizeOf(context).width - 32)
              .clamp(0.0, 520.0)
              .toDouble(),
          child: PlayerBar(
            app: app,
            compact: true,
            onCollapse: () => setState(() => _expanded = false),
          ),
        );
      }
      return FloatingActionButton(
        heroTag: null,
        tooltip: '展开迷你播放器',
        shape: const CircleBorder(),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        onPressed: () => setState(() => _expanded = true),
        child: track == null
            ? const Icon(Icons.headphones_rounded)
            : PlayerCover(
                app: app,
                track: track,
                size: 48,
                circle: app.appearance.disc,
                radius: 16,
                rotate: true,
                playing: app.playback.playing,
              ),
      );
    },
  );
}
