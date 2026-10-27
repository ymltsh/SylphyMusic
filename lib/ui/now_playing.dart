import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import 'cover_art.dart';
import 'lyrics_view.dart';
import 'player_bar.dart';

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key, required this.app});
  final SylphyApp app;
  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage>
    with SingleTickerProviderStateMixin {
  late final motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat(reverse: true);
  String? lyricsKey;
  Future<String?>? lyrics;
  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app.playback,
    builder: (context, _) {
      final track = widget.app.playback.current;
      if (track == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('正在播放')),
          body: const Center(child: Text('队列为空')),
        );
      }
      if (lyricsKey != track.ref.key) {
        lyricsKey = track.ref.key;
        lyrics = widget.app.loadLyrics(track);
      }
      final art = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CoverArt(app: widget.app, track: track, size: 240),
          const SizedBox(height: 24),
          Text(
            track.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text('${track.artist} · ${track.album}', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            [
              track.remote['format'],
              if (track.remote['sampleRate'] != null)
                '${track.remote['sampleRate']} Hz',
              if (track.remote['bitrate'] != null)
                '${track.remote['bitrate']} bps',
            ].whereType<Object>().join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
      final lyricView = FutureBuilder<String?>(
        future: lyrics,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError ||
              snapshot.data == null ||
              snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.hasError ? '歌词获取失败，请检查网络或来源登录状态' : '当前歌曲没有可用歌词',
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      lyrics = widget.app.loadLyrics(track);
                    }),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          return LyricsView(
            text: snapshot.data!,
            position: widget.app.playback.position,
            onSeek: (position) => widget.app.playback.seek(position),
          );
        },
      );
      return Scaffold(
        appBar: AppBar(
          title: const Text('正在播放'),
          actions: [
            IconButton(
              tooltip: '导入这首歌的歌词',
              icon: const Icon(Icons.note_add_outlined),
              onPressed: () async {
                try {
                  await widget.app.attachLyrics(track);
                  if (mounted) {
                    setState(() {
                      lyrics = widget.app.loadLyrics(track);
                    });
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('歌词导入失败，请使用 UTF-8 编码的 LRC 或文本文件'),
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: ClipRect(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
                  child: Opacity(
                    opacity: .13,
                    child: AnimatedBuilder(
                      animation: motion,
                      builder: (context, _) => Transform.scale(
                        scale: MediaQuery.disableAnimationsOf(context)
                            ? 1.1
                            : 1.1 + motion.value * .15,
                        child: CoverArt(
                          app: widget.app,
                          track: track,
                          size: MediaQuery.sizeOf(context).width,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, size) => size.maxWidth > 850
                        ? Row(
                            children: [
                              Expanded(
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: art,
                                  ),
                                ),
                              ),
                              Expanded(child: lyricView),
                            ],
                          )
                        : ListView(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: art,
                              ),
                              SizedBox(height: 300, child: lyricView),
                            ],
                          ),
                  ),
                ),
                PlayerBar(app: widget.app),
              ],
            ),
          ],
        ),
      );
    },
  );
}
