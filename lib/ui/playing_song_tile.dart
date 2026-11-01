import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'cover_art.dart';

/// A song row with a quiet current-track tint and a live equalizer badge.
/// Progress notifications do not trigger a rebuild unless the active track or
/// its play/pause status actually changes.
class PlayingSongTile extends StatefulWidget {
  const PlayingSongTile({
    super.key,
    required this.app,
    required this.track,
    required this.title,
    required this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.contentPadding,
  });

  final SylphyApp app;
  final Track track;
  final String title, subtitle;
  final Widget? leading, trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? contentPadding;

  @override
  State<PlayingSongTile> createState() => _PlayingSongTileState();
}

class _PlayingSongTileState extends State<PlayingSongTile> {
  bool _isCurrent = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _sync(notify: false);
    widget.app.playback.addListener(_onPlaybackChanged);
  }

  @override
  void didUpdateWidget(covariant PlayingSongTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.app.playback, widget.app.playback)) {
      oldWidget.app.playback.removeListener(_onPlaybackChanged);
      widget.app.playback.addListener(_onPlaybackChanged);
    }
    _sync(notify: false);
  }

  void _onPlaybackChanged() => _sync(notify: true);

  void _sync({required bool notify}) {
    final isCurrent = widget.app.playback.currentRef == widget.track.ref;
    final isPlaying = isCurrent && widget.app.playback.playing;
    if (_isCurrent == isCurrent && _isPlaying == isPlaying) return;
    _isCurrent = isCurrent;
    _isPlaying = isPlaying;
    if (notify && mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.app.playback.removeListener(_onPlaybackChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      color: _isCurrent
          ? scheme.primary.withValues(alpha: .09)
          : Colors.transparent,
      child: ListTile(
        contentPadding: widget.contentPadding,
        selected: _isCurrent,
        selectedColor: scheme.primary,
        leading: SizedBox.square(
          dimension: 48,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child:
                    widget.leading ??
                    CoverArt(app: widget.app, track: widget.track),
              ),
              if (_isCurrent)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 2,
                      ),
                      child: PlaybackEqualizer(
                        playing: _isPlaying,
                        color: scheme.onPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _isCurrent
              ? const TextStyle(fontWeight: FontWeight.w600)
              : null,
        ),
        subtitle: Text(
          widget.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: widget.onTap,
        trailing: widget.trailing,
      ),
    );
  }
}

/// Three subtle bars move only while the selected track is playing.
class PlaybackEqualizer extends StatefulWidget {
  const PlaybackEqualizer({
    super.key,
    required this.playing,
    required this.color,
  });

  final bool playing;
  final Color color;

  @override
  State<PlaybackEqualizer> createState() => _PlaybackEqualizerState();
}

class _PlaybackEqualizerState extends State<PlaybackEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 820),
  );

  @override
  void initState() {
    super.initState();
    _updateAnimation();
  }

  @override
  void didUpdateWidget(covariant PlaybackEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing != oldWidget.playing) _updateAnimation();
  }

  void _updateAnimation() {
    if (widget.playing) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.playing) {
      return Icon(Icons.pause_rounded, size: 14, color: widget.color);
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      return Icon(Icons.equalizer_rounded, size: 14, color: widget.color);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => SizedBox(
        width: 14,
        height: 14,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final offset in const [0.0, .28, .62])
              Container(
                width: 2.5,
                height:
                    4 +
                    10 *
                        (.5 +
                            .5 *
                                math.sin(
                                  2 * math.pi * (_controller.value + offset),
                                )),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
