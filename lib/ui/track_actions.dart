import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'playlist_picker_sheet.dart';

Future<void> performTrackAction(
  BuildContext context,
  SylphyApp app,
  String action,
  Track track,
) async {
  switch (action) {
    case 'favorite':
      await app.toggleFavorite(track);
    case 'cache':
      await app.cacheTrack(track);
    case 'next':
      await app.playback.enqueue(track.ref, next: true);
    case 'enqueue':
      await app.playback.enqueue(track.ref);
    case 'block':
      await app.toggleBlacklist(track);
    case 'playlist':
      final candidates = app.playlists.where(
        (p) =>
            (p.kind != PlaylistKind.favorites || p.sourceId == null) &&
            (p.kind != PlaylistKind.cloud ||
                (p.sourceId == track.ref.sourceId &&
                    p.status != SyncStatus.readonly &&
                    p.status != SyncStatus.syncing &&
                    app.sources.any(
                      (s) => s.id == p.sourceId && s.kind.cloudPlaylistWritable,
                    ))),
      );
      final chosen = await showPlaylistPickerSheet(
        context,
        candidates: candidates.toList(),
        sources: app.sources,
        trackCount: 1,
        trackTitle: track.title,
      );
      if (chosen == null) return;
      await appendToPlaylistChoice(app, chosen, [track.ref]);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已添加到歌单')));
      }
  }
}
