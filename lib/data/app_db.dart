import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../core/models.dart';

class AppDb {
  static const _assetsTable = '''CREATE TABLE media_assets(
    source_id TEXT NOT NULL,asset_key TEXT NOT NULL,kind TEXT NOT NULL,
    version TEXT NOT NULL,relative_file TEXT NOT NULL,bytes INTEGER NOT NULL,
    sha256 TEXT NOT NULL,fetched_at INTEGER NOT NULL,last_used INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,pinned INTEGER NOT NULL DEFAULT 0,
    etag TEXT,last_modified TEXT,PRIMARY KEY(source_id,asset_key))''';
  static const _assetsIndex =
      'CREATE INDEX idx_assets_lru ON media_assets(kind,pinned,last_used)';
  static const _assetMigrations =
      'CREATE TABLE media_asset_migrations(source_id TEXT NOT NULL,asset_key TEXT NOT NULL,PRIMARY KEY(source_id,asset_key))';
  static const _indexRuns =
      'CREATE TABLE index_runs(source_id TEXT PRIMARY KEY,run_id TEXT NOT NULL)';
  static Future<void> _catalogSchema(DatabaseExecutor d) async {
    await d.execute(
      "ALTER TABLE blacklist ADD COLUMN source_id TEXT NOT NULL DEFAULT ''",
    );
    await d.execute(
      "ALTER TABLE blacklist ADD COLUMN id TEXT NOT NULL DEFAULT ''",
    );
    for (final row in await d.query('blacklist')) {
      final ref = TrackRef.parse(row['track_key'] as String);
      await d.update(
        'blacklist',
        {'source_id': ref.sourceId, 'id': ref.id},
        where: 'track_key=?',
        whereArgs: [ref.key],
      );
    }
    await d.execute(
      'CREATE INDEX idx_blacklist_ref ON blacklist(source_id,id)',
    );
    await d.execute('CREATE INDEX idx_tracks_visible ON tracks(missing,title)');
  }

  static const _trackColumns =
      'source_id,id,title,artist,album,album_artist,duration_ms,cover_id,year,disc,number,remote_json,missing';
  static const _stageTable = '''CREATE TABLE index_tracks AS
    SELECT CAST('' AS TEXT) AS run_id, tracks.* FROM tracks WHERE 0''';
  static const _stageIndex =
      'CREATE UNIQUE INDEX idx_index_identity ON index_tracks(run_id,source_id,id)';
  static bool _desktopInitialized = false;
  static const _intentTable =
      '''CREATE TABLE sync_intents(playlist_id TEXT PRIMARY KEY,
    before_json TEXT NOT NULL, local_json TEXT NOT NULL, desired_json TEXT NOT NULL,
    before_name TEXT NOT NULL, desired_name TEXT NOT NULL)''';
  AppDb(this.root);
  final Directory root;
  late final Database db;
  Future<void> open() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux) &&
        !_desktopInitialized) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _desktopInitialized = true;
    }
    await root.create(recursive: true);
    db = await openDatabase(
      p.join(root.path, 'sylphy.sqlite'),
      version: 6,
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute(
            "ALTER TABLE playlists ADD COLUMN base_name TEXT NOT NULL DEFAULT ''",
          );
          await database.execute('UPDATE playlists SET base_name=name');
        }
        if (oldVersion < 3) await database.execute(_intentTable);
        if (oldVersion < 4) {
          await database.execute(
            "ALTER TABLE cache ADD COLUMN metadata_version TEXT NOT NULL DEFAULT ''",
          );
          for (final row in await database.query('cache')) {
            final ref = TrackRef.parse(row['track_key'] as String);
            final tracks = await database.query(
              'tracks',
              where: 'source_id=? AND id=?',
              whereArgs: [ref.sourceId, ref.id],
              limit: 1,
            );
            if (tracks.isNotEmpty) {
              await database.update(
                'cache',
                {
                  'metadata_version': Track.fromRow(tracks.first)
                      .resourceVersion,
                },
                where: 'track_key=?',
                whereArgs: [ref.key],
              );
            }
          }
        }
        if (oldVersion < 5) {
          await database.execute(_stageTable);
          await database.execute(_stageIndex);
          await database.execute(_indexRuns);
          await _catalogSchema(database);
        }
        if (oldVersion < 6) {
          await database.execute(_assetsTable);
          await database.execute(_assetsIndex);
          await database.execute(_assetMigrations);
        }
      },
      onCreate: (d, v) async {
        for (final sql in <String>[
          '''CREATE TABLE sources(id TEXT PRIMARY KEY, name TEXT NOT NULL,kind TEXT NOT NULL,url TEXT NOT NULL,username TEXT NOT NULL,remote_user_id TEXT NOT NULL DEFAULT '',enabled INTEGER NOT NULL DEFAULT 1,last_sync INTEGER NOT NULL DEFAULT 0)''',
          '''CREATE TABLE tracks(source_id TEXT NOT NULL,id TEXT NOT NULL,title TEXT,artist TEXT,album TEXT,album_artist TEXT,duration_ms INTEGER,cover_id TEXT,year INTEGER,disc INTEGER,number INTEGER,remote_json TEXT,missing INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(source_id,id))''',
          '''CREATE TABLE playlists(id TEXT PRIMARY KEY,name TEXT NOT NULL,kind TEXT NOT NULL,source_id TEXT,remote_id TEXT,status TEXT NOT NULL DEFAULT 'synced',base_json TEXT NOT NULL DEFAULT '[]',message TEXT NOT NULL DEFAULT '')''',
          '''CREATE TABLE playlist_items(playlist_id TEXT NOT NULL,entry_id TEXT NOT NULL,position INTEGER NOT NULL,track_key TEXT NOT NULL,PRIMARY KEY(playlist_id,entry_id))''',
          '''CREATE INDEX idx_playlist_pos ON playlist_items(playlist_id,position)''',
          '''CREATE TABLE blacklist(track_key TEXT PRIMARY KEY)''',
          '''CREATE TABLE cache(track_key TEXT PRIMARY KEY,relative_file TEXT NOT NULL,bytes INTEGER NOT NULL,sha256 TEXT NOT NULL,last_used INTEGER NOT NULL,resource_tag TEXT NOT NULL DEFAULT '')''',
          '''CREATE INDEX idx_cache_lru ON cache(last_used)''',
          '''CREATE TABLE cache_jobs(id TEXT PRIMARY KEY,label TEXT NOT NULL,state TEXT NOT NULL,created INTEGER NOT NULL)''',
          '''CREATE TABLE cache_job_items(job_id TEXT NOT NULL,position INTEGER NOT NULL,track_key TEXT NOT NULL,state TEXT NOT NULL DEFAULT 'pending',error TEXT NOT NULL DEFAULT '',PRIMARY KEY(job_id,position))''',
          '''CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)''',
          '''ALTER TABLE playlists ADD COLUMN base_name TEXT NOT NULL DEFAULT '' ''',
          _intentTable,
          '''ALTER TABLE cache ADD COLUMN metadata_version TEXT NOT NULL DEFAULT '' ''',
          _stageTable,
          _stageIndex,
          _indexRuns,
          _assetsTable,
          _assetsIndex,
          _assetMigrations,
        ]) {
          await d.execute(sql);
        }
        await _catalogSchema(d);
      },
    );
    // A killed process never exposes an incomplete remote snapshot. Its staging
    // data is discarded; the next sync starts a fresh server pagination pass.
    await db.delete('index_tracks');
    await db.insert(
      'playlists',
      const PlaylistModel(
        id: 'favorites',
        name: '我的收藏',
        kind: PlaylistKind.favorites,
      ).toRow(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> close() => db.close();
  Future<List<SourceProfile>> sources() async => (await db.query(
    'sources',
    orderBy: 'name',
  )).map(SourceProfile.fromRow).toList();
  Future<SourceProfile?> source(String id) async {
    final r = await db.query(
      'sources',
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    return r.isEmpty ? null : SourceProfile.fromRow(r.first);
  }

  Future<void> putSource(SourceProfile source) async => db.insert(
    'sources',
    source.toRow(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  Future<void> updateSyncTime(String sourceId) async => db.update(
    'sources',
    {'last_sync': DateTime.now().millisecondsSinceEpoch},
    where: 'id=?',
    whereArgs: [sourceId],
  );
  Future<void> replaceSourceTracks(String id, List<Track> tracks) async {
    if (tracks.any((track) => track.ref.sourceId != id)) {
      throw StateError('索引包含其他来源的歌曲');
    }
    await db.transaction((tx) async {
      final source = await tx.query(
        'sources',
        where: 'id=? AND enabled=1',
        whereArgs: [id],
        limit: 1,
      );
      if (source.isEmpty) throw StateError('来源已停用或移除，已丢弃过期索引结果');
      await tx.update(
        'tracks',
        {'missing': 1},
        where: 'source_id=?',
        whereArgs: [id],
      );
      final batch = tx.batch();
      for (final track in tracks) {
        batch.insert(
          'tracks',
          track.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
    await updateSyncTime(id);
  }

  Future<void> stageIndexPage(
    String runId,
    String sourceId,
    List<Track> page,
  ) async {
    if (page.any((track) => track.ref.sourceId != sourceId)) {
      throw StateError('索引包含其他来源的歌曲');
    }
    await db.transaction((tx) async {
      final batch = tx.batch();
      for (final track in page) {
        batch.insert('index_tracks', {'run_id': runId, ...track.toRow()});
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> discardIndex(String runId) =>
      db.delete('index_tracks', where: 'run_id=?', whereArgs: [runId]);

  Future<void> commitIndex(String runId, SourceProfile original) async {
    await db.transaction((tx) async {
      final rows = await tx.query(
        'sources',
        where: 'id=?',
        whereArgs: [original.id],
      );
      if (rows.isEmpty) throw StateError('来源已移除，已丢弃过期索引结果');
      final current = SourceProfile.fromRow(rows.single);
      if (!current.enabled ||
          current.url != original.url ||
          current.username != original.username ||
          current.kind != original.kind) {
        throw StateError('来源连接已变更或停用，已丢弃过期索引结果');
      }
      await tx.update(
        'tracks',
        {'missing': 1},
        where: 'source_id=?',
        whereArgs: [original.id],
      );
      await tx.rawInsert(
        'INSERT OR REPLACE INTO tracks ($_trackColumns) SELECT $_trackColumns FROM index_tracks WHERE run_id=?',
        [runId],
      );
      await tx.update(
        'sources',
        {'last_sync': DateTime.now().millisecondsSinceEpoch},
        where: 'id=?',
        whereArgs: [original.id],
      );
      await tx.delete('index_tracks', where: 'run_id=?', whereArgs: [runId]);
    });
  }

  Future<List<Track>> tracks({
    bool includeMissing = false,
    String? sourceId,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (!includeMissing) where.add('missing=0');
    if (sourceId != null) {
      where.add('source_id=?');
      args.add(sourceId);
    }
    return (await db.query(
      'tracks',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'title COLLATE NOCASE',
    )).map(Track.fromRow).toList();
  }

  Future<Track?> track(TrackRef ref) async {
    final a = await db.query(
      'tracks',
      where: 'source_id=? AND id=?',
      whereArgs: [ref.sourceId, ref.id],
      limit: 1,
    );
    return a.isEmpty ? null : Track.fromRow(a.first);
  }

  Future<List<PlaylistModel>> playlists() async => (await db.query(
    'playlists',
    orderBy: "CASE kind WHEN 'favorites' THEN 0 WHEN 'local' THEN 1 ELSE 2 END,name COLLATE NOCASE",
  )).map(PlaylistModel.fromRow).toList();
  Future<PlaylistModel?> playlist(String id) async {
    final r = await db.query(
      'playlists',
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    return r.isEmpty ? null : PlaylistModel.fromRow(r.first);
  }

  Future<void> putPlaylist(PlaylistModel p) async => db.insert(
    'playlists',
    p.toRow(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  Future<({int count, String? firstKey})> playlistPreview(String id) async {
    final row = (await db.rawQuery(
      'SELECT COUNT(*) AS count, '
      '(SELECT track_key FROM playlist_items WHERE playlist_id=? '
      'ORDER BY position LIMIT 1) AS first_key '
      'FROM playlist_items WHERE playlist_id=?',
      [id, id],
    )).single;
    return (count: row['count'] as int, firstKey: row['first_key'] as String?);
  }

  Future<List<String>> playlistKeys(String id) async => (await db.query(
    'playlist_items',
    columns: ['track_key'],
    where: 'playlist_id=?',
    whereArgs: [id],
    orderBy: 'position',
  )).map((r) => r['track_key'] as String).toList();
  Future<void> replacePlaylistKeys(String id, List<String> keys) async {
    await db.transaction((tx) => _replacePlaylistKeys(tx, id, keys));
  }

  Future<void> savePlaylistSnapshot(
    PlaylistModel playlist,
    List<String> keys,
  ) async {
    await db.transaction((tx) async {
      await tx.insert(
        'playlists',
        playlist.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _replacePlaylistKeys(tx, playlist.id, keys);
    });
  }

  Future<void> _replacePlaylistKeys(
    DatabaseExecutor tx,
    String id,
    List<String> keys,
  ) async {
    final old = await tx.query(
      'playlist_items',
      where: 'playlist_id=?',
      whereArgs: [id],
      orderBy: 'position',
    );
    final available = <String, List<String>>{};
    for (final row in old) {
      available
          .putIfAbsent(row['track_key'] as String, () => [])
          .add(row['entry_id'] as String);
    }
    await tx.delete('playlist_items', where: 'playlist_id=?', whereArgs: [id]);
    final batch = tx.batch();
    for (var index = 0; index < keys.length; index++) {
      final ids = available[keys[index]];
      batch.insert('playlist_items', {
        'playlist_id': id,
        'entry_id': ids != null && ids.isNotEmpty
            ? ids.removeAt(0)
            : const Uuid().v4(),
        'position': index,
        'track_key': keys[index],
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> removePlaylist(String id) async {
    if (id == 'favorites') return;
    await db.transaction((tx) async {
      await tx.delete('sync_intents', where: 'playlist_id=?', whereArgs: [id]);
      await tx.delete(
        'playlist_items',
        where: 'playlist_id=?',
        whereArgs: [id],
      );
      await tx.delete('playlists', where: 'id=?', whereArgs: [id]);
    });
  }

  Future<bool> blocked(TrackRef r) async => (await db.query(
    'blacklist',
    where: 'track_key=?',
    whereArgs: [r.key],
    limit: 1,
  )).isNotEmpty;
  Future<Set<String>> blacklist() async =>
      (await db.query('blacklist'))
          .map((r) => r['track_key'] as String)
          .toSet();
  Future<void> setBlocked(TrackRef r, bool blocked) async {
    if (blocked) {
      await db.insert('blacklist', {
        'source_id': r.sourceId,
        'id': r.id,
        'track_key': r.key,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.delete('blacklist', where: 'track_key=?', whereArgs: [r.key]);
    }
  }

  Future<String?> setting(String key) async {
    final r = await db.query(
      'settings',
      where: 'key=?',
      whereArgs: [key],
      limit: 1,
    );
    return r.isEmpty ? null : r.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async => db.insert(
    'settings',
    {'key': key, 'value': value},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  Future<QueueSnapshot> queue() async {
    try {
      return QueueSnapshot.fromJson(
        jsonDecode(await setting('queue') ?? '{}') as Map<String, dynamic>,
      );
    } catch (_) {
      return const QueueSnapshot();
    }
  }

  Future<void> saveQueue(QueueSnapshot queue) =>
      setSetting('queue', jsonEncode(queue.toJson()));
  Future<void> removeSourceData(String id) async {
    // Never issues a remote mutation and never deletes original local audio.
    await db.transaction((tx) async {
      await tx.delete('sources', where: 'id=?', whereArgs: [id]);
      await tx.delete('tracks', where: 'source_id=?', whereArgs: [id]);
      final blockedRows = await tx.query('blacklist');
      for (final row in blockedRows) {
        try {
          if (TrackRef.parse(row['track_key'] as String).sourceId == id) {
            await tx.delete(
              'blacklist',
              where: 'track_key=?',
              whereArgs: [row['track_key']],
            );
          }
        } catch (_) {}
      }
      final removedPlaylists = await tx.query(
        'playlists',
        columns: ['id'],
        where: 'source_id=?',
        whereArgs: [id],
      );
      for (final p in removedPlaylists) {
        await tx.delete(
          'sync_intents',
          where: 'playlist_id=?',
          whereArgs: [p['id']],
        );
        await tx.delete(
          'playlist_items',
          where: 'playlist_id=?',
          whereArgs: [p['id']],
        );
      }
      await tx.delete('playlists', where: 'source_id=?', whereArgs: [id]);
      final rows = await tx.query('playlist_items');
      for (final row in rows) {
        try {
          if (TrackRef.parse(row['track_key'] as String).sourceId == id) {
            await tx.delete(
              'playlist_items',
              where: 'playlist_id=? AND entry_id=?',
              whereArgs: [row['playlist_id'], row['entry_id']],
            );
          }
        } catch (_) {}
      }
    });
  }
}
