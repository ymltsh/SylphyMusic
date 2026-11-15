import '../core/models.dart';
import 'app_db.dart';

class CacheCatalogResult {
  const CacheCatalogResult(this.rows, this.total, this.sourceIds);
  final List<Map<String, Object?>> rows;
  final int total;
  final Set<String> sourceIds;
}

/// Reads only cache-linked metadata. Filtering, resource aggregation and
/// ordering run in SQLite without scanning the library into Dart objects.
class CacheCatalog {
  const CacheCatalog(this.db);
  final AppDb db;

  Future<CacheCatalogResult> query({
    String search = '',
    String? sourceId,
    String sort = 'recent',
  }) => db.db.transaction((tx) async {
    final keys = await tx.rawQuery('''
      SELECT track_key FROM cache
      UNION
      SELECT l.track_key FROM cache_asset_links l JOIN media_assets a
        ON l.source_id=a.source_id AND l.asset_key=a.asset_key
    ''');
    // Decode only identities in Dart: older Android SQLite versions need not
    // provide JSON functions. This connection-local table is not a migration.
    await tx.execute('''CREATE TEMP TABLE IF NOT EXISTS cache_browser_refs(
      track_key TEXT PRIMARY KEY,source_id TEXT NOT NULL,id TEXT NOT NULL)''');
    await tx.delete('cache_browser_refs');
    final sources = <String>{};
    final batch = tx.batch();
    for (final row in keys) {
      final key = row['track_key'] as String;
      final ref = TrackRef.parse(key);
      sources.add(ref.sourceId);
      batch.insert('cache_browser_refs', {
        'track_key': key,
        'source_id': ref.sourceId,
        'id': ref.id,
      });
    }
    await batch.commit(noResult: true);
    final conditions = <String>[];
    final args = <Object?>[];
    if (sourceId != null) {
      conditions.add('r.source_id=?');
      args.add(sourceId);
    }
    for (final term
        in search.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty)) {
      conditions.add('''instr(lower(
        COALESCE(t.title,'不可用歌曲') || ' ' || COALESCE(t.artist,'') || ' ' ||
        COALESCE(t.album,'') || ' ' || COALESCE(s.name,'已移除的来源')
      ),lower(?))>0''');
      args.add(term);
    }
    final order = switch (sort) {
      'size' => 'audio_bytes+cover_bytes+lyrics_bytes DESC',
      'title' => 'title COLLATE NOCASE',
      _ => 'last_used DESC',
    };
    try {
      final rows = await tx.rawQuery('''
        WITH asset_users AS (
          SELECT source_id,asset_key,COUNT(DISTINCT track_key) users
          FROM cache_asset_links GROUP BY source_id,asset_key
        ), linked AS (
          SELECT l.track_key,
            SUM(CASE WHEN l.kind='cover' THEN a.bytes ELSE 0 END) cover_bytes,
            SUM(CASE WHEN l.kind<>'cover' THEN a.bytes ELSE 0 END) lyrics_bytes,
            SUM(CASE WHEN l.kind='manual' THEN a.bytes ELSE 0 END) manual_bytes,
            MAX(CASE WHEN l.kind='cover' AND u.users>1 THEN 1 ELSE 0 END) cover_shared,
            MAX(a.last_used) last_used
          FROM cache_asset_links l JOIN media_assets a
            ON l.source_id=a.source_id AND l.asset_key=a.asset_key
          JOIN asset_users u ON l.source_id=u.source_id AND l.asset_key=u.asset_key
          GROUP BY l.track_key
        )
        SELECT r.track_key,r.source_id AS source,
          COALESCE(t.title,'不可用歌曲') title,
          COALESCE(t.artist,'') artist,COALESCE(t.album,'') album,
          COALESCE(c.bytes,0) audio_bytes,COALESCE(l.cover_bytes,0) cover_bytes,
          COALESCE(l.lyrics_bytes,0) lyrics_bytes,COALESCE(l.manual_bytes,0) manual_bytes,
          COALESCE(l.cover_shared,0) cover_shared,
          MAX(COALESCE(c.last_used,0),COALESCE(l.last_used,0)) last_used
        FROM cache_browser_refs r
        LEFT JOIN tracks t ON t.source_id=r.source_id AND t.id=r.id
        LEFT JOIN sources s ON s.id=r.source_id
        LEFT JOIN cache c ON c.track_key=r.track_key
        LEFT JOIN linked l ON l.track_key=r.track_key
        ${conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}'}
        ORDER BY $order,r.track_key
      ''', args);
      return CacheCatalogResult(rows, keys.length, sources);
    } finally {
      await tx.delete('cache_browser_refs');
    }
  });
}
