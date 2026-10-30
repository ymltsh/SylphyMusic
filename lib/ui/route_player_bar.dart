import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import 'player_bar.dart';

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
