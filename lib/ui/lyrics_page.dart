import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/appearance.dart';
import '../core/models.dart';
import '../core/player_layout.dart';
import 'lyrics_view.dart';
import 'playback_controls.dart';
import 'player_cover.dart';
import 'player_visuals.dart';
import 'system_bars.dart';

/// The single full-lyrics surface. Every entry point (the compact preview in a
/// layout and the player menu) pushes this page, so there is no second modal
/// implementation with different colours, controls or dismissal behaviour.
class LyricsPage extends StatefulWidget {
  const LyricsPage({
    super.key,
    required this.app,
    required this.track,
    required this.theme,
    required this.lyrics,
    this.background = PlayerBackground.album,
    this.backgroundOpacity = .65,
  });
  final SylphyApp app;
  final Track track;
  final ThemeData theme;
  final Future<String?>? lyrics;
  final PlayerBackground background;
  final double backgroundOpacity;
  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  late Future<String?> lyrics =
      widget.lyrics ?? widget.app.loadLyrics(widget.track);
  bool busy = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    widget.app.playback.addListener(_trackChanged);
    widget.app.assets.addListener(_assetChanged);
  }

  void _assetChanged() {
    final change = widget.app.assets.lastChange;
    if (change != null &&
        (change.sourceId != widget.track.ref.sourceId ||
            (change.key != widget.app.lyrics.key(widget.track) &&
                change.key != widget.app.lyrics.manualKey(widget.track)))) {
      return;
    }
    if (mounted) {
      setState(() {
        lyrics = widget.app.loadLyrics(widget.track);
      });
    }
  }

  void _trackChanged() {
    if (!mounted || _leaving) return;
    final current = widget.app.playback.current;
    if (current?.ref == widget.track.ref) return;
    // The page owns a fixed theme and lyric future. Leave it rather than
    // showing a stale song after next / automatic advance.
    _leaving = true;
    Navigator.maybePop(context);
  }

  @override
  void dispose() {
    widget.app.playback.removeListener(_trackChanged);
    widget.app.assets.removeListener(_assetChanged);
    super.dispose();
  }

  Future<void> _seek(Duration position) async {
    try {
      await widget.app.playback.seek(position);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('跳转失败，请重试')));
      }
    }
  }

  Future<void> _reload() async {
    if (busy) return;
    final next = widget.app.loadLyrics(widget.track, forceRefresh: true);
    setState(() {
      busy = true;
      lyrics = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder renders the error state.
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _body(BuildContext context) => FutureBuilder<String?>(
    future: lyrics,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      final text = snapshot.data?.trim();
      if (snapshot.hasError || text == null || text.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lyrics_outlined, size: 40),
                const SizedBox(height: 16),
                Text(
                  snapshot.hasError ? '歌词获取失败，请检查网络或来源登录状态' : '当前歌曲没有可用歌词',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: busy ? null : _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        );
      }
      return LyricsView(
        key: ValueKey('lyrics/${widget.track.ref.key}'),
        showToolbar: false,
        text: text,
        position: widget.app.playback.position,
        initialFontSize: widget.app.appearance.lyricFontSize,
        highlightColor: switch (widget.app.appearance.lyricPageColorMode) {
          LyricColorMode.album => Theme.of(context).colorScheme.primary,
          LyricColorMode.system =>
            MediaQuery.platformBrightnessOf(context) == Brightness.dark
                ? Colors.white
                : Colors.black,
          LyricColorMode.fixed => widget.app.appearance.lyricPageFixedColor,
        },
        onSeek: _seek,
      );
    },
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.app.playback, widget.app.appearance]),
    builder: (context, _) => Theme(
      data: widget.theme,
      child: Builder(
        builder: (context) => AppSystemBars(
          child: Scaffold(
            key: const ValueKey('lyrics-page'),
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: PlayerBackdrop(
                      app: widget.app,
                      track: widget.track,
                      background: widget.background,
                      opacity: widget.backgroundOpacity,
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: '返回播放页',
                              onPressed: () => Navigator.maybePop(context),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            const SizedBox(width: 4),
                            PlayerCover(
                              app: widget.app,
                              track: widget.track,
                              size: 40,
                              circle: widget.app.appearance.disc,
                              radius: 10,
                              shadow: false,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: .55),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<double>(
                              tooltip: '完整歌词字号',
                              icon: const Icon(Icons.text_fields_rounded),
                              initialValue: widget.app.appearance.lyricFontSize,
                              onSelected: (size) =>
                                  widget.app.appearance.update(lyricFont: size),
                              itemBuilder: (_) => [
                                for (final entry in {
                                  20.0: '小',
                                  24.0: '标准',
                                  28.0: '大',
                                }.entries)
                                  CheckedPopupMenuItem(
                                    value: entry.key,
                                    checked:
                                        widget.app.appearance.lyricFontSize ==
                                        entry.key,
                                    child: Text(entry.value),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: _body(context),
                          ),
                        ),
                      ),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PlayerProgress(app: widget.app),
                                SizedBox(
                                  height: 72,
                                  child: PlayerControls(app: widget.app),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
