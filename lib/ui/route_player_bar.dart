import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/player_layout.dart';
import 'player_bar.dart';
import 'player_cover.dart';

/// Use with Scaffold.extendBody so the dock can float over scrolling content.
class RoutePlayerBar extends StatefulWidget {
  const RoutePlayerBar({
    super.key,
    required this.app,
    this.showWhenIdle = false,
  });

  final SylphyApp app;
  final bool showWhenIdle;

  @override
  State<RoutePlayerBar> createState() => _RoutePlayerBarState();
}

class _RoutePlayerBarState extends State<RoutePlayerBar> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return ListenableBuilder(
      listenable: Listenable.merge([app.playback, app.appearance]),
      builder: (context, _) => SafeArea(
        top: false,
        child: app.playback.current == null && !widget.showWhenIdle
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                child: Align(
                  alignment: _collapsed
                      ? AlignmentDirectional.centerEnd
                      : Alignment.center,
                  heightFactor: 1,
                  child: _collapsed
                      ? _RoutePlayerExpandButton(
                          app: app,
                          onPressed: () => setState(() => _collapsed = false),
                        )
                      : ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1040),
                          child: PlayerBar(
                            app: app,
                            compact: true,
                            onCollapse: () => setState(() => _collapsed = true),
                          ),
                        ),
                ),
              ),
      ),
    );
  }
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
      return _RoutePlayerExpandButton(
        app: app,
        onPressed: () => setState(() => _expanded = true),
      );
    },
  );
}

class _RoutePlayerExpandButton extends StatelessWidget {
  const _RoutePlayerExpandButton({required this.app, required this.onPressed});

  final SylphyApp app;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final track = app.playback.current;
    final colors = Theme.of(context).colorScheme;
    return FloatingActionButton(
      heroTag: null,
      tooltip: '展开迷你播放器',
      shape: const CircleBorder(),
      backgroundColor: colors.surfaceContainerHigh,
      foregroundColor: colors.onSurface,
      onPressed: onPressed,
      child: track == null
          ? const Icon(Icons.headphones_rounded)
          : PlayerCover(
              app: app,
              track: track,
              size: 48,
              style: PlayerCoverStyle.vinyl,
              rotate: true,
              playing: app.playback.playing,
            ),
    );
  }
}
