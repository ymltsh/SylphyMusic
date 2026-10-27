import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'cover_art.dart';
import 'now_playing.dart';
import 'track_lookup.dart';

String formatTime(Duration time) =>
    '${time.inMinutes}:${(time.inSeconds % 60).toString().padLeft(2, '0')}';

class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key, required this.app});
  final SylphyApp app;
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
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '随机播放',
          onPressed: enabled
              ? () => _act(
                  context,
                  () => player.setShuffle(!player.snapshot.shuffle),
                )
              : null,
          isSelected: player.snapshot.shuffle,
          icon: const Icon(Icons.shuffle),
        ),
        IconButton(
          tooltip: '上一首',
          onPressed: enabled ? () => _act(context, player.previous) : null,
          icon: const Icon(Icons.skip_previous),
        ),
        IconButton.filled(
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
          tooltip:
              '循环模式：${switch (player.snapshot.repeat) {
                RepeatKind.off => '顺序',
                RepeatKind.all => '列表循环',
                RepeatKind.one => '单曲循环',
              }}',
          onPressed: enabled
              ? () => _act(
                  context,
                  () => player.setRepeat(switch (player.snapshot.repeat) {
                    RepeatKind.off => RepeatKind.all,
                    RepeatKind.all => RepeatKind.one,
                    RepeatKind.one => RepeatKind.off,
                  }),
                )
              : null,
          icon: Icon(
            player.snapshot.repeat == RepeatKind.one
                ? Icons.repeat_one
                : Icons.repeat,
            color: player.snapshot.repeat == RepeatKind.off
                ? null
                : scheme.primary,
          ),
        ),
      ],
    );
    final description = Expanded(
      child: InkWell(
        onTap: track == null
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => NowPlayingPage(app: app)),
              ),
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
                        Row(
                          children: [
                            description,
                            IconButton(
                              tooltip: '播放队列',
                              onPressed: () => _queue(context),
                              icon: const Icon(Icons.queue_music),
                            ),
                          ],
                        ),
                        controls,
                      ],
                    )
                  : Row(
                      children: [
                        description,
                        controls,
                        const SizedBox(width: 20),
                        IconButton(
                          tooltip: '播放队列',
                          onPressed: () => _queue(context),
                          icon: const Icon(Icons.queue_music),
                        ),
                      ],
                    ),
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
            if (player.error != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      player.error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.error, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _act(context, player.retry),
                    child: const Text('重试'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _queue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
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
    );
  }
}
