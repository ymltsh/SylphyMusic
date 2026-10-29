import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';

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
            p.kind != PlaylistKind.cloud ||
            (p.sourceId == track.ref.sourceId &&
                p.status != SyncStatus.readonly &&
                p.status != SyncStatus.syncing &&
                app.sources.any(
                  (s) => s.id == p.sourceId && s.kind.cloudPlaylistWritable,
                )),
      );
      final chosen = await showDialog<PlaylistModel>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('添加到歌单'),
          children: candidates
              .map(
                (p) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, p),
                  child: Text(
                    '${p.name}${p.kind == PlaylistKind.cloud ? ' · 云端' : ''}',
                  ),
                ),
              )
              .toList(),
        ),
      );
      if (chosen == null) return;
      final keys = await app.db.playlistKeys(chosen.id);
      keys.add(track.ref.key);
      await app.setPlaylistKeys(chosen, keys);
  }
}
