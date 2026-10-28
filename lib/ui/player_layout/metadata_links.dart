import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/models.dart';
import '../../data/library_catalog.dart';
import '../library_browser.dart';
import '../track_actions.dart';
import 'metadata_text.dart';

class PlayerMetadataLinks extends StatelessWidget {
  const PlayerMetadataLinks({
    super.key,
    required this.app,
    required this.track,
    required this.style,
    required this.textAlign,
    this.preview = false,
  });

  final SylphyApp app;
  final Track? track;
  final TextStyle style;
  final TextAlign textAlign;
  final bool preview;

  void _open(BuildContext context, bool album) {
    final t = track!;
    // Match the catalog's normalization of each field independently.
    final key = album
        ? '${(t.albumArtist.isEmpty ? t.artist : t.albumArtist).trim().toLowerCase()}|${t.album.trim().toLowerCase()}'
        : t.artistGroup;
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(album ? t.album : t.artist)),
          body: LibraryBrowser(
            app: app,
            query: const CatalogQuery().songsIn(
              album ? 'album' : 'artist',
              key,
            ),
            onAction: (action, track) =>
                performTrackAction(context, app, action, track),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final artist = track?.artist ?? 'Sylphy Studio';
    final album = track?.album ?? '绿野来信';
    final alignment = Alignment(
      textAlign == TextAlign.left
          ? -1
          : textAlign == TextAlign.right
          ? 1
          : 0,
      -1,
    );
    Widget link(String text, bool isAlbum, double width) => SizedBox(
      width: width,
      child: Semantics(
        button: !preview && track != null && text.trim().isNotEmpty,
        child: MouseRegion(
          cursor: !preview && track != null && text.trim().isNotEmpty
              ? SystemMouseCursors.click
              : MouseCursor.defer,
          child: GestureDetector(
            key: ValueKey(isAlbum ? 'player-open-album' : 'player-open-artist'),
            behavior: HitTestBehavior.opaque,
            onTap: preview || track == null || text.trim().isEmpty
                ? null
                : () => _open(context, isAlbum),
            child: PlayerMetadataText(
              text: text.isEmpty ? (isAlbum ? '未知专辑' : '未知艺术家') : text,
              style: style,
              alignment: alignment,
              textAlign: textAlign,
            ),
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        double measure(String text) {
          final painter = TextPainter(
            text: TextSpan(
              text: text,
              style: DefaultTextStyle.of(context).style.merge(style),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        final artistWidth = measure(artist.isEmpty ? '未知艺术家' : artist);
        final albumWidth = measure(album.isEmpty ? '未知专辑' : album);
        final separatorWidth = measure(' · ').clamp(0.0, constraints.maxWidth);
        final available = constraints.maxWidth - separatorWidth;
        final ratio = (available / (artistWidth + albumWidth)).clamp(0.0, 1.0);
        return Align(
          alignment: alignment,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              link(artist, false, artistWidth * ratio),
              SizedBox(
                width: separatorWidth,
                child: PlayerMetadataText(
                  text: ' · ',
                  style: style,
                  alignment: alignment,
                  textAlign: TextAlign.center,
                ),
              ),
              link(album, true, albumWidth * ratio),
            ],
          ),
        );
      },
    );
  }
}
