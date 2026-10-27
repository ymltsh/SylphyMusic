import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/player_layout.dart';
import 'player_layout/layout_renderer.dart';

/// Playback renders the saved layout; component sizing belongs to the editor.
class PlayerScene extends StatelessWidget {
  const PlayerScene({
    super.key,
    required this.app,
    required this.layout,
    required this.track,
    required this.lyrics,
    required this.onOpenLyrics,
    required this.onOpenEditor,
    required this.onQuality,
  });
  final SylphyApp app;
  final PlayerLayout layout;
  final Track track;
  final Future<String?>? lyrics;
  final VoidCallback onOpenLyrics;
  final VoidCallback onOpenEditor, onQuality;

  @override
  Widget build(BuildContext context) => PlayerLayoutRenderer(
    layout: layout,
    drawBackground: false,
    data: PlayerWidgetContext(
      app: app,
      track: track,
      lyrics: lyrics,
      onOpenLyrics: onOpenLyrics,
      onOpenEditor: onOpenEditor,
      onQuality: onQuality,
    ),
  );
}
