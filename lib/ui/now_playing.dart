import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/player_layout.dart';
import 'app_theme.dart';
import 'cover_palette.dart';
import 'lyrics_page.dart';
import 'player_layout/layout_editor.dart';
import 'player_scene.dart';
import 'player_visuals.dart';
import 'song_info_sheet.dart';
import 'system_bars.dart';

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key, required this.app});
  final SylphyApp app;
  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  String? lyricsKey;
  Future<String?>? lyrics;
  String? _paletteKey;
  Future<ColorScheme?>? _paletteFuture;
  double _dragOffset = 0;
  bool _dragging = false;
  double _horizontalOffset = 0;
  bool _openingLyrics = false;
  @override
  void initState() {
    super.initState();
    widget.app.assets.addListener(_assetChanged);
  }

  void _assetChanged() {
    final track = widget.app.playback.current,
        change = widget.app.assets.lastChange;
    if (track == null) return;
    if (change != null &&
        (change.sourceId != track.ref.sourceId ||
            (change.key != widget.app.artwork.key(track) &&
                change.key != widget.app.lyrics.key(track) &&
                change.key != widget.app.lyrics.manualKey(track)))) {
      return;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.app.assets.removeListener(_assetChanged);
    super.dispose();
  }

  PlayerLayout get _layout =>
      widget.app.playerLayouts.active ?? playerTemplate();

  Future<ColorScheme?> _paletteFor(Track track, Brightness brightness) {
    final key =
        '${track.ref.key}/${track.artworkVersion}/${widget.app.artwork.revision(track)}/${brightness.name}';
    if (_paletteKey != key) {
      _paletteKey = key;
      _paletteFuture = _loadPalette(track, brightness);
    }
    return _paletteFuture!;
  }

  Future<ColorScheme?> _loadPalette(Track track, Brightness brightness) async {
    final file = await widget.app.artwork.load(track);
    if (file == null) return null;
    return coverColorScheme(file, brightness: brightness);
  }

  ColorScheme _withCoverPalette(ColorScheme base, ColorScheme? cover) {
    if (cover == null) return base;
    return base.copyWith(
      primary: cover.primary,
      onPrimary: cover.onPrimary,
      primaryContainer: cover.primaryContainer,
      onPrimaryContainer: cover.onPrimaryContainer,
      secondary: cover.secondary,
      onSecondary: cover.onSecondary,
      secondaryContainer: cover.secondaryContainer,
      onSecondaryContainer: cover.onSecondaryContainer,
      tertiary: cover.tertiary,
      onTertiary: cover.onTertiary,
      inversePrimary: cover.inversePrimary,
      surfaceTint: cover.primary,
    );
  }

  Future<void> _openLyrics(
    Track track,
    ThemeData theme,
    PlayerLayout layout,
  ) async {
    if (_openingLyrics) return;
    _openingLyrics = true;
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => LyricsPage(
            app: widget.app,
            track: track,
            theme: theme,
            lyrics: lyrics,
            background: layout.background,
            backgroundOpacity: layout.backgroundOpacity,
          ),
        ),
      );
    } finally {
      _openingLyrics = false;
    }
    if (mounted && widget.app.playback.currentRef == track.ref) {
      setState(() {
        lyrics = widget.app.loadLyrics(track);
      });
    }
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _horizontalOffset = 0;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (details.delta.dx < 0) {
      _horizontalOffset += details.delta.dx;
    }
  }

  void _onHorizontalDragEnd(
    DragEndDetails details,
    Track track,
    ThemeData theme,
    PlayerLayout layout,
  ) {
    final velocity = details.primaryVelocity ?? 0;
    final open = _horizontalOffset < -56 || velocity < -500;
    _horizontalOffset = 0;
    if (open) _openLyrics(track, theme, layout);
  }

  void _onHorizontalDragCancel() {
    _horizontalOffset = 0;
  }

  Future<void> _openEditor(
    Track track,
    ThemeData theme,
    PlayerLayout layout,
  ) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerLayoutEditor(
          app: widget.app,
          initial: layout,
          theme: theme,
          track: track,
          lyrics: lyrics,
        ),
      ),
    );
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _dragging = true;
    if (_dragOffset != 0) setState(() => _dragOffset = 0);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (details.delta.dy <= 0) return;
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dy).clamp(0.0, 220.0);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _dragging = false;
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > 110 || velocity > 700) {
      Navigator.maybePop(context);
      return;
    }
    if (_dragOffset != 0) setState(() => _dragOffset = 0);
  }

  void _onVerticalDragCancel() {
    _dragging = false;
    if (_dragOffset != 0) setState(() => _dragOffset = 0);
  }

  void _showSongInfo(Track track) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SongInfoSheet(
      track: track,
      source: widget.app.sources
          .where((source) => source.id == track.ref.sourceId)
          .firstOrNull,
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      widget.app.playback,
      widget.app.appearance,
      widget.app.playerLayouts,
    ]),
    builder: (context, _) {
      final track = widget.app.playback.current;
      if (track == null) {
        return const Scaffold(
          body: SafeArea(child: Center(child: Text('队列为空'))),
        );
      }
      final nextLyricsKey =
          '${track.ref.key}/${track.resourceVersion}/${widget.app.lyrics.revision(track)}';
      if (lyricsKey != nextLyricsKey) {
        lyricsKey = nextLyricsKey;
        lyrics = widget.app.loadLyrics(track);
      }
      final layout = _layout;
      final brightness = Theme.of(context).brightness;
      // Share the global charcoal surfaces with the immersive player.
      final baseTheme = sylphyTheme(widget.app.appearance, brightness);
      final baseScheme = baseTheme.colorScheme;
      return FutureBuilder<ColorScheme?>(
        future: _paletteFor(track, brightness),
        builder: (context, paletteSnapshot) {
          final scheme = _withCoverPalette(baseScheme, paletteSnapshot.data);
          final theme = baseTheme.copyWith(
            colorScheme: scheme,
            scaffoldBackgroundColor: scheme.surface,
          );
          return Theme(
            data: theme,
            child: AppSystemBars(
              child: Scaffold(
                body: Stack(
                  children: [
                    Positioned.fill(
                      child: ExcludeSemantics(
                        child: PlayerBackdrop(
                          app: widget.app,
                          track: track,
                          background: layout.background,
                          opacity: layout.backgroundOpacity,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragStart: _onVerticalDragStart,
                        onVerticalDragUpdate: _onVerticalDragUpdate,
                        onVerticalDragEnd: _onVerticalDragEnd,
                        onVerticalDragCancel: _onVerticalDragCancel,
                        child: AnimatedContainer(
                          duration:
                              MediaQuery.disableAnimationsOf(context) ||
                                  _dragging
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          transform: Matrix4.translationValues(
                            0,
                            _dragOffset,
                            0,
                          ),
                          child: SafeArea(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onHorizontalDragStart: _onHorizontalDragStart,
                              onHorizontalDragUpdate: _onHorizontalDragUpdate,
                              onHorizontalDragEnd: (details) =>
                                  _onHorizontalDragEnd(
                                    details,
                                    track,
                                    theme,
                                    layout,
                                  ),
                              onHorizontalDragCancel: _onHorizontalDragCancel,
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 1200,
                                  ),
                                  child: PlayerScene(
                                    app: widget.app,
                                    layout: layout,
                                    track: track,
                                    lyrics: lyrics,
                                    onOpenLyrics: () =>
                                        _openLyrics(track, theme, layout),
                                    onOpenEditor: () =>
                                        _openEditor(track, theme, layout),
                                    onQuality: () => _showSongInfo(track),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
