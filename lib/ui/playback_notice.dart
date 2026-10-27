import 'dart:async';

import 'package:flutter/material.dart';

/// One playback toast shared across routes, outside the SnackBar queue.
class PlaybackNotice extends StatefulWidget {
  const PlaybackNotice({
    super.key,
    required this.playback,
    required this.readError,
    required this.child,
  });
  final Listenable playback;
  final String? Function() readError;
  final Widget child;
  @override
  State<PlaybackNotice> createState() => _PlaybackNoticeState();
}

class _PlaybackNoticeState extends State<PlaybackNotice> {
  String? _lastError;
  OverlayEntry? _entry;
  Timer? _timer;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _lastError = widget.readError();
    widget.playback.addListener(_changed);
  }

  @override
  void didUpdateWidget(PlaybackNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playback != widget.playback) {
      oldWidget.playback.removeListener(_changed);
      _generation++;
      _hide();
      _lastError = widget.readError();
      widget.playback.addListener(_changed);
    }
  }

  void _changed() {
    final error = widget.readError();
    if (error == _lastError) return;
    _lastError = error;
    final generation = ++_generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      _hide();
      if (error == null) return;
      final message = error.contains('连续 3 首')
          ? '连续播放失败，已暂停播放'
          : error == '来源已停用或移除' || error == '系统暂时未授予音频焦点'
          ? error
          : '歌曲加载失败，请稍后重试';
      _entry = OverlayEntry(
        builder: (context) {
          final colors = Theme.of(context).colorScheme;
          return Positioned.fill(
            child: IgnorePointer(
              child: SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
                    child: Semantics(
                      liveRegion: true,
                      child: Material(
                        key: const ValueKey('playback-error-toast'),
                        color: colors.inverseSurface,
                        elevation: 6,
                        borderRadius: BorderRadius.circular(14),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            child: Text(
                              message,
                              style: TextStyle(color: colors.onInverseSurface),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
      Overlay.of(context, rootOverlay: true).insert(_entry!);
      _timer = Timer(const Duration(seconds: 3), _hide);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  @override
  void dispose() {
    _generation++;
    widget.playback.removeListener(_changed);
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
