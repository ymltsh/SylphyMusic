import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'cover_art.dart';
import 'now_playing.dart';
import 'playback_mode_button.dart';
import 'playback_controls.dart';
import 'track_lookup.dart';

String formatTime(Duration time) =>
    '${time.inMinutes}:${(time.inSeconds % 60).toString().padLeft(2, '0')}';

// The mini player opens as a bottom sheet-like full page, with a matching
// downward exit animation when the user dismisses it.
Route<void> _nowPlayingRoute(SylphyApp app) => PageRouteBuilder<void>(
  pageBuilder: (_, _, _) => NowPlayingPage(app: app),
  transitionDuration: const Duration(milliseconds: 320),
  reverseTransitionDuration: const Duration(milliseconds: 260),
  transitionsBuilder: (context, animation, _, child) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
          ),
      child: child,
    );
  },
);

class PlayerBar extends StatelessWidget {
  const PlayerBar({
    super.key,
    required this.app,
    this.compact = false,
    this.immersive = false,
    this.onCollapse,
  });
  final SylphyApp app;
  final bool compact;
  final bool immersive;
  final VoidCallback? onCollapse;
  Future<void> _act(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('播放操作失败，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = app.playback, track = app.playback.current;
    final scheme = Theme.of(context).colorScheme;
    final enabled = player.snapshot.tracks.isNotEmpty;
    if (compact) {
      final bar = Material(
        color: scheme.surfaceContainerHigh.withValues(
          alpha: app.appearance.glass ? .8 : 1,
        ),
        child: InkWell(
          onTap: track == null
              ? null
              : () => Navigator.of(context).push(_nowPlayingRoute(app)),
          onLongPress: onCollapse,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    if (track != null)
                      CoverArt(app: app, track: track, size: 44)
                    else
                      const SizedBox.square(
                        dimension: 44,
                        child: Icon(Icons.headphones_rounded),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track?.title ?? '选择一首音乐开始播放',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (track != null)
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onLongPress: () {},
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PlaybackModeButton(playback: player),
                          IconButton.filled(
                            tooltip: player.playing ? '暂停' : '播放',
                            onPressed: enabled
                                ? () => _act(context, player.toggle)
                                : null,
                            icon: Icon(
                              player.playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                          ),
                          IconButton(
                            tooltip: '播放队列',
                            onPressed: () => showQueue(context),
                            icon: const Icon(Icons.queue_music),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (player.buffering)
                const LinearProgressIndicator(minHeight: 2)
              else
                LinearProgressIndicator(
                  minHeight: 2,
                  value: player.duration.inMilliseconds <= 0
                      ? 0
                      : (player.position.inMilliseconds /
                                player.duration.inMilliseconds)
                            .clamp(0, 1),
                ),
            ],
          ),
        ),
      );
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: .18),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: app.appearance.glass
              ? BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: bar,
                )
              : bar,
        ),
      );
    }
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlaybackModeButton(playback: player),
        IconButton(
          tooltip: '上一首',
          onPressed: enabled ? () => _act(context, player.previous) : null,
          icon: const Icon(Icons.skip_previous),
        ),
        IconButton.filled(
          style: IconButton.styleFrom(
            minimumSize: Size.square(immersive ? 68 : 56),
            iconSize: immersive ? 36 : 28,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          tooltip: player.playing ? '暂停' : '播放',
          onPressed: enabled ? () => _act(context, player.toggle) : null,
          icon: Icon(
            player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          ),
        ),
        IconButton(
          tooltip: '下一首',
          onPressed: enabled ? () => _act(context, player.next) : null,
          icon: const Icon(Icons.skip_next),
        ),
        IconButton(
          tooltip: '播放队列',
          onPressed: () => showQueue(context),
          icon: const Icon(Icons.queue_music_rounded),
        ),
      ],
    );
    if (immersive) {
      return SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PlayerProgress(app: app),
                  const SizedBox(height: 16),
                  SizedBox(height: 72, child: PlayerControls(app: app)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final description = Expanded(
      child: InkWell(
        onTap: track == null
            ? null
            : () => Navigator.of(context).push(_nowPlayingRoute(app)),
        child: Row(
          children: [
            if (track != null) CoverArt(app: app, track: track),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track?.title ?? '选择一首音乐开始播放',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (track != null)
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Material(
      elevation: 4,
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (player.buffering) const LinearProgressIndicator(minHeight: 2),
              LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth < 620
                    ? Column(
                        children: [
                          Row(children: [description]),
                          controls,
                        ],
                      )
                    : Row(children: [description, controls]),
              ),
              if (track != null)
                Row(
                  children: [
                    Text(
                      formatTime(player.position),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Expanded(
                      child: Slider(
                        value: player.position.inMilliseconds
                            .clamp(0, player.duration.inMilliseconds)
                            .toDouble(),
                        max: player.duration.inMilliseconds <= 0
                            ? 1
                            : player.duration.inMilliseconds.toDouble(),
                        onChanged: player.duration > Duration.zero
                            ? (value) => _act(
                                context,
                                () => player.seek(
                                  Duration(milliseconds: value.round()),
                                ),
                              )
                            : null,
                      ),
                    ),
                    Text(
                      formatTime(player.duration),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .7,
          child: AnimatedBuilder(
            animation: app.playback,
            builder: (context, _) {
              final player = app.playback;
              return Column(
                children: [
                  ListTile(
                    title: Text('播放队列 · ${player.snapshot.tracks.length} 首'),
                    trailing: TextButton(
                      onPressed: () => _act(context, player.clearQueue),
                      child: const Text('清空'),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: player.snapshot.tracks.length,
                      itemBuilder: (context, index) {
                        final key = player.snapshot.tracks[index];
                        return TrackLookup(
                          app: app,
                          ref: TrackRef.parse(key),
                          builder: (context, track) => ListTile(
                            selected: index == player.snapshot.index,
                            leading: Icon(
                              index == player.snapshot.index
                                  ? Icons.equalizer
                                  : Icons.music_note_outlined,
                            ),
                            title: Text(
                              track?.title ?? '不可用歌曲',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(track?.artist ?? '来源已移除'),
                            onTap: () =>
                                _act(context, () => player.jumpTo(index)),
                            trailing: IconButton(
                              tooltip: '移出队列',
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  _act(context, () => player.removeAt(index)),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
