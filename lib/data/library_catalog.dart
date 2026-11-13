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
    this.namedAlbumsOnly = false,
  });
  final int view; // 0 songs, 1 albums, 2 artists, 3 folders.
  final String search, sort;
  final String? sourceId, groupKind, groupKey;
  final bool descending, blocked, namedAlbumsOnly;
  String get signature => jsonEncode([
    view,
    search,
    sourceId,
    sort,
    descending,
    groupKind,
    groupKey,
    blocked,
    namedAlbumsOnly,
  ]);

  String get groupType => switch (view) {
    1 => 'album',
    3 => 'folder',
    _ => 'artist',
  };

  String get countUnit => switch (view) {
    0 => '首',
    1 => '张专辑',
    3 => groupKey == null ? '个文件夹' : '项',
    _ => '位艺术家',
  };

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

  CatalogQuery folderIn(String key) => CatalogQuery(
    view: 3,
    search: search,
    sourceId: sourceId,
    sort: sort,
    descending: descending,
    groupKind: 'folder',
    groupKey: key,
    blocked: blocked,
  );
}

class CatalogRow {
  CatalogRow(Map<String, Object?> row, {Track? portrait})
    : track = Track.fromRow(row),
      _portrait = portrait,
      key = row['catalog_key'] as String? ?? '',
      count = row['catalog_count'] as int? ?? 1,
      sources = row['catalog_sources'] as int? ?? 1,
      folder = row['catalog_folder'] as String?,
      folderEncoded = row['catalog_folder_encoded'] == 1,
      isFolder = row['catalog_is_folder'] == 1;
  final String? folder;
  final bool folderEncoded, isFolder;
  String get folderLocation {
    if (folder == null) return '未提供目录';
    if (!folderEncoded) return folder!;
    return folder!.split('/').map(_decodeFolderName).join('/');
  }

  String get folderTitle {
    if (folder == null) return '未提供目录';
    if (folder == '.' || folder == '/') return '根目录';
    final path = folder!.endsWith('/')
        ? folder!.substring(0, folder!.length - 1)
        : folder!;
    final name = path.substring(path.lastIndexOf('/') + 1);
    if (name.isEmpty) return folder!;
    // Server filesystem paths are already text. URI decoding rejects raw
    // Unicode; only WebDAV IDs contain percent-encoded path components.
    if (!folderEncoded) return name;
    return _decodeFolderName(name);
  }

  static String _decodeFolderName(String name) {
    try {
      return Uri.decodeComponent(name);
    } on ArgumentError {
      return name;
    } on FormatException {
      return name;
    }
  }

  final Track track;
  final Track? _portrait;
  Track get portraitTrack => _portrait ?? track;
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

  static const _folder = 'json_array(t.source_id,f.directory)';

  // Split paths inside SQLite; existing indexes need no metadata reload or
  // destructive migration. The last component is the filename, not a folder.
  static const _folderPrefix = r'''WITH RECURSIVE
    raw_file_paths(source_id,id,path) AS (
      SELECT t.source_id,t.id,replace(CASE WHEN s.kind='webdav' THEN t.id
        ELSE coalesce(nullif(json_extract(t.remote_json,'$.Path'),''),
          nullif(json_extract(t.remote_json,'$.MediaSources[0].Path'),''),
          nullif(json_extract(t.remote_json,'$.path'),'')) END,char(92),'/')
      FROM tracks t JOIN sources s ON s.id=t.source_id),
    file_paths(source_id,id,path) AS (
      SELECT source_id,id,CASE WHEN path IS NULL OR path='' OR
        instr(lower(path),'://')>0 OR substr(path,1,1)='/' OR
        substr(path,2,2)=':/' OR substr(path,1,2)='./'
        THEN path ELSE './' || path END FROM raw_file_paths),
    folder_parts(source_id,id,directory,rest) AS (
      SELECT source_id,id,'',CASE
        WHEN instr(lower(path),'://')>0 THEN NULL ELSE path END FROM file_paths
      UNION ALL
      SELECT source_id,id,directory || substr(rest,1,instr(rest,'/')),
        substr(rest,instr(rest,'/')+1)
      FROM folder_parts WHERE instr(rest,'/')>0),
    folders AS (
      SELECT source_id,id,CASE
        WHEN rest IS NULL OR (directory='' AND rest='') THEN NULL
        WHEN directory='' THEN '.'
        WHEN directory='/' OR (length(directory)=3 AND substr(directory,2,1)=':') THEN directory
        ELSE substr(directory,1,length(directory)-1) END AS directory
      FROM folder_parts WHERE rest IS NULL OR instr(rest,'/')=0)
    ''';

  String _group(CatalogQuery query) => switch (query.view) {
    1 => _album,
    3 => _folder,
    _ => _artist,
  };

  ({String prefix, String from, List<Object?> args}) _from(CatalogQuery query) {
    final conditions = <String>[
      if (!query.blocked) 't.missing=0',
      if (!query.blocked) 's.enabled=1',
      if (query.view == 1 && query.namedAlbumsOnly) "trim(t.album)<>''",
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
    if (query.groupKey != null && query.groupKind == 'folder') {
      final scope = _folderScope(query.groupKey!);
      conditions.add('t.source_id=?');
      args.add(scope.source);
      conditions.add(
        '(f.directory IS ? OR '
        '(? IS NOT NULL AND substr(f.directory,1,length(?))=?))',
      );
      args.addAll([scope.path, scope.prefix, scope.prefix, scope.prefix]);
    } else if (query.groupKey != null) {
      final expression = switch (query.groupKind) {
        'album' => _album,
        'folder' => _folder,
        _ => _artist,
      };
      conditions.add('$expression=?');
      args.add(query.groupKey);
    }
    final folders = query.view == 3 || query.groupKind == 'folder';
    return (
      prefix: folders ? _folderPrefix : '',
      from:
          'FROM tracks t JOIN sources s ON s.id=t.source_id ${folders ? 'JOIN folders f ON f.source_id=t.source_id AND f.id=t.id' : ''} LEFT JOIN blacklist b ON b.source_id=t.source_id AND b.id=t.id WHERE ${conditions.join(' AND ')}',
      args: args,
    );
  }

  String _order(CatalogQuery query) {
    final grouped = query.view != 0;
    final expression = switch (query.sort) {
      'year' => grouped ? 'MAX(t.year)' : 't.year',
      'duration' => grouped ? 'SUM(t.duration_ms)' : 't.duration_ms',
      'track_number' => 't.disc,t.number',
      'artist' => 't.artist COLLATE NOCASE',
      'album' => 't.album COLLATE NOCASE',
      _ =>
        query.view == 1
            ? 't.album COLLATE NOCASE'
            : query.view == 2
            ? 't.artist COLLATE NOCASE'
            : query.view == 3
            ? 'f.directory COLLATE NOCASE'
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
    if (query.view == 3) return _folderPage(query, offset, limit);
    final sql = _from(query), group = _group(query);
    final groupSql = query.view == 0 ? '' : ' GROUP BY $group';
    return db.db.transaction((tx) async {
      final count = await tx.rawQuery(
        '${sql.prefix}SELECT COUNT(*) AS n FROM (SELECT 1 ${sql.from}$groupSql)',
        sql.args,
      );
      final rows = await tx.rawQuery(
        '${sql.prefix}SELECT t.*${query.view == 0 ? '' : ', $group AS catalog_key,COUNT(*) AS catalog_count, COUNT(DISTINCT t.source_id) AS catalog_sources'}${query.view == 2 ? ", MIN((CASE WHEN s.kind IN ('emby','jellyfin','plex','subsonic') THEN '0' ELSE '1' END) || json_array(t.source_id,t.id)) AS catalog_portrait_ref" : ''} ${sql.from}$groupSql ORDER BY ${_order(query)} LIMIT ? OFFSET ?',
        [...sql.args, limit, offset],
      );
      final portraits = <String, Track>{};
      if (query.view == 2 && rows.isNotEmpty) {
        final refs = [
          for (final row in rows)
            TrackRef.parse(
              (row['catalog_portrait_ref'] as String).substring(1),
            ),
        ];
        final candidates = await tx.rawQuery(
          'SELECT * FROM tracks WHERE ${List.filled(refs.length, '(source_id=? AND id=?)').join(' OR ')}',
          [
            for (final ref in refs) ...[ref.sourceId, ref.id],
          ],
        );
        for (final candidate in candidates) {
          final track = Track.fromRow(candidate);
          portraits[track.ref.key] = track;
        }
      }
      return CatalogPage(
        rows
            .map(
              (row) => CatalogRow(
                row,
                portrait: query.view == 2
                    ? portraits[(row['catalog_portrait_ref'] as String)
                          .substring(1)]
                    : null,
              ),
            )
            .toList(),
        count.single['n'] as int,
      );
    });
  }

  static ({String source, String? path, String? prefix}) _folderScope(
    String key,
  ) {
    final value = jsonDecode(key);
    if (value is! List ||
        value.length != 2 ||
        value[0] is! String ||
        (value[1] != null && value[1] is! String)) {
      throw const FormatException('无效文件夹');
    }
    final path = value[1] as String?;
    return (
      source: value[0] as String,
      path: path,
      prefix: path == null
          ? null
          : path == '.'
          ? './'
          : path.endsWith('/')
          ? path
          : '$path/',
    );
  }

  /// Project each matching path to its immediate child, keeping pagination,
  /// search and subtree counts in SQL. Songs directly in a folder stay visible
  /// alongside child folders. No full-library Track objects are materialized.
  Future<CatalogPage> _folderPage(CatalogQuery query, int offset, int limit) {
    final root = query.groupKey == null;
    final scope = root ? null : _folderScope(query.groupKey!);
    final sql = _from(
      CatalogQuery(
        view: 3,
        search: query.search,
        sourceId: query.sourceId,
        blocked: query.blocked,
      ),
    );
    final from = sql.from.replaceFirst(
      'LEFT JOIN blacklist',
      'CROSS JOIN browse_scope q LEFT JOIN blacklist',
    );
    final prefix =
        '''${sql.prefix},
      browse_scope AS (SELECT ? AS source,? AS parent,? AS prefix,? AS at_root),
      music_directories AS (
        SELECT DISTINCT f.source_id,f.directory
        FROM folders f JOIN tracks t ON t.source_id=f.source_id AND t.id=f.id
        JOIN sources s ON s.id=t.source_id
        LEFT JOIN blacklist b ON b.source_id=t.source_id AND b.id=t.id
        WHERE ${query.blocked ? 'b.track_key IS NOT NULL' : 't.missing=0 AND s.enabled=1 AND b.track_key IS NULL'}),
      initial_roots AS (
        SELECT d.* FROM music_directories d WHERE NOT EXISTS (
          SELECT 1 FROM music_directories a WHERE a.source_id=d.source_id
          AND a.directory IS NOT d.directory AND
          substr(d.directory,1,length(CASE WHEN a.directory='.' THEN './'
            WHEN substr(a.directory,-1)='/' THEN a.directory
            ELSE a.directory || '/' END))=
          CASE WHEN a.directory='.' THEN './'
            WHEN substr(a.directory,-1)='/' THEN a.directory
            ELSE a.directory || '/' END)),
      scoped AS (
        SELECT t.*,s.kind AS source_kind,
          CASE WHEN q.at_root=1 THEN
            (SELECT r.directory FROM initial_roots r WHERE r.source_id=t.source_id
              AND (r.directory IS f.directory OR
                substr(f.directory,1,length(CASE WHEN r.directory='.' THEN './'
                  WHEN substr(r.directory,-1)='/' THEN r.directory
                  ELSE r.directory || '/' END))=
                CASE WHEN r.directory='.' THEN './'
                  WHEN substr(r.directory,-1)='/' THEN r.directory
                  ELSE r.directory || '/' END)
              ORDER BY length(r.directory),r.directory LIMIT 1)
          WHEN f.directory IS q.parent THEN NULL
          ELSE q.prefix || CASE
            WHEN instr(substr(f.directory,length(q.prefix)+1),'/')>0 THEN
              substr(f.directory,length(q.prefix)+1,
                instr(substr(f.directory,length(q.prefix)+1),'/')-1)
            ELSE substr(f.directory,length(q.prefix)+1) END
          END AS catalog_folder,
          CASE WHEN q.at_root=1 OR f.directory IS NOT q.parent
            THEN 1 ELSE 0 END AS catalog_is_folder
        $from AND (q.at_root=1 OR (t.source_id=q.source AND
          (f.directory IS q.parent OR (q.prefix IS NOT NULL AND
            substr(f.directory,1,length(q.prefix))=q.prefix))))),
      entries AS (
        SELECT *,CASE WHEN catalog_is_folder=1
          THEN json_array(source_id,catalog_folder)
          ELSE json_array('song',source_id,id) END AS catalog_key
        FROM scoped)
      ''';
    final args = <Object?>[
      scope?.source,
      scope?.path,
      scope?.prefix,
      root ? 1 : 0,
      ...sql.args,
    ];
    final order = switch (query.sort) {
      'year' => 'MAX(year)',
      'duration' => 'SUM(duration_ms)',
      'track_number' => 'disc,number',
      'artist' => 'artist COLLATE NOCASE',
      'album' => 'album COLLATE NOCASE',
      _ => 'CASE WHEN catalog_is_folder=1 THEN catalog_folder ELSE title END COLLATE NOCASE',
    };
    return db.db.transaction((tx) async {
      final count = await tx.rawQuery(
        '${prefix}SELECT COUNT(DISTINCT catalog_key) AS n FROM entries',
        args,
      );
      final rows = await tx.rawQuery(
        '''${prefix}SELECT *,COUNT(*) AS catalog_count,
        COUNT(DISTINCT source_id) AS catalog_sources,
        CASE WHEN source_kind='webdav' THEN 1 ELSE 0 END AS catalog_folder_encoded
        FROM entries GROUP BY catalog_key ORDER BY catalog_is_folder DESC,
        $order ${query.descending ? 'DESC' : 'ASC'},source_id,id LIMIT ? OFFSET ?''',
        [...args, limit, offset],
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
      '${sql.prefix}SELECT t.source_id,t.id ${sql.from} ORDER BY ${_order(query)}',
      sql.args,
    );
    return rows
        .map((row) => TrackRef(row['source_id'] as String, row['id'] as String))
        .toList();
  }
}
