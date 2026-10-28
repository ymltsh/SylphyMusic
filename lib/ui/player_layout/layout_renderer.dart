import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/models.dart';
import '../../core/player_layout.dart';
import '../lyrics_view.dart';
import '../playback_controls.dart';
import '../player_bar.dart';
import '../player_cover.dart';
import '../player_visuals.dart';
import '../player_favorite.dart';
import '../player_quick_actions.dart';
import 'metadata_text.dart';
import 'metadata_links.dart';

class PlayerWidgetContext {
  const PlayerWidgetContext({
    required this.app,
    this.track,
    this.lyrics,
    this.preview = false,
    this.onOpenLyrics,
    this.onOpenEditor,
    this.onQuality,
  });
  final SylphyApp app;
  final Track? track;
  final Future<String?>? lyrics;
  final bool preview;
  final VoidCallback? onOpenLyrics;
  final VoidCallback? onOpenEditor, onQuality;
}

typedef PlayerWidgetBuilder = Widget Function(
  BuildContext,
  PlayerElement,
  PlayerWidgetContext,
);

/// Both the editor and normal playback use this single registry.
class PlayerWidgetRegistry {
  static final Map<PlayerPart, PlayerWidgetBuilder> builders = {
    PlayerPart.cover: (context, element, data) => LayoutBuilder(
      builder: (context, size) {
        final side = math.min(size.maxWidth, size.maxHeight);
        return Center(
          child: PlayerCover(
            key: ValueKey('cover/${element.id}'),
            app: data.app,
            track: data.track,
            size: side,
            circle: data.app.appearance.disc,
            radius: element.radius,
            rotate: data.app.appearance.discRotation,
            playing: data.app.playback.playing,
            preview: data.preview,
          ),
        );
      },
    ),
    PlayerPart.title: (context, e, data) =>
        _text(context, e, data.track?.title ?? '风穿过森林', bold: true),
    PlayerPart.artist: (context, e, data) => PlayerMetadataLinks(
      app: data.app,
      track: data.track,
      preview: data.preview,
      textAlign: e.align == 'left'
          ? TextAlign.left
          : e.align == 'right'
          ? TextAlign.right
          : TextAlign.center,
      style: TextStyle(
        fontSize: e.fontSize,
        color: e.color == null
            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: .68)
            : Color(e.color!),
      ),
    ),
    PlayerPart.lyrics: (context, e, data) => _lyrics(context, e, data),
    PlayerPart.progress: (context, e, data) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: PlayerProgress(
          app: data.app,
          preview: data.preview,
          color: e.color,
        ),
      ),
    ),
    PlayerPart.controls: (context, e, data) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: PlayerControls(
          app: data.app,
          preview: data.preview,
          color: e.color,
          radius: e.radius,
          playWidth: e.playWidth,
          playHeight: e.playHeight,
          spacing: e.controlSpacing,
        ),
      ),
    ),
    PlayerPart.queue: (context, e, data) => Center(
      child: IconButton(
        tooltip: '播放队列',
        color: e.color == null ? null : Color(e.color!),
        onPressed: data.preview
            ? () {}
            : () => PlayerBar(app: data.app).showQueue(context),
        icon: const Icon(Icons.queue_music_rounded),
      ),
    ),
    PlayerPart.favorite: (context, e, data) => Center(
      child: data.preview || data.track == null
          ? Icon(
              Icons.favorite_border_rounded,
              color: e.color == null ? null : Color(e.color!),
            )
          : PlayerFavorite(app: data.app, track: data.track!),
    ),
    PlayerPart.decoration: (context, e, data) => DecoratedBox(
      decoration: BoxDecoration(
        color: e.color == null
            ? Theme.of(context).colorScheme.primaryContainer
            : Color(e.color!),
        borderRadius: BorderRadius.circular(e.radius),
      ),
    ),
  };

  static Widget build(
    BuildContext context,
    PlayerElement element,
    PlayerWidgetContext data,
  ) => Opacity(
    opacity: element.opacity,
    child: builders[element.type]!(context, element, data),
  );

  static Widget _lyrics(
    BuildContext context,
    PlayerElement e,
    PlayerWidgetContext data,
  ) {
    final scheme = Theme.of(context).colorScheme;
    Widget message(String text) => Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: scheme.onSurface.withValues(alpha: .55),
          fontSize: 13,
        ),
      ),
    );
    final content = data.lyrics == null
        ? message('暂无歌词 · 点击查看')
        : FutureBuilder<String?>(
            future: data.lyrics,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: e.color == null ? null : Color(e.color!),
                    ),
                  ),
                );
              }
              final text = snapshot.data?.trim();
              if (snapshot.hasError || text == null || text.isEmpty) {
                return Center(
                  child: Text(
                    snapshot.hasError ? '歌词加载失败 · 点击查看' : '暂无歌词 · 点击查看',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: .55),
                      fontSize: 13,
                    ),
                  ),
                );
              }
              return LyricsPreview(
                key: ValueKey('lyrics-preview/${e.id}'),
                text: text,
                position: data.app.playback.position,
                fontSize: data.app.appearance.miniLyricFontSize,
                lineHeight: e.lyricLineHeight,
                highlightColor: e.color == null ? null : Color(e.color!),
              );
            },
          );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('open-lyrics/${e.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: data.preview ? null : data.onOpenLyrics,
        child: content,
      ),
    );
  }

  static Widget _text(
    BuildContext context,
    PlayerElement e,
    String text, {
    bool bold = false,
  }) => PlayerMetadataText(
    text: text,
    maxLines: bold ? 2 : 1,
    alignment: Alignment(
      e.align == 'left'
          ? -1
          : e.align == 'right'
          ? 1
          : 0,
      e.type == PlayerPart.title
          ? 1
          : e.type == PlayerPart.artist
          ? -1
          : 0,
    ),
    textAlign: e.align == 'left'
        ? TextAlign.left
        : e.align == 'right'
        ? TextAlign.right
        : TextAlign.center,
    style: TextStyle(
      fontSize: e.fontSize,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: e.color == null
          ? Theme.of(context).colorScheme.onSurface
                .withValues(alpha: bold ? 1 : .68)
          : Color(e.color!),
    ),
  );
}

class PlayerLayoutBackground extends StatelessWidget {
  const PlayerLayoutBackground({
    super.key,
    required this.layout,
    required this.data,
  });
  final PlayerLayout layout;
  final PlayerWidgetContext data;
  @override
  Widget build(BuildContext context) {
    return PlayerBackdrop(
      app: data.app,
      track: data.track,
      background: layout.background,
      opacity: layout.backgroundOpacity,
    );
  }
}

class PlayerLayoutRenderer extends StatelessWidget {
  const PlayerLayoutRenderer({
    super.key,
    required this.layout,
    required this.data,
    this.drawBackground = true,
  });
  final PlayerLayout layout;
  final PlayerWidgetContext data;
  final bool drawBackground;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(
        math.max(1, constraints.maxWidth),
        math.max(1, constraints.maxHeight),
      );
      return SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          children: [
            if (drawBackground)
              Positioned.fill(
                child: PlayerLayoutBackground(layout: layout, data: data),
              ),
            for (final e in layout.elements.where((e) => !e.hidden))
              Positioned.fromRect(
                key: ValueKey('player-element/${e.id}'),
                rect: layout.bounds(e, size),
                child: PlayerWidgetRegistry.build(context, e, data),
              ),
            Positioned.fromRect(
              rect: layout.actionBounds(size),
              child: PlayerQuickActions(
                app: data.app,
                track: data.track,
                preview: data.preview,
                onOpenLyrics: data.onOpenLyrics,
                onOpenEditor: data.onOpenEditor,
                onQuality: data.onQuality,
              ),
            ),
          ],
        ),
      );
    },
  );
}
