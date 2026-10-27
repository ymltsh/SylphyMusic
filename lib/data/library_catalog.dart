import 'dart:convert';

import '../core/models.dart';
import 'app_db.dart';

class CatalogQuery {
  const CatalogQuery({
    this.view = 0,
    this.search = '',
    this.sourceId,
    this.sort = 'name',
    this.descending = false,
    this.groupKind,
    this.groupKey,
    this.blocked = false,
  });
  final int view; // 0 songs, 1 albums, 2 artists.
  final String search, sort;
  final String? sourceId, groupKind, groupKey;
  final bool descending, blocked;
  String get signature => jsonEncode([
    view,
    search,
    sourceId,
    sort,
    descending,
    groupKind,
    groupKey,
    blocked,
  ]);

  /// All matching songs, preserving scope and sorting from a grouped view.
  CatalogQuery get songs => CatalogQuery(
    search: search,
    sourceId: sourceId,
    sort: sort,
    descending: descending,
    groupKind: groupKind,
    groupKey: groupKey,
    blocked: blocked,
  );
  CatalogQuery songsIn(String kind, String key) => CatalogQuery(
    search: search,
    sourceId: sourceId,
    sort: sort,
    descending: descending,
    groupKind: kind,
    groupKey: key,
    blocked: blocked,
  );
}

class CatalogRow {
  CatalogRow(Map<String, Object?> row)
    : track = Track.fromRow(row),
      key = row['catalog_key'] as String? ?? '',
      count = row['catalog_count'] as int? ?? 1,
      sources = row['catalog_sources'] as int? ?? 1;
  final Track track;
  final String key;
  final int count, sources;
}

class CatalogPage {
  const CatalogPage(this.rows, this.total);
  final List<CatalogRow> rows;
  final int total;
}

/// Filtering, grouping and ordering stay in SQLite. Queries return bounded
/// metadata batches; creating a queue fetches identities without blobs.
class LibraryCatalog {
  LibraryCatalog(this.db);
  final AppDb db;
  static const _artist = 'lower(trim(t.artist))';
  static const _album =
      "lower(trim(CASE WHEN t.album_artist='' THEN t.artist ELSE t.album_artist END)) || '|' || lower(trim(t.album))";

  ({String from, List<Object?> args}) _from(CatalogQuery query) {
    final conditions = <String>[
      if (!query.blocked) 't.missing=0',
      if (!query.blocked) 's.enabled=1',
      query.blocked ? 'b.track_key IS NOT NULL' : 'b.track_key IS NULL',
    ];
    final args = <Object?>[];
    if (query.sourceId != null) {
      conditions.add('t.source_id=?');
      args.add(query.sourceId);
    }
    if (query.search.isNotEmpty) {
      conditions.add(
        "instr(lower(t.title || ' ' || t.artist || ' ' || t.album), lower(?))>0",
      );
      args.add(query.search);
    }
    if (query.groupKey != null) {
      conditions.add('${query.groupKind == 'album' ? _album : _artist}=?');
      args.add(query.groupKey);
    }
    return (
      from:
          'FROM tracks t JOIN sources s ON s.id=t.source_id LEFT JOIN blacklist b ON b.source_id=t.source_id AND b.id=t.id WHERE ${conditions.join(' AND ')}',
      args: args,
    );
  }

  String _order(CatalogQuery query) {
    final grouped = query.view != 0;
    final expression = switch (query.sort) {
      'year' => grouped ? 'MAX(t.year)' : 't.year',
      'duration' => grouped ? 'SUM(t.duration_ms)' : 't.duration_ms',
      'artist' => 't.artist COLLATE NOCASE',
      'album' => 't.album COLLATE NOCASE',
      _ =>
        query.view == 1
            ? 't.album COLLATE NOCASE'
            : query.view == 2
            ? 't.artist COLLATE NOCASE'
            : 't.title COLLATE NOCASE',
    };
    return '$expression ${query.descending ? 'DESC' : 'ASC'},t.source_id,t.id';
  }

  Future<CatalogPage> page(
    CatalogQuery query, {
    int offset = 0,
    int limit = 100,
  }) async {
    if (limit < 1 || limit > 250 || offset < 0) {
      throw ArgumentError('Invalid catalog page');
    }
    final sql = _from(query), group = query.view == 1 ? _album : _artist;
    final groupSql = query.view == 0 ? '' : ' GROUP BY $group';
    return db.db.transaction((tx) async {
      final count = await tx.rawQuery(
        'SELECT COUNT(*) AS n FROM (SELECT 1 ${sql.from}$groupSql)',
        sql.args,
      );
      final rows = await tx.rawQuery(
        'SELECT t.*${query.view == 0 ? '' : ', $group AS catalog_key,COUNT(*) AS catalog_count, COUNT(DISTINCT t.source_id) AS catalog_sources'} ${sql.from}$groupSql ORDER BY ${_order(query)} LIMIT ? OFFSET ?',
        [...sql.args, limit, offset],
      );
      return CatalogPage(
        rows.map(CatalogRow.new).toList(),
        count.single['n'] as int,
      );
    });
  }

  Future<List<TrackRef>> queue(CatalogQuery query) async {
    if (query.view != 0) {
      throw ArgumentError('Open a group before creating its queue');
    }
    final sql = _from(query);
    final rows = await db.db.rawQuery(
      'SELECT t.source_id,t.id ${sql.from} ORDER BY ${_order(query)}',
      sql.args,
    );
    return rows
        .map((row) => TrackRef(row['source_id'] as String, row['id'] as String))
        .toList();
  }
}
