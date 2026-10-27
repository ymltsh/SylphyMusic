import 'package:flutter/material.dart';

import '../core/models.dart';
import '../services/playback.dart';

/// One mutually exclusive mode control, shared by every player surface.
class PlaybackModeButton extends StatefulWidget {
  const PlaybackModeButton({
    super.key,
    required this.playback,
    this.preview = false,
  });
  final PlaybackCoordinator playback;
  final bool preview;
  @override
  State<PlaybackModeButton> createState() => _PlaybackModeButtonState();
}

class _PlaybackModeButtonState extends State<PlaybackModeButton> {
  bool busy = false;
  Future<void> _cycle() async {
    if (busy || widget.preview) return;
    setState(() => busy = true);
    try {
      await widget.playback.cyclePlaybackMode();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('播放模式切换失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.playback,
    builder: (context, _) {
      final mode = widget.preview
          ? PlaybackMode.listLoop
          : widget.playback.snapshot.playbackMode;
      return IconButton(
        tooltip: '播放模式：${mode.label}',
        onPressed: widget.preview
            ? () {}
            : busy || widget.playback.snapshot.tracks.isEmpty
            ? null
            : _cycle,
        icon: Icon(switch (mode) {
          PlaybackMode.listLoop => Icons.repeat,
          PlaybackMode.singleLoop => Icons.repeat_one,
          PlaybackMode.shuffle => Icons.shuffle,
        }),
      );
    },
  );
}
