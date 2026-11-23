import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/appearance.dart';
import '../core/models.dart';
import '../core/player_layout.dart';
import 'cover_palette.dart';
import 'design_system/adaptive_collapsing_chrome.dart';
import 'lyrics_view.dart';
import 'playback_controls.dart';
import 'player_cover.dart';
import 'player_visuals.dart';
import 'settings_controls.dart';
import 'skyline_lyrics.dart';
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
  Track? _track;
  Future<String?>? _lyrics;
  Future<String?>? _refreshing;
  (TrackRef, String, int, Brightness)? _paletteKey;
  Future<CoverPalette?>? _paletteFuture;
  bool _useOpeningTheme = true;
  bool _immersive = false;

  PlayerElement? get _playControls =>
      (widget.app.playerLayouts.active ?? playerTemplate()).elements
          .where(
            (element) => element.type == PlayerPart.controls && !element.hidden,
          )
          .firstOrNull;

  @override
  void initState() {
    super.initState();
    final track = widget.app.playback.current ?? widget.track;
    _track = track;
    _useOpeningTheme =
        track.ref == widget.track.ref &&
        track.artworkVersion == widget.track.artworkVersion;
    _lyrics =
        track.ref == widget.track.ref &&
            track.resourceVersion == widget.track.resourceVersion
        ? widget.lyrics ?? widget.app.loadLyrics(track)
        : widget.app.loadLyrics(track);
    widget.app.playback.addListener(_trackChanged);
    widget.app.assets.addListener(_assetChanged);
  }

  void _assetChanged() {
    final track = _track;
    if (!mounted || track == null) return;
    final change = widget.app.assets.lastChange;
    if (change != null && change.sourceId != track.ref.sourceId) return;
    final artworkChanged =
        change == null || change.key == widget.app.artwork.key(track);
    final lyricsChanged =
        change == null ||
        change.key == widget.app.lyrics.key(track) ||
        change.key == widget.app.lyrics.manualKey(track);
    if (!artworkChanged && !lyricsChanged) return;
    setState(() {
      if (artworkChanged) {
        _useOpeningTheme = false;
        _paletteKey = null;
      }
      if (lyricsChanged && _refreshing == null) {
        _lyrics = widget.app.loadLyrics(track);
      }
    });
  }

  void _trackChanged() {
    final current = widget.app.playback.current;
    final previous = _track;
    if (!mounted || identical(current, previous)) return;
    final changedSong = current?.ref != previous?.ref;
    setState(() {
      _track = current;
      if (changedSong ||
          current?.resourceVersion != previous?.resourceVersion) {
        _refreshing = null;
        _lyrics = current == null ? null : widget.app.loadLyrics(current);
      }
      if (changedSong || current?.artworkVersion != previous?.artworkVersion) {
        _useOpeningTheme = false;
        _paletteKey = null;
        _paletteFuture = null;
      }
    });
  }

  Future<CoverPalette?>? _paletteFor(Track? track, Brightness brightness) {
    if (_useOpeningTheme || track == null) return null;
    final key = (
      track.ref,
      track.artworkVersion,
      widget.app.artwork.revision(track),
      brightness,
    );
    if (_paletteKey != key) {
      _paletteKey = key;
      _paletteFuture = _loadPalette(track, brightness);
    }
    return _paletteFuture;
  }

  Future<CoverPalette?> _loadPalette(Track track, Brightness brightness) async {
    final file = await widget.app.artwork.load(track);
    return file == null ? null : coverColorScheme(file, brightness: brightness);
  }

  @override
  void dispose() {
    widget.app.playback.removeListener(_trackChanged);
    widget.app.assets.removeListener(_assetChanged);
    super.dispose();
  }

  Future<void> _seek(TrackRef ref, Duration position) async {
    if (_track?.ref != ref) return;
    try {
      await widget.app.playback.seek(position);
    } catch (_) {
      if (mounted && _track?.ref == ref) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('跳转失败，请重试')));
      }
    }
  }

  Future<void> _reload() async {
    final track = _track;
    if (track == null || _refreshing != null) return;
    final next = widget.app.loadLyrics(track, forceRefresh: true);
    setState(() {
      _refreshing = next;
      _lyrics = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder renders the error state.
    } finally {
      if (mounted && identical(_refreshing, next)) {
        setState(() => _refreshing = null);
      }
    }
  }

  Widget _body(Track? track) => track == null
      ? const Center(child: Text('队列为空'))
      : FutureBuilder<String?>(
          key: ValueKey(track.ref),
          future: _lyrics,
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
                        snapshot.hasError
                            ? '歌词获取失败，请检查网络或来源登录状态'
                            : '当前歌曲没有可用歌词',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _refreshing == null ? _reload : null,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final appearance = widget.app.appearance;
            final playback = widget.app.playback;
            final highlightColor = switch (appearance.lyricPageColorMode) {
              LyricColorMode.album => Theme.of(context).colorScheme.primary,
              LyricColorMode.system =>
                MediaQuery.platformBrightnessOf(context) == Brightness.dark
                    ? Colors.white
                    : Colors.black,
              LyricColorMode.fixed => appearance.lyricPageFixedColor,
            };
            final standard = LyricsView(
              key: ValueKey('lyrics/${track.ref.key}'),
              showToolbar: false,
              text: text,
              position: playback.position,
              initialFontSize: appearance.lyricFontSize,
              fontWeight: appearance.lyricPageWeight.fontWeight,
              highlightColor: highlightColor,
              onSeek: (position) => _seek(track.ref, position),
            );
            if (!appearance.lyricSkylineEnabled) return standard;
            return SkylineLyrics(
              text: text,
              position: playback.position,
              duration: playback.duration > Duration.zero
                  ? playback.duration
                  : Duration(milliseconds: track.durationMs),
              advancing: playback.playing && !playback.buffering,
              speed: playback.speed,
              fontSize: appearance.lyricFontSize,
              fontWeight: appearance.lyricPageWeight.fontWeight,
              color: highlightColor,
              untimedLyrics: standard,
            );
          },
        );

  Widget _more(BuildContext context) {
    final appearance = widget.app.appearance;
    return SylphyFoldedMoreMenu(
      tooltip: '歌词更多',
      items: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.auto_awesome_outlined),
          trailingIcon: appearance.lyricSkylineEnabled
              ? const Icon(Icons.check_rounded)
              : null,
          onPressed: () =>
              appearance.update(lyricSkyline: !appearance.lyricSkylineEnabled),
          child: const Text('浮光沉际'),
        ),
        MenuItemButton(
          leadingIcon: Icon(
            _immersive
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
          ),
          onPressed: () => setState(() => _immersive = !_immersive),
          child: Text(_immersive ? '退出沉浸模式' : '沉浸模式'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('歌词字号'),
              LyricFontSizeSlider(appearance: appearance),
            ],
          ),
        ),
        SubmenuButton(
          animated: !MediaQuery.disableAnimationsOf(context),
          leadingIcon: const Icon(Icons.format_bold_rounded),
          menuChildren: [
            for (final weight in LyricPageWeight.values)
              MenuItemButton(
                trailingIcon: appearance.lyricPageWeight == weight
                    ? const Icon(Icons.check_rounded)
                    : null,
                onPressed: () => appearance.update(lyricPageWeight: weight),
                child: Text(weight.label),
              ),
          ],
          child: const Text('歌词粗细'),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, Track? track) => Padding(
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
          track: track,
          size: 40,
          radius: 10,
          shadow: false,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track?.title ?? '歌词',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (track != null) ...[
                const SizedBox(height: 3),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: .55),
                  ),
                ),
              ],
            ],
          ),
        ),
        _more(context),
      ],
    ),
  );

  Widget _footer() => Center(
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
              child: PlayerControls(
                app: widget.app,
                radius: _playControls?.radius ?? 24,
                color: _playControls?.color,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final track = _track;
    final base = Theme.of(context);
    return FutureBuilder<CoverPalette?>(
      future: _paletteFor(track, base.brightness),
      builder: (context, snapshot) {
        final palette = snapshot.connectionState == ConnectionState.done
            ? snapshot.data
            : null;
        final theme = _useOpeningTheme
            ? widget.theme
            : palette == null
            ? base
            : base.copyWith(colorScheme: palette.applyTo(base.colorScheme));
        return Theme(
          data: theme,
          child: AnimatedBuilder(
            animation: Listenable.merge([
              widget.app.playback,
              widget.app.appearance,
              widget.app.playerLayouts,
            ]),
            builder: (context, _) => _buildPage(context, track),
          ),
        );
      },
    );
  }

  Widget _buildPage(BuildContext context, Track? track) => AppSystemBars(
    immersive: _immersive,
    child: Scaffold(
      key: const ValueKey('lyrics-page'),
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: PlayerBackdrop(
                app: widget.app,
                track: track,
                background: widget.background,
                opacity: widget.backgroundOpacity,
              ),
            ),
          ),
          SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    if (!_immersive) _header(context, track),
                    Expanded(
                      key: const ValueKey('lyrics-content'),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: _body(track),
                        ),
                      ),
                    ),
                    if (!_immersive && track != null) _footer(),
                  ],
                ),
                if (_immersive)
                  PositionedDirectional(top: 4, end: 8, child: _more(context)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
