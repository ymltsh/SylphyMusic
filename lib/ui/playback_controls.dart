import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import 'playback_mode_button.dart';
import 'player_bar.dart';

Future<void> _act(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('播放操作失败，请重试')));
    }
  }
}

class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.app,
    this.preview = false,
    this.color,
    this.radius = 24,
    this.playWidth = 64,
    this.playHeight = 64,
    this.spacing = 12,
  });
  final SylphyApp app;
  final bool preview;
  final int? color;
  final double radius, playWidth, playHeight, spacing;
  @override
  Widget build(BuildContext context) {
    final p = app.playback;
    final enabled = preview || p.snapshot.tracks.isNotEmpty;
    VoidCallback? action(Future<void> Function() task) => !enabled
        ? null
        : preview
        ? () {}
        : () => _act(context, task);
    return LayoutBuilder(
      builder: (context, constraints) {
        const sideWidth = 40.0;
        final gap = spacing.clamp(
          0.0,
          math.max(0.0, (constraints.maxWidth - sideWidth * 4 - playWidth) / 4),
        );
        Widget side(Widget child) =>
            SizedBox(width: sideWidth, height: 48, child: child);
        return Center(
          child: SizedBox(
            width: sideWidth * 4 + playWidth + gap * 4,
            height: playHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                side(PlaybackModeButton(playback: p, preview: preview)),
                side(
                  IconButton(
                    tooltip: '上一首',
                    onPressed: action(p.previous),
                    icon: const Icon(Icons.skip_previous),
                  ),
                ),
                IconButton.filled(
                  tooltip: !preview && p.playing ? '暂停' : '播放',
                  style: IconButton.styleFrom(
                    minimumSize: Size(playWidth, playHeight),
                    fixedSize: Size(playWidth, playHeight),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(radius),
                    ),
                    iconSize: playHeight * .56,
                    backgroundColor: color == null
                        ? Theme.of(context).colorScheme.primary
                        : Color(color!),
                    foregroundColor: color == null
                        ? Theme.of(context).colorScheme.onPrimary
                        : ThemeData.estimateBrightnessForColor(Color(color!)) ==
                              Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  ),
                  onPressed: action(p.toggle),
                  icon: Icon(
                    !preview && p.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                side(
                  IconButton(
                    tooltip: '下一首',
                    onPressed: action(p.next),
                    icon: const Icon(Icons.skip_next),
                  ),
                ),
                side(
                  IconButton(
                    tooltip: '播放队列',
                    onPressed: preview
                        ? () {}
                        : () => PlayerBar(app: app).showQueue(context),
                    icon: const Icon(Icons.queue_music_rounded),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class PlayerProgress extends StatefulWidget {
  const PlayerProgress({
    super.key,
    required this.app,
    this.preview = false,
    this.color,
  });
  final SylphyApp app;
  final bool preview;
  final int? color;

  @override
  State<PlayerProgress> createState() => _PlayerProgressState();
}

class _PlayerProgressState extends State<PlayerProgress> {
  double? _scrubValue;
  String? _scrubTrackKey;
  int _seekEpoch = 0;

  @override
  void didUpdateWidget(covariant PlayerProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != widget.app ||
        oldWidget.preview != widget.preview ||
        (_scrubValue != null &&
            _scrubTrackKey != widget.app.playback.currentRef?.key)) {
      _scrubValue = null;
      _scrubTrackKey = null;
      ++_seekEpoch;
    }
  }

  void _beginSeek(double value) {
    ++_seekEpoch;
    _scrubTrackKey = widget.app.playback.currentRef?.key;
    setState(() => _scrubValue = value);
  }

  Future<void> _finishSeek(double value) async {
    final epoch = _seekEpoch;
    final playback = widget.app.playback;
    try {
      if (!widget.preview && _scrubTrackKey == playback.currentRef?.key) {
        await _act(
          context,
          () => playback.seek(Duration(milliseconds: value.round())),
        );
      }
    } finally {
      if (mounted && epoch == _seekEpoch) {
        setState(() {
          _scrubValue = null;
          _scrubTrackKey = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.app.playback;
    final preview = widget.preview;
    final color = widget.color;
    final hasDuration = p.duration > Duration.zero;
    final max = preview
        ? (hasDuration ? p.duration.inMilliseconds : 240000)
        : math.max(1, p.duration.inMilliseconds);
    final playbackValue = preview
        ? (hasDuration
              ? p.position.inMilliseconds.clamp(0, max).toDouble()
              : 65000.0)
        : p.position.inMilliseconds.clamp(0, max).toDouble();
    final value = (_scrubValue ?? playbackValue).clamp(0.0, max.toDouble());
    final canSeek = preview || hasDuration;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: SizedBox(
            height: 48,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
              ),
              child: Slider(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                activeColor: color == null ? null : Color(color!),
                value: value,
                max: max.toDouble(),
                allowedInteraction: SliderInteraction.tapAndSlide,
                onChangeStart: canSeek ? _beginSeek : null,
                onChanged: canSeek
                    ? (v) => setState(() => _scrubValue = v)
                    : null,
                onChangeEnd: canSeek ? _finishSeek : null,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                preview && !hasDuration && _scrubValue == null
                    ? '1:05'
                    : formatTime(Duration(milliseconds: value.round())),
                style: const TextStyle(fontSize: 12, height: 1.2),
              ),
              if (!preview && p.buffering)
                const Text('缓冲中', style: TextStyle(fontSize: 12, height: 1.2)),
              Text(
                preview && !hasDuration ? '4:00' : formatTime(p.duration),
                style: const TextStyle(fontSize: 12, height: 1.2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
