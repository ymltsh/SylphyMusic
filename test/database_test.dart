import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/data/app_db.dart';

void main() {
  late Directory root;
  late AppDb db;
  const source = SourceProfile(
    id: 'source',
    name: 'Source',
    kind: SourceKind.emby,
    url: 'https://example.invalid',
    username: 'test',
  );
  const a = Track(
    ref: TrackRef('source', 'a'),
    title: 'A',
    artist: 'Artist',
    album: 'Album',
    remote: {'size': 1000},
  );
  const b = Track(
    ref: TrackRef('source', 'b'),
    title: 'B',
    artist: 'Artist',
    album: 'Album',
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sylphy-db-');
    db = AppDb(root);
    await db.open();
    await db.putSource(source);
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  test(
    'v1 to v9 upgrade preserves playlist, queue and cache version baseline',
    () async {
      await db.replaceSourceTracks(source.id, [a]);
      await db.putPlaylist(
        const PlaylistModel(id: 'p', name: 'Name', kind: PlaylistKind.local),
      );
      await db.replacePlaylistKeys('p', [a.ref.key, a.ref.key]);
      await db.saveQueue(QueueSnapshot(tracks: [a.ref.key], positionMs: 1234));
      await db.db.insert('cache', {
        'track_key': a.ref.key,
        'relative_file': 'ready/test',
        'bytes': 1000,
        'sha256': 'test',
        'last_used': 1,
      });
      await db.db.execute('DROP TABLE sync_intents');
      await db.db.execute('DROP TABLE index_tracks');
      await db.db.execute('DROP TABLE index_runs');
      await db.db.execute('DROP INDEX idx_tracks_visible');
      await db.db.execute('DROP INDEX idx_blacklist_ref');
      await db.db.execute('ALTER TABLE blacklist DROP COLUMN source_id');
      await db.db.execute('ALTER TABLE blacklist DROP COLUMN id');
      await db.db.execute('ALTER TABLE playlists DROP COLUMN base_name');
      await db.db.execute('ALTER TABLE cache DROP COLUMN metadata_version');
      await db.db.execute('DROP TABLE media_assets');
      await db.db.execute('DROP TABLE media_asset_migrations');
      await db.db.execute('DROP TABLE webdav_track_tags');
      await db.db.execute('DROP TABLE cache_asset_links');
      await db.db.execute('ALTER TABLE sources DROP COLUMN webdav_base_path');
      await db.db.execute('ALTER TABLE sources DROP COLUMN webdav_max_depth');
      await db.db.execute('PRAGMA user_version=1');
      await db.close();
      db = AppDb(root);
      await db.open();
      expect((await db.playlist('p'))!.baseName, 'Name');
      expect(await db.playlistKeys('p'), [a.ref.key, a.ref.key]);
      expect((await db.queue()).positionMs, 1234);
      expect(
        (await db.db.query('cache')).single['metadata_version'],
        a.resourceVersion,
      );
      expect(await db.db.query('sync_intents'), isEmpty);
    },
  );
  test(
    'playlist entry identities survive reorder with duplicate tracks',
    () async {
      await db.putPlaylist(
        const PlaylistModel(id: 'p', name: 'Name', kind: PlaylistKind.local),
      );
      await db.replacePlaylistKeys('p', [a.ref.key, b.ref.key, a.ref.key]);
      final before = await db.db.query('playlist_items', orderBy: 'position');
      await db.replacePlaylistKeys('p', [b.ref.key, a.ref.key, a.ref.key]);
      final after = await db.db.query('playlist_items', orderBy: 'position');
      expect(
        after.map((row) => row['entry_id']).toSet(),
        before.map((row) => row['entry_id']).toSet(),
      );
      expect(after.first['entry_id'], before[1]['entry_id']);
    },
  );
  test(
    'source identity and disabled-source checks reject stale index writes',
    () async {
      await expectLater(
        db.replaceSourceTracks(source.id, [
          const Track(
            ref: TrackRef('other', 'a'),
            title: 'Bad',
            artist: '',
            album: '',
          ),
        ]),
        throwsStateError,
      );
      await db.removeSourceData(source.id);
      await expectLater(
        db.replaceSourceTracks(source.id, [a]),
        throwsStateError,
      );
      expect(await db.tracks(), isEmpty);
    },
  );
  test('corrupt queue indices and permutations are repaired safely', () {
    final queue = QueueSnapshot.fromJson({
      'tracks': [a.ref.key, b.ref.key],
      'index': 99,
      'positionMs': -1,
      'order': [8, 8],
      'history': [-1, 0, 99],
      'repeat': 'unknown',
    });
    expect(queue.index, 1);
    expect(queue.positionMs, 0);
    expect(queue.order, [0, 1]);
    expect(queue.history, [0]);
    expect(queue.repeat, RepeatKind.all);
  });
}
