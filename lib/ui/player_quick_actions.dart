import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'player_favorite.dart';

class PlayerQuickActions extends StatelessWidget {
  const PlayerQuickActions({
    super.key,
    required this.app,
    this.track,
    this.preview = false,
    this.onOpenLyrics,
    this.onOpenEditor,
    this.onQuality,
  });
  final SylphyApp app;
  final Track? track;
  final bool preview;
  final VoidCallback? onOpenLyrics, onOpenEditor, onQuality;

  void _timerSheet(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListenableBuilder(
        listenable: app.sleepTimer,
        builder: (context, _) => ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('睡眠定时'),
              subtitle: Text(
                app.sleepTimer.active
                    ? '约 ${(app.sleepTimer.remaining.inSeconds + 59) ~/ 60} 分钟后暂停播放，离开播放页仍有效'
                    : '倒计时结束后暂停播放',
              ),
            ),
            if (app.sleepTimer.error != null)
              ListTile(title: Text(app.sleepTimer.error!)),
            for (final minutes in [15, 30, 45, 60, 90])
              ListTile(
                title: Text('$minutes 分钟'),
                onTap: () {
                  app.sleepTimer.start(Duration(minutes: minutes));
                  Navigator.pop(context);
                },
              ),
            if (app.sleepTimer.active)
              ListTile(
                title: const Text('取消定时'),
                onTap: () {
                  app.sleepTimer.cancel();
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app.sleepTimer,
    builder: (context, _) => Row(
      key: const ValueKey('player-quick-actions'),
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: '睡眠定时',
          isSelected: !preview && app.sleepTimer.active,
          onPressed: preview ? () {} : () => _timerSheet(context),
          icon: const Icon(Icons.timer_outlined),
          selectedIcon: const Icon(Icons.timer),
        ),
        IconButton(
          tooltip: '歌词页',
          onPressed: preview ? () {} : onOpenLyrics,
          icon: const Icon(Icons.lyrics_outlined),
        ),
        if (preview || track == null)
          IconButton(
            tooltip: '收藏',
            onPressed: () {},
            icon: const Icon(Icons.favorite_border_rounded),
          )
        else
          PlayerFavorite(app: app, track: track!),
        if (preview)
          IconButton(
            tooltip: '更多',
            onPressed: () {},
            icon: const Icon(Icons.more_vert),
          )
        else
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'edit') {
                onOpenEditor?.call();
              } else {
                onQuality?.call();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'quality', child: Text('歌曲信息')),
              PopupMenuItem(value: 'edit', child: Text('编辑播放页')),
            ],
          ),
      ],
    ),
  );
}
