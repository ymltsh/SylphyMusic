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

class PlayerProgress extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final p = app.playback;
    final hasDuration = p.duration > Duration.zero;
    final max = preview
        ? (hasDuration ? p.duration.inMilliseconds : 240000)
        : math.max(1, p.duration.inMilliseconds);
    final value = preview
        ? (hasDuration
              ? p.position.inMilliseconds.clamp(0, max).toDouble()
              : 65000.0)
        : p.position.inMilliseconds.clamp(0, max).toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
          ),
          child: Slider(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            activeColor: color == null ? null : Color(color!),
            value: value,
            max: max.toDouble(),
            onChanged: preview
                ? (_) {}
                : p.duration <= Duration.zero
                ? null
                : (v) => _act(
                    context,
                    () => p.seek(Duration(milliseconds: v.round())),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                preview && !hasDuration ? '1:05' : formatTime(p.position),
                style: const TextStyle(fontSize: 12),
              ),
              if (!preview && p.buffering)
                const Text('缓冲中', style: TextStyle(fontSize: 12)),
              Text(
                preview && !hasDuration ? '4:00' : formatTime(p.duration),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
