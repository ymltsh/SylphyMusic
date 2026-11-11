import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../core/models.dart';
import '../core/recommendation_models.dart';
import 'app_db.dart';

/// Only metadata and source-scoped identities are read here; no audio downloads.
class RecommendationRepository {
  RecommendationRepository(this.database);
  final AppDb database;

  static const _visible = '''
    FROM tracks t
    JOIN sources s ON s.id=t.source_id
    LEFT JOIN blacklist b ON b.source_id=t.source_id AND b.id=t.id
    LEFT JOIN track_listen_stats ls
      ON ls.source_id=t.source_id AND ls.track_id=t.id
    WHERE s.enabled=1 AND t.missing=0 AND b.track_key IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM recommendation_feedback f
        WHERE f.source_id=t.source_id AND f.track_id=t.id
          AND f.action='hide'
      )
  ''';

  // Keep remote_json and artwork metadata out of the 1200-candidate pass.
  // Only the final 24 tracks / 8 representative albums are fully hydrated.
  static const _lightTrack =
      '''t.source_id,t.id,t.title,t.artist,t.album,t.album_artist,
    t.duration_ms,t.year,t.disc,t.number,t.missing''';

  static const _albumKey = '''
    lower(trim(CASE WHEN t.album_artist='' THEN t.artist ELSE t.album_artist END))
    || '|' || lower(trim(t.album))
  ''';

  Future<void> checkpoint({
    required String sessionId,
    required TrackRef track,
    required int startedAt,
    required int updatedAt,
    required int hour,
    required int weekday,
    required String day,
    required int listenedMs,
    required bool qualified,
    required bool completed,
    required bool skipped,
  }) => database.db.transaction((tx) async {
    final prior = await tx.query(
      'listening_sessions',
      where: 'session_id=?',
      whereArgs: [sessionId],
      limit: 1,
    );
    final before = prior.isEmpty ? null : prior.first;
    final oldMs = (before?['listened_ms'] as int?) ?? 0;
    final nextMs = max(oldMs, listenedMs);
    final deltaMs = nextMs - oldMs;
    final addPlay = qualified && before?['qualified'] != 1 ? 1 : 0;
    final addComplete = completed && before?['completed'] != 1 ? 1 : 0;
    final addSkip = skipped && before?['skipped'] != 1 ? 1 : 0;
    await tx.insert('listening_sessions', {
      'session_id': sessionId,
      'source_id': track.sourceId,
      'track_id': track.id,
      'started_at_ms': startedAt,
      'updated_at_ms': updatedAt,
      'listened_ms': nextMs,
      'local_hour': hour,
      'local_weekday': weekday,
      'local_day': day,
      'qualified': qualified || before?['qualified'] == 1 ? 1 : 0,
      'completed': completed || before?['completed'] == 1 ? 1 : 0,
      'skipped': skipped || before?['skipped'] == 1 ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await tx.insert('track_listen_stats', {
      'source_id': track.sourceId,
      'track_id': track.id,
      'play_count': 0,
      'completion_count': 0,
      'skip_count': 0,
      'total_listened_ms': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await tx.rawUpdate(
      '''
      UPDATE track_listen_stats SET
        play_count=play_count+?,
        completion_count=completion_count+?,
        skip_count=skip_count+?,
        total_listened_ms=total_listened_ms+?,
        last_played_at_ms=CASE WHEN ?=1 THEN ? ELSE last_played_at_ms END
      WHERE source_id=? AND track_id=?
    ''',
      [
        addPlay,
        addComplete,
        addSkip,
        deltaMs,
        addPlay,
        updatedAt,
        track.sourceId,
        track.id,
      ],
    );
  });

  Future<void> pruneSessions(DateTime now) async {
    final before = now
        .subtract(const Duration(days: 90))
        .millisecondsSinceEpoch;
    await database.db.delete(
      'listening_sessions',
      where: 'started_at_ms < ?',
      whereArgs: [before],
    );
  }

  Future<Set<String>> favoriteKeys() async {
    final rows = await database.db.rawQuery('''
      SELECT DISTINCT i.track_key FROM playlist_items i
      JOIN playlists p ON p.id=i.playlist_id
      WHERE p.kind='favorites' LIMIT 15000
    ''');
    return rows.map((r) => r['track_key'] as String).toSet();
  }

  TrackCandidate _candidate(Map<String, Object?> row) => TrackCandidate(
    track: Track.fromRow(row),
    plays: (row['rec_plays'] as num?)?.toInt() ?? 0,
    completions: (row['rec_completions'] as num?)?.toInt() ?? 0,
    skips: (row['rec_skips'] as num?)?.toInt() ?? 0,
    lastPlayedAt: (row['rec_last_played'] as num?)?.toInt(),
  );

  Future<List<TrackCandidate>> candidates(int seed) async {
    const columns = '''$_lightTrack,
      COALESCE(ls.play_count,0) AS rec_plays,
      COALESCE(ls.completion_count,0) AS rec_completions,
      COALESCE(ls.skip_count,0) AS rec_skips,
      ls.last_played_at_ms AS rec_last_played''';
    final count = await database.db.rawQuery('SELECT COUNT(*) AS n $_visible');
    final total = (count.first['n'] as int?) ?? 0;
    if (total == 0) return [];
    final offset = total <= 400 ? 0 : seed % (total - 399);
    final results = await Future.wait([
      database.db.rawQuery('''SELECT $columns $_visible
        ORDER BY COALESCE(ls.play_count,0) DESC,
          COALESCE(ls.last_played_at_ms,0) DESC, t.rowid
        LIMIT 400'''),
      database.db.rawQuery('''SELECT $columns $_visible
        ORDER BY COALESCE(ls.play_count,0) ASC,
          COALESCE(ls.last_played_at_ms,0) ASC, t.rowid
        LIMIT 400'''),
      database.db.rawQuery(
        '''SELECT $columns $_visible
        ORDER BY t.rowid LIMIT 400 OFFSET ?''',
        [offset],
      ),
    ]);
    final selected = <String, TrackCandidate>{};
    for (final rows in results) {
      for (final row in rows) {
        final item = _candidate(row);
        selected[item.track.ref.key] = item;
      }
    }
    return selected.values.toList();
  }

  Future<List<TrackCandidate>> randomCandidates(int seed) async {
    final rows = await database.db.rawQuery('SELECT COUNT(*) AS n $_visible');
    final total = (rows.first['n'] as int?) ?? 0;
    if (total == 0) return [];
    final offset = total <= 1200 ? 0 : seed % (total - 1199);
    final result = await database.db.rawQuery(
      '''
      SELECT $_lightTrack $_visible ORDER BY t.rowid LIMIT 1200 OFFSET ?
    ''',
      [offset],
    );
    return [
      for (final row in result)
        TrackCandidate(
          track: Track.fromRow(row),
          plays: 0,
          completions: 0,
          skips: 0,
          lastPlayedAt: null,
        ),
    ];
  }

  Future<Map<String, int>> timeArtistAffinity(DateTime now) async {
    final cutoff = now
        .subtract(const Duration(days: 90))
        .millisecondsSinceEpoch;
    final hour = now.hour;
    final hours = hour < 5
        ? [22, 23, 0, 1, 2, 3, 4]
        : hour < 11
        ? [5, 6, 7, 8, 9, 10]
        : hour < 17
        ? [11, 12, 13, 14, 15, 16]
        : hour < 22
        ? [17, 18, 19, 20, 21]
        : [22, 23, 0, 1, 2, 3, 4];
    final summary = await database.db.rawQuery(
      '''
      SELECT COUNT(*) AS n, COUNT(DISTINCT local_day) AS days
      FROM listening_sessions
      WHERE qualified=1 AND started_at_ms>=?
    ''',
      [cutoff],
    );
    if (((summary.first['n'] as int?) ?? 0) < 20 ||
        ((summary.first['days'] as int?) ?? 0) < 5)
      return {};
    final slots = List.filled(hours.length, '?').join(',');
    final rows = await database.db.rawQuery(
      '''
      SELECT lower(trim(t.artist)) AS artist, COUNT(*) AS n
      FROM listening_sessions l
      JOIN tracks t ON t.source_id=l.source_id AND t.id=l.track_id
      WHERE l.qualified=1 AND l.started_at_ms >= ?
        AND l.local_hour IN ($slots)
        AND (CASE WHEN ?=1 THEN l.local_weekday IN (6,7)
                  ELSE l.local_weekday NOT IN (6,7) END)
      GROUP BY lower(trim(t.artist)) ORDER BY n DESC LIMIT 120
    ''',
      [cutoff, ...hours, now.weekday >= 6 ? 1 : 0],
    );
    return {
      for (final r in rows) r['artist'] as String: (r['n'] as num).toInt(),
    };
  }

  Future<List<AlbumCandidate>> albumCandidates() async {
    const projection =
        '''$_lightTrack,
      $_albumKey AS rec_album_key,
      COUNT(*) AS rec_count,
      SUM(CASE WHEN COALESCE(ls.play_count,0)=0 THEN 1 ELSE 0 END)
        AS rec_unplayed,
      SUM(COALESCE(ls.play_count,0)) AS rec_plays''';
    final results = await Future.wait([
      database.db.rawQuery('''SELECT $projection $_visible
        AND trim(t.album) <> ''
        GROUP BY t.source_id, rec_album_key HAVING COUNT(*) >= 2
        ORDER BY rec_plays DESC, rec_count DESC LIMIT 240'''),
      database.db.rawQuery('''SELECT $projection $_visible
        AND trim(t.album) <> ''
        GROUP BY t.source_id, rec_album_key HAVING COUNT(*) >= 2
        ORDER BY rec_unplayed DESC, rec_count DESC LIMIT 240'''),
    ]);
    final map = <String, AlbumCandidate>{};
    for (final rows in results) {
      for (final row in rows) {
        final track = Track.fromRow(row);
        final key = row['rec_album_key'] as String;
        map['${track.ref.sourceId}|$key'] = AlbumCandidate(
          representative: track,
          groupKey: key,
          trackCount: (row['rec_count'] as num).toInt(),
          unplayedCount: (row['rec_unplayed'] as num).toInt(),
          plays: (row['rec_plays'] as num).toInt(),
        );
      }
    }
    return map.values.toList();
  }

  Future<Set<String>> recentTracks(DateTime now) async {
    final since = now.subtract(const Duration(days: 3)).millisecondsSinceEpoch;
    final rows = await database.db.rawQuery(
      '''
      SELECT i.source_id, i.track_id FROM recommendation_items i
      JOIN recommendation_snapshots s ON s.id=i.snapshot_id
      WHERE s.kind='daily' AND s.created_at_ms >= ? AND i.track_id IS NOT NULL
      LIMIT 500
    ''',
      [since],
    );
    return rows
        .map(
          (row) => TrackRef(
            row['source_id'] as String,
            row['track_id'] as String,
          ).key,
        )
        .toSet();
  }

  Future<({int id, int generation, int itemCount})?> latestSnapshot(
    String kind,
    String day,
  ) async {
    final rows = await database.db.query(
      'recommendation_snapshots',
      columns: ['id', 'generation', 'item_count'],
      where: 'kind=? AND local_day=?',
      whereArgs: [kind, day],
      orderBy: 'generation DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (
      id: rows.first['id'] as int,
      generation: rows.first['generation'] as int,
      itemCount: rows.first['item_count'] as int,
    );
  }

  Future<List<RecommendedTrack>> dailyItems(int snapshotId) async {
    final items = await database.db.query(
      'recommendation_items',
      where: 'snapshot_id=? AND item_kind=?',
      whereArgs: [snapshotId, 'track'],
      orderBy: 'position',
    );
    final result = <RecommendedTrack>[];
    for (final item in items) {
      final rows = await database.db.rawQuery(
        '''
        SELECT t.* $_visible AND t.source_id=? AND t.id=? LIMIT 1
      ''',
        [item['source_id'], item['track_id']],
      );
      if (rows.isEmpty) continue;
      result.add(
        RecommendedTrack(
          Track.fromRow(rows.first),
          item['reason_code'] as String,
          (item['score'] as num).toDouble(),
        ),
      );
    }
    return result;
  }

  Future<List<RecommendedAlbum>> albumItems(int snapshotId) async {
    final items = await database.db.query(
      'recommendation_items',
      where: 'snapshot_id=? AND item_kind=?',
      whereArgs: [snapshotId, 'album'],
      orderBy: 'position',
    );
    final result = <RecommendedAlbum>[];
    for (final item in items) {
      final rows = await database.db.rawQuery(
        '''
        SELECT t.* $_visible AND t.source_id=? AND t.id=?
          AND $_albumKey=? LIMIT 1
      ''',
        [item['source_id'], item['representative_track_id'], item['album_key']],
      );
      if (rows.isEmpty) continue;
      result.add(
        RecommendedAlbum(
          representative: Track.fromRow(rows.first),
          groupKey: item['album_key'] as String,
          trackCount: (item['album_track_count'] as int?) ?? 1,
          reason: item['reason_code'] as String,
          score: (item['score'] as num).toDouble(),
        ),
      );
    }
    return result;
  }

  Future<int> saveDaily(
    String day,
    int generation,
    int seed,
    List<RecommendedTrack> items,
  ) => _saveSnapshot(
    kind: 'daily',
    day: day,
    generation: generation,
    seed: seed,
    items: [
      for (final item in items)
        {
          'item_kind': 'track',
          'source_id': item.track.ref.sourceId,
          'track_id': item.track.ref.id,
          'reason_code': item.reason,
          'score': item.score,
        },
    ],
  );

  Future<int> saveAlbums(
    String day,
    int generation,
    int seed,
    List<RecommendedAlbum> items,
  ) => _saveSnapshot(
    kind: 'albums',
    day: day,
    generation: generation,
    seed: seed,
    items: [
      for (final item in items)
        {
          'item_kind': 'album',
          'source_id': item.representative.ref.sourceId,
          'album_key': item.groupKey,
          'representative_track_id': item.representative.ref.id,
          'album_track_count': item.trackCount,
          'reason_code': item.reason,
          'score': item.score,
        },
    ],
  );

  Future<int> _saveSnapshot({
    required String kind,
    required String day,
    required int generation,
    required int seed,
    required List<Map<String, Object?>> items,
  }) => database.db.transaction((tx) async {
    final id = await tx.insert('recommendation_snapshots', {
      'kind': kind,
      'local_day': day,
      'generation': generation,
      'algorithm_version': 1,
      'seed': seed,
      'item_count': items.length,
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
    for (var i = 0; i < items.length; i++) {
      await tx.insert('recommendation_items', {
        'snapshot_id': id,
        'position': i,
        ...items[i],
      });
    }
    // Snapshot item rows are removed in the same transaction as expired heads.
    final old = await tx.query(
      'recommendation_snapshots',
      columns: ['id'],
      orderBy: 'created_at_ms DESC',
      limit: 150,
    );
    if (old.length == 150) {
      await tx.rawDelete('''
        DELETE FROM recommendation_items WHERE snapshot_id IN (
          SELECT id FROM recommendation_snapshots
          WHERE id NOT IN (SELECT id FROM recommendation_snapshots
                           ORDER BY created_at_ms DESC LIMIT 120)
        )
      ''');
      await tx.rawDelete('''
        DELETE FROM recommendation_snapshots
        WHERE id NOT IN (SELECT id FROM recommendation_snapshots
                         ORDER BY created_at_ms DESC LIMIT 120)
      ''');
    }
    return id;
  });

  Future<void> hideTrack(TrackRef ref) async {
    await database.db.insert('recommendation_feedback', {
      'source_id': ref.sourceId,
      'track_id': ref.id,
      'action': 'hide',
      'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearAnalytics() async {
    await database.db.transaction((tx) async {
      await tx.delete('listening_sessions');
      await tx.delete('track_listen_stats');
      await tx.delete('recommendation_items');
      await tx.delete('recommendation_snapshots');
    });
  }
}
