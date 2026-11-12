import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../core/models.dart';
import '../services/embedded_tags.dart';

class AppDb {
  /// Private, durable letters, independent of snapshot pruning and diagnostics.
  static const _recommendationLettersTable =
      '''CREATE TABLE recommendation_letters(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    snapshot_id INTEGER,
    local_day TEXT NOT NULL,
    generation INTEGER NOT NULL,
    content TEXT NOT NULL,
    details_text TEXT NOT NULL DEFAULT '',
    origin TEXT NOT NULL,
    created_at_ms INTEGER NOT NULL,
    UNIQUE(local_day,generation))''';
  static const _letterV13Alter = <String>[
    "ALTER TABLE recommendation_snapshots ADD COLUMN letter_title TEXT NOT NULL DEFAULT ''",
    "ALTER TABLE recommendation_letters ADD COLUMN title TEXT NOT NULL DEFAULT ''",
    "ALTER TABLE recommendation_letters ADD COLUMN cover_refs_json TEXT NOT NULL DEFAULT '[]'",
    "ALTER TABLE recommendation_letters ADD COLUMN song_count INTEGER NOT NULL DEFAULT 0",
  ];
  static const _recommendationLettersIndex =
      'CREATE INDEX idx_recommendation_letters_date ON recommendation_letters(created_at_ms DESC)';
  static const _recommendationSchema = <String>[
    '''CREATE TABLE listening_sessions(
      session_id TEXT PRIMARY KEY,source_id TEXT NOT NULL,track_id TEXT NOT NULL,
      started_at_ms INTEGER NOT NULL,updated_at_ms INTEGER NOT NULL,
      listened_ms INTEGER NOT NULL DEFAULT 0,local_hour INTEGER NOT NULL,
      local_weekday INTEGER NOT NULL,local_day TEXT NOT NULL,
      qualified INTEGER NOT NULL DEFAULT 0,
      completed INTEGER NOT NULL DEFAULT 0,skipped INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE track_listen_stats(
      source_id TEXT NOT NULL,track_id TEXT NOT NULL,
      play_count INTEGER NOT NULL DEFAULT 0,
      completion_count INTEGER NOT NULL DEFAULT 0,
      skip_count INTEGER NOT NULL DEFAULT 0,
      total_listened_ms INTEGER NOT NULL DEFAULT 0,
      last_played_at_ms INTEGER,PRIMARY KEY(source_id,track_id))''',
    '''CREATE TABLE recommendation_snapshots(
      id INTEGER PRIMARY KEY AUTOINCREMENT,kind TEXT NOT NULL,
      local_day TEXT NOT NULL,generation INTEGER NOT NULL,
      algorithm_version INTEGER NOT NULL,seed INTEGER NOT NULL,
      item_count INTEGER NOT NULL DEFAULT 0,created_at_ms INTEGER NOT NULL,
      introduction TEXT NOT NULL DEFAULT '',llm_tag TEXT NOT NULL DEFAULT 'local',
      UNIQUE(kind,local_day,generation))''',
    '''CREATE TABLE recommendation_items(
      snapshot_id INTEGER NOT NULL,position INTEGER NOT NULL,
      item_kind TEXT NOT NULL,source_id TEXT NOT NULL,track_id TEXT,
      album_key TEXT,representative_track_id TEXT,album_track_count INTEGER,
      reason_code TEXT NOT NULL,score REAL NOT NULL,
      PRIMARY KEY(snapshot_id,position))''',
    '''CREATE TABLE recommendation_feedback(
      source_id TEXT NOT NULL,track_id TEXT NOT NULL,action TEXT NOT NULL,
      updated_at_ms INTEGER NOT NULL,PRIMARY KEY(source_id,track_id))''',
    'CREATE INDEX idx_listening_sessions_time ON listening_sessions(started_at_ms)',
    'CREATE INDEX idx_listening_sessions_context ON listening_sessions(local_hour,local_weekday,started_at_ms)',
    'CREATE INDEX idx_stats_last_played ON track_listen_stats(last_played_at_ms)',
    'CREATE INDEX idx_recommendation_items_source ON recommendation_items(source_id,track_id)',
    'CREATE INDEX idx_recommendation_snapshot_date ON recommendation_snapshots(kind,local_day)',
  ];
  static const _assetsTable = '''CREATE TABLE media_assets(
    source_id TEXT NOT NULL,asset_key TEXT NOT NULL,kind TEXT NOT NULL,
    version TEXT NOT NULL,relative_file TEXT NOT NULL,bytes INTEGER NOT NULL,
    sha256 TEXT NOT NULL,fetched_at INTEGER NOT NULL,last_used INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,pinned INTEGER NOT NULL DEFAULT 0,
    etag TEXT,last_modified TEXT,PRIMARY KEY(source_id,asset_key))''';
  static const _assetLinks = '''CREATE TABLE cache_asset_links(
    track_key TEXT NOT NULL,kind TEXT NOT NULL,source_id TEXT NOT NULL,
    asset_key TEXT NOT NULL,PRIMARY KEY(track_key,kind))''';
  static const _assetLinksIndex =
      'CREATE INDEX idx_cache_links_asset ON cache_asset_links(source_id,asset_key)';
  static const _assetsIndex =
      'CREATE INDEX idx_assets_lru ON media_assets(kind,pinned,last_used)';
  static const _assetMigrations =
      'CREATE TABLE media_asset_migrations(source_id TEXT NOT NULL,asset_key TEXT NOT NULL,PRIMARY KEY(source_id,asset_key))';
  static const _indexRuns =
      'CREATE TABLE index_runs(source_id TEXT PRIMARY KEY,run_id TEXT NOT NULL)';
  static const _webDavTagsTable = '''CREATE TABLE webdav_track_tags(
    source_id TEXT NOT NULL,track_id TEXT NOT NULL,
    resource_version TEXT NOT NULL,title TEXT,artist TEXT,album TEXT,
    album_artist TEXT,year INTEGER,disc INTEGER,number INTEGER,
    status TEXT NOT NULL,updated_at INTEGER NOT NULL,
    PRIMARY KEY(source_id,track_id))''';
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
    SELECT CAST('' AS TEXT) AS run_id, tracks.*,
      CAST('' AS TEXT) AS resource_version FROM tracks WHERE 0''';
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
      version: 13,
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
        if (oldVersion < 7) {
          // v5/v6 have the old index_tracks shape; v1-v4 created the new one.
          if (oldVersion >= 5) {
            await database.execute(
              "ALTER TABLE index_tracks ADD COLUMN resource_version TEXT NOT NULL DEFAULT ''",
            );
          }
          await database.execute(_webDavTagsTable);
        }
        if (oldVersion < 8) {
          await database.execute(
            "ALTER TABLE sources ADD COLUMN webdav_base_path TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            'ALTER TABLE sources ADD COLUMN webdav_max_depth INTEGER NOT NULL DEFAULT -1',
          );
        }
        if (oldVersion < 9) {
          await database.execute(_assetLinks);
          await database.execute(_assetLinksIndex);
        }
        if (oldVersion < 10) {
          for (final sql in _recommendationSchema) {
            await database.execute(sql);
          }
        } else if (oldVersion < 11) {
          await database.execute(
            "ALTER TABLE recommendation_snapshots ADD COLUMN introduction TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            "ALTER TABLE recommendation_snapshots ADD COLUMN llm_tag TEXT NOT NULL DEFAULT 'local'",
          );
        }
        if (oldVersion < 12) {
          await database.execute(_recommendationLettersTable);
          await database.execute(_recommendationLettersIndex);
          // Preserve existing nonempty daily introductions as older letters.
          await database.execute('''
            INSERT OR IGNORE INTO recommendation_letters(
              snapshot_id,local_day,generation,content,origin,created_at_ms)
            SELECT id,local_day,generation,introduction,
                   CASE WHEN llm_tag='local' THEN 'local' ELSE 'llm' END,
                   created_at_ms
            FROM recommendation_snapshots
            WHERE kind='daily' AND trim(introduction) <> ''
          ''');
        }
        if (oldVersion < 13) {
          for (final sql in _letterV13Alter) {
            await database.execute(sql);
          }
          // Retain older letters and their snapshot metadata if still present.
          await database.execute(
            "UPDATE recommendation_letters SET title='写给你的今日音乐信' WHERE title=''",
          );
          await database.execute('''
            UPDATE recommendation_letters SET song_count=COALESCE(
              (SELECT s.item_count FROM recommendation_snapshots s
               WHERE s.id=recommendation_letters.snapshot_id),0)
            WHERE song_count=0
          ''');
        }
      },
      onCreate: (d, v) async {
        for (final sql in <String>[
          '''CREATE TABLE sources(id TEXT PRIMARY KEY, name TEXT NOT NULL,kind TEXT NOT NULL,url TEXT NOT NULL,username TEXT NOT NULL,remote_user_id TEXT NOT NULL DEFAULT '',enabled INTEGER NOT NULL DEFAULT 1,last_sync INTEGER NOT NULL DEFAULT 0,webdav_base_path TEXT NOT NULL DEFAULT '',webdav_max_depth INTEGER NOT NULL DEFAULT -1)''',
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
          _assetLinks,
          _assetLinksIndex,
          _webDavTagsTable,
        ]) {
          await d.execute(sql);
        }
        await _catalogSchema(d);
        for (final sql in _recommendationSchema) {
          await d.execute(sql);
        }
        await d.execute(_recommendationLettersTable);
        await d.execute(_recommendationLettersIndex);
        for (final sql in _letterV13Alter) {
          await d.execute(sql);
        }
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
        batch.insert('index_tracks', {
          'run_id': runId,
          ...track.toRow(),
          'resource_version': track.resourceVersion,
        });
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
          current.kind != original.kind ||
          current.webdavBasePath != original.webdavBasePath ||
          current.webdavMaxDepth != original.webdavMaxDepth) {
        throw StateError('来源连接已变更或停用，已丢弃过期索引结果');
      }
      await tx.update(
        'tracks',
        {'missing': 1},
        where: 'source_id=?',
        whereArgs: [original.id],
      );
      // Merge verified embedded tags with the new directory snapshot. A normal
      // PROPFIND rescan must never reset resolved artist/album names.
      await tx.rawInsert(
        '''
        INSERT OR REPLACE INTO tracks ($_trackColumns)
        SELECT i.source_id,i.id,
          COALESCE(NULLIF(m.title,''),i.title),
          COALESCE(NULLIF(m.artist,''),i.artist),
          COALESCE(NULLIF(m.album,''),i.album),
          COALESCE(NULLIF(m.album_artist,''),i.album_artist),
          i.duration_ms,i.cover_id,
          COALESCE(m.year,i.year),
          COALESCE(m.disc,i.disc),
          COALESCE(m.number,i.number),
          i.remote_json,i.missing
        FROM index_tracks i
        LEFT JOIN webdav_track_tags m
          ON m.source_id=i.source_id AND m.track_id=i.id
         AND m.resource_version=i.resource_version AND m.status='done'
        WHERE i.run_id=?
      ''',
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

  /// Only completed metadata for the exact file version may suppress a fetch.
  Future<bool> hasWebDavTags(Track track) async {
    final rows = await db.query(
      'webdav_track_tags',
      columns: ['status'],
      where: 'source_id=? AND track_id=? AND resource_version=?',
      whereArgs: [track.ref.sourceId, track.ref.id, track.resourceVersion],
      limit: 1,
    );
    return rows.isNotEmpty && rows.single['status'] == 'done';
  }

  /// Persist and project tags atomically. A source disable, deletion or a new
  /// PROPFIND snapshot invalidates a stale in-flight Range response.
  Future<bool> putWebDavTags(Track requested, EmbeddedTags tags) async {
    if (!tags.hasMusicMetadata) return false;
    String? clean(String? s) => s?.trim().isNotEmpty == true ? s!.trim() : null;
    return db.transaction((tx) async {
      final sources = await tx.query(
        'sources',
        columns: ['kind', 'enabled'],
        where: 'id=?',
        whereArgs: [requested.ref.sourceId],
        limit: 1,
      );
      if (sources.isEmpty ||
          sources.single['kind'] != 'webdav' ||
          sources.single['enabled'] != 1) {
        return false;
      }
      final rows = await tx.query(
        'tracks',
        where: 'source_id=? AND id=? AND missing=0',
        whereArgs: [requested.ref.sourceId, requested.ref.id],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final current = Track.fromRow(rows.single);
      if (current.resourceVersion != requested.resourceVersion) return false;
      final already = await tx.query(
        'webdav_track_tags',
        columns: ['resource_version', 'status'],
        where: 'source_id=? AND track_id=?',
        whereArgs: [requested.ref.sourceId, requested.ref.id],
        limit: 1,
      );
      if (already.isNotEmpty &&
          already.single['resource_version'] == requested.resourceVersion &&
          already.single['status'] == 'done') {
        return false;
      }
      final updates = <String, Object?>{
        if (clean(tags.title) != null) 'title': clean(tags.title),
        if (clean(tags.artist) != null) 'artist': clean(tags.artist),
        if (clean(tags.album) != null) 'album': clean(tags.album),
        if (clean(tags.albumArtist) != null)
          'album_artist': clean(tags.albumArtist),
        if (tags.year != null) 'year': tags.year,
        if (tags.discNumber != null) 'disc': tags.discNumber,
        if (tags.trackNumber != null) 'number': tags.trackNumber,
      };
      if (updates.isEmpty) return false;
      await tx.insert('webdav_track_tags', {
        'source_id': requested.ref.sourceId,
        'track_id': requested.ref.id,
        'resource_version': requested.resourceVersion,
        'title': clean(tags.title),
        'artist': clean(tags.artist),
        'album': clean(tags.album),
        'album_artist': clean(tags.albumArtist),
        'year': tags.year,
        'disc': tags.discNumber,
        'number': tags.trackNumber,
        'status': 'done',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.update(
        'tracks',
        updates,
        where: 'source_id=? AND id=?',
        whereArgs: [requested.ref.sourceId, requested.ref.id],
      );
      return true;
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

  Future<List<PlaylistModel>> playlists() => _orderedPlaylists(db);

  Future<List<PlaylistModel>> _orderedPlaylists(
    DatabaseExecutor executor,
  ) async {
    final items = (await executor.query(
      'playlists',
      orderBy: "CASE kind WHEN 'favorites' THEN 0 WHEN 'local' THEN 1 ELSE 2 END,name COLLATE NOCASE",
    )).map(PlaylistModel.fromRow).toList();
    final settings = await executor.query(
      'settings',
      where: 'key=?',
      whereArgs: ['playlist_display_order'],
      limit: 1,
    );
    if (settings.isEmpty) return items;
    final Object? saved;
    try {
      saved = jsonDecode(settings.single['value'] as String);
    } on FormatException {
      return items;
    }
    if (saved is! List) return items;
    final remaining = {for (final item in items) item.id: item};
    final ordered = <PlaylistModel>[];
    for (final id in saved) {
      final item = remaining.remove(id);
      if (item != null) ordered.add(item);
    }
    return [...ordered, ...remaining.values];
  }

  // Only local presentation settings change; playlist content and sync state
  // stay untouched. Resolve IDs inside the transaction to tolerate refreshes.
  Future<void> movePlaylistDisplay(String id, String targetId) async {
    if (id == targetId) return;
    await db.transaction((tx) async {
      final items = await _orderedPlaylists(tx);
      final from = items.indexWhere((item) => item.id == id);
      final to = items.indexWhere((item) => item.id == targetId);
      if (from < 0 || to < 0) return;
      items.insert(to, items.removeAt(from));
      await tx.insert('settings', {
        'key': 'playlist_display_order',
        'value': jsonEncode(items.map((item) => item.id).toList()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

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

  Future<List<({String id, String key})>> playlistEntries(String id) async =>
      (await db.query(
            'playlist_items',
            columns: ['entry_id', 'track_key'],
            where: 'playlist_id=?',
            whereArgs: [id],
            orderBy: 'position',
          ))
          .map(
            (row) => (
              id: row['entry_id'] as String,
              key: row['track_key'] as String,
            ),
          )
          .toList();

  Future<void> removePlaylistEntry(
    PlaylistModel playlist,
    String entryId,
  ) async {
    await db.transaction((tx) async {
      final removed = await tx.delete(
        'playlist_items',
        where: 'playlist_id=? AND entry_id=?',
        whereArgs: [playlist.id, entryId],
      );
      if (removed > 0 && playlist.kind == PlaylistKind.cloud) {
        await tx.update(
          'playlists',
          {
            'status':
                (playlist.status == SyncStatus.conflict
                        ? SyncStatus.conflict
                        : SyncStatus.pending)
                    .name,
            'message': '',
          },
          where: 'id=?',
          whereArgs: [playlist.id],
        );
      }
    });
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
      for (final table in [
        'listening_sessions',
        'track_listen_stats',
        'recommendation_feedback',
        'recommendation_items',
      ]) {
        await tx.delete(table, where: 'source_id=?', whereArgs: [id]);
      }
      await tx.delete('sources', where: 'id=?', whereArgs: [id]);
      await tx.delete('tracks', where: 'source_id=?', whereArgs: [id]);
      await tx.delete(
        'webdav_track_tags',
        where: 'source_id=?',
        whereArgs: [id],
      );
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
