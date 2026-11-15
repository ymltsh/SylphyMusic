import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import 'lyrics_page.dart';
import 'player_cover.dart';
import 'playback_mode_button.dart';
import 'player_favorite.dart';

class WideMiniPlayer extends StatelessWidget {
  const WideMiniPlayer({
    super.key,
    required this.app,
    required this.onOpen,
    required this.onQueue,
    this.onCollapse,
  });
  final SylphyApp app;
  final VoidCallback onOpen, onQueue;
  final VoidCallback? onCollapse;

  Future<void> _act(BuildContext context, Future<void> Function() task) async {
    try {
      await task();
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('播放操作未完成，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      app.playback,
      app.appearance,
      app.desktopPreferences,
    ]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, bounds) {
        final player = app.playback;
        final track = player.current;
        final enabled = player.snapshot.tracks.isNotEmpty;
        final colors = Theme.of(context).colorScheme;
        final safePadding = MediaQuery.paddingOf(context);
        final availableWidth = bounds.maxWidth - safePadding.horizontal - 32;
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        // Budget for both side panels and the actual center controls, rather
        // than switching layouts at a desktop-sized window breakpoint.
        final wide = availableWidth >= 800 + (textScale - 1).clamp(0, 2) * 80;
        final sideWidth = ((availableWidth - 24) * .26).clamp(232.0, 320.0);
        final compactButtons = IconButton.styleFrom(
          minimumSize: const Size(32, 32),
          fixedSize: const Size(32, 32),
          padding: const EdgeInsets.all(6),
          iconSize: 20,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: colors.onSurfaceVariant,
        );

        void lyrics() {
          if (track == null) return;
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => LyricsPage(
                app: app,
                track: track,
                theme: Theme.of(context),
                lyrics: app.loadLyrics(track),
              ),
            ),
          );
        }

        Widget speedMenu() => PopupMenuButton<double>(
          tooltip: '播放速度',
          enabled: enabled,
          onSelected: (value) => _act(context, () => player.setSpeed(value)),
          itemBuilder: (_) => [
            for (final speed in [.75, 1.0, 1.25, 1.5, 2.0])
              CheckedPopupMenuItem(
                value: speed,
                checked: player.speed == speed,
                child: Text('$speed×'),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Text(
              '${player.speed.toStringAsFixed(player.speed == player.speed.roundToDouble() ? 1 : 2)}×',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        );

        Future<void> volumePanel() => showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('应用内音量'),
            content: SizedBox(
              width: 260,
              height: 48,
              child: ListenableBuilder(
                listenable: player,
                builder: (_, _) => _InlineVolume(app: app),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('完成'),
              ),
            ],
          ),
        );

        Widget more() => PopupMenuButton<String>(
          tooltip: '更多播放控制',
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: (value) {
            if (value == 'volume') {
              volumePanel();
            } else if (value == 'mode') {
              _act(context, player.cyclePlaybackMode);
            } else if (value == 'speed') {
              _act(context, () async {
                final speed = await showDialog<double>(
                  context: context,
                  builder: (dialogContext) => SimpleDialog(
                    title: const Text('播放速度'),
                    children: [
                      for (final speed in [.75, 1.0, 1.25, 1.5, 2.0])
                        SimpleDialogOption(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(speed),
                          child: Text(
                            '$speed×${player.speed == speed ? " · 当前" : ""}',
                          ),
                        ),
                    ],
                  ),
                );
                if (speed != null) await player.setSpeed(speed);
              });
            } else if (value == 'open')
              onOpen();
            else if (value == 'lyrics')
              lyrics();
            else if (value == 'collapse')
              onCollapse?.call();
            else if (value == 'favorite' && track != null)
              _act(context, () => app.toggleFavorite(track));
          },
          itemBuilder: (_) => [
            if (track != null) ...[
              const PopupMenuItem(value: 'open', child: Text('打开播放页')),
              const PopupMenuItem(value: 'lyrics', child: Text('查看歌词')),
              const PopupMenuItem(value: 'favorite', child: Text('切换收藏')),
            ],
            if (!wide) ...[
              if (enabled) ...[
                PopupMenuItem(
                  value: 'mode',
                  child: Text('切换播放模式 · ${player.snapshot.playbackMode.label}'),
                ),
                PopupMenuItem(
                  value: 'speed',
                  child: Text('播放速度 · ${player.speed}×'),
                ),
              ],
              if (app.desktopPreferences.showVolume)
                const PopupMenuItem(value: 'volume', child: Text('应用内音量')),
            ],
            if (onCollapse != null)
              const PopupMenuItem(value: 'collapse', child: Text('收起播放器')),
          ],
        );

        Widget description() => Row(
          children: [
            InkWell(
              onTap: track == null ? null : onOpen,
              borderRadius: BorderRadius.circular(12),
              child: PlayerCover(
                app: app,
                track: track,
                size: wide ? 52 : 40,
                circle: app.appearance.disc,
                radius: 8,
                rotate: app.appearance.discRotation,
                playing: player.playing,
                shadow: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: track == null ? null : onOpen,
                    child: Text(
                      track?.title ?? '选择一首音乐',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: 13.5,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          track?.artist ?? '从曲库开始播放',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: 11.5,
                                height: 1.2,
                                color: colors.onSurfaceVariant,
                              ),
                        ),
                      ),
                      if (wide) ...[
                        const SizedBox(width: 4),
                        IconButtonTheme(
                          data: IconButtonThemeData(style: compactButtons),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (wide &&
                                  app.desktopPreferences.showExtraControls &&
                                  track != null)
                                PlayerFavorite(app: app, track: track),
                              more(),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        );

        Widget controls() => IconButtonTheme(
          data: IconButtonThemeData(
            style: IconButton.styleFrom(
              minimumSize: Size.square(wide ? 40 : 36),
              fixedSize: Size.square(wide ? 40 : 36),
              padding: EdgeInsets.all(wide ? 8 : 6),
              iconSize: wide ? 22 : 20,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (wide) ...[
                PlaybackModeButton(playback: player),
                const SizedBox(width: 8),
              ],
              IconButton(
                tooltip: '上一首 · Ctrl + ←',
                onPressed: enabled
                    ? () => _act(context, player.previous)
                    : null,
                icon: const Icon(Icons.skip_previous_rounded),
                iconSize: 24,
              ),
              SizedBox(width: wide ? 8 : 4),
              IconButton.filled(
                tooltip: player.playing ? '暂停 · 空格' : '播放 · 空格',
                style: IconButton.styleFrom(
                  fixedSize: Size.square(wide ? 44 : 40),
                  minimumSize: Size.square(wide ? 44 : 40),
                  iconSize: 27,
                  shape: const CircleBorder(),
                  backgroundColor: colors.surfaceContainerHighest,
                  foregroundColor: colors.onSurface,
                ),
                onPressed: enabled ? () => _act(context, player.toggle) : null,
                icon: Icon(
                  player.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
              SizedBox(width: wide ? 8 : 4),
              IconButton(
                tooltip: '下一首 · Ctrl + →',
                onPressed: enabled ? () => _act(context, player.next) : null,
                icon: const Icon(Icons.skip_next_rounded),
                iconSize: 24,
              ),
              if (wide) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '歌词',
                  onPressed: track == null ? null : lyrics,
                  icon: const Text(
                    '词',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ],
          ),
        );

        Widget queue() => IconButton(
          tooltip: '播放队列 · ${player.snapshot.tracks.length} 首 · Ctrl + L',
          onPressed: onQueue,
          style: IconButton.styleFrom(
            minimumSize: Size.square(wide ? 40 : 36),
            fixedSize: Size.square(wide ? 40 : 36),
            iconSize: 22,
            padding: const EdgeInsets.all(8),
          ),
          icon: const Icon(Icons.queue_music_rounded),
        );
        Widget volume() => SizedBox(
          width: wide ? 136 : 132,
          height: 36,
          child: _InlineVolume(app: app),
        );
        Widget right() => Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(width: 48, child: speedMenu()),
            queue(),
            if (app.desktopPreferences.showVolume) ...[
              const SizedBox(width: 4),
              volume(),
            ],
          ],
        );
        Widget center() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            controls(),
            SizedBox(height: 22, child: _InlineProgress(app: app)),
          ],
        );

        final fontExtra = (MediaQuery.textScalerOf(context).scale(14) - 14)
            .clamp(0.0, 100.0);
        // Scaffold gives the footer a bounded screen height. Give the bar its
        // own height so nested sliders cannot consume the entire body.
        return SizedBox(
          height:
              (wide ? 84.0 : 64.0) +
              fontExtra * 2 +
              MediaQuery.paddingOf(context).bottom,
          child: Material(
            color: colors.surfaceContainerLow,
            child: SafeArea(
              top: false,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: colors.outlineVariant.withValues(alpha: .6),
                    ),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: wide ? 6 : 4,
                  ),
                  child: wide
                      ? Row(
                          children: [
                            SizedBox(width: sideWidth, child: description()),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Align(
                                alignment: Alignment.center,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 460,
                                  ),
                                  child: center(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(width: sideWidth, child: right()),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: description()),
                            const SizedBox(width: 12),
                            controls(),
                            queue(),
                            IconButtonTheme(
                              data: IconButtonThemeData(style: compactButtons),
                              child: more(),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

String _time(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

class _InlineProgress extends StatefulWidget {
  const _InlineProgress({required this.app});
  final SylphyApp app;
  @override
  State<_InlineProgress> createState() => _InlineProgressState();
}

class _InlineProgressState extends State<_InlineProgress> {
  double? _draft;
  String? _track;
  @override
  Widget build(BuildContext context) {
    final player = widget.app.playback;
    if (_track != player.currentRef?.key) {
      _draft = null;
      _track = player.currentRef?.key;
    }
    final max = player.duration.inMilliseconds.toDouble();
    final value = (_draft ?? player.position.inMilliseconds.toDouble()).clamp(
      0.0,
      max > 0 ? max : 1.0,
    );
    return Row(
      children: [
        Text(
          _time(Duration(milliseconds: value.round())),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
            ),
            child: Slider(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              value: value,
              max: max > 0 ? max : 1,
              onChangeStart: max > 0 ? (v) => setState(() => _draft = v) : null,
              onChanged: max > 0 ? (v) => setState(() => _draft = v) : null,
              onChangeEnd: max > 0
                  ? (v) async {
                      final track = _track;
                      try {
                        if (track == player.currentRef?.key)
                          await player.seek(Duration(milliseconds: v.round()));
                      } catch (_) {
                        if (context.mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('跳转失败，请重试')),
                          );
                      } finally {
                        if (mounted) setState(() => _draft = null);
                      }
                    }
                  : null,
            ),
          ),
        ),
        Text(
          _time(player.duration),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _InlineVolume extends StatefulWidget {
  const _InlineVolume({required this.app});
  final SylphyApp app;
  @override
  State<_InlineVolume> createState() => _InlineVolumeState();
}

class _InlineVolumeState extends State<_InlineVolume> {
  double? _draft;
  double? _pending;
  bool _writing = false;
  bool _dragging = false;
  Timer? _delay;
  Future<void> _write(double value) async {
    _pending = value;
    if (_writing) return;
    _writing = true;
    try {
      while (_pending != null) {
        final next = _pending!;
        _pending = null;
        await widget.app.playback.setVolume(next);
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('音量调整失败，请重试')));
    } finally {
      _writing = false;
      if (mounted && !_dragging) setState(() => _draft = null);
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final volume = (_draft ?? widget.app.playback.volume).clamp(0.0, 100.0);
    return Row(
      children: [
        IconButton(
          tooltip: volume == 0 ? '取消静音 · M' : '静音 · M',
          onPressed: _writing
              ? null
              : () async {
                  _delay?.cancel();
                  _pending = null;
                  try {
                    await widget.app.playback.toggleMute();
                  } catch (_) {
                    if (context.mounted)
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('静音切换失败')));
                  }
                },
          icon: Icon(
            volume == 0
                ? Icons.volume_off_rounded
                : volume < 50
                ? Icons.volume_down_rounded
                : Icons.volume_up_rounded,
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
            ),
            child: Slider(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              value: volume,
              max: 100,
              label: '应用内音量 ${volume.round()}%',
              onChangeStart: (_) => _dragging = true,
              onChanged: (v) {
                setState(() => _draft = v);
                _delay?.cancel();
                _delay = Timer(
                  const Duration(milliseconds: 60),
                  () => _write(v),
                );
              },
              onChangeEnd: (v) {
                _dragging = false;
                _delay?.cancel();
                _write(v);
              },
            ),
          ),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '${volume.round()}',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}
