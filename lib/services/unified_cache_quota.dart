import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';

import '../data/app_db.dart';

/// One physical-disk budget for complete audio, covers and lyrics.
/// A shared album image is charged once, regardless of how many tracks use it.
class CacheUsage {
  const CacheUsage({
    required this.audio,
    required this.cover,
    required this.lyrics,
  });
  final int audio, cover, lyrics;
  int get total => audio + cover + lyrics;
}

class UnifiedCacheQuota {
  UnifiedCacheQuota(this.db, this.dataRoot)
    : maxBytes = Platform.isWindows || Platform.isLinux
          ? 10 * 1024 * 1024 * 1024
          : 5 * 1024 * 1024 * 1024;

  final AppDb db;
  final Directory dataRoot;
  final Lock lock = Lock();
  int maxBytes;
  bool Function(String key)? audioProtected;
  bool Function(String sourceId, String assetKey)? assetProtected;
  void Function(String sourceId, String assetKey, String kind)? onAssetEvicted;
  Future<void>? _initializing;

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    final setting = await db.setting('cache_limit');
    if (setting != null) maxBytes = int.tryParse(setting) ?? maxBytes;
  }

  Future<CacheUsage> usage() async {
    final audio = await db.db.rawQuery(
      'SELECT COALESCE(SUM(bytes),0) AS size FROM cache',
    );
    final assets = await db.db.rawQuery('''
      SELECT kind, COALESCE(SUM(bytes),0) AS size FROM (
        SELECT kind,relative_file,MAX(bytes) AS bytes
        FROM media_assets GROUP BY kind,relative_file
      ) GROUP BY kind
    ''');
    int amount(String kind) => assets
        .where((row) => row['kind'] == kind)
        .fold<int>(0, (sum, row) => sum + (row['size'] as int));
    return CacheUsage(
      audio: audio.single['size'] as int,
      cover: amount('cover'),
      lyrics: amount('lyrics'),
    );
  }

  /// Admission and its SQLite/file commit share the same lock across both
  /// stores, so simultaneous downloads cannot oversubscribe the quota.
  Future<T> admit<T>(
    int bytes,
    Future<T> Function() commit, {
    String? audioKey,
    String? assetSource,
    String? assetKey,
    String? assetFile,
  }) async {
    await initialize();
    return lock.synchronized(() async {
      if (bytes > maxBytes) throw StateError('单个资源超过统一缓存容量');
      var incoming = bytes;
      if (assetFile != null) {
        final existing = await db.db.query(
          'media_assets',
          columns: ['asset_key'],
          where: 'relative_file=?',
          whereArgs: [assetFile],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          incoming = 0;
        } else if (assetSource != null &&
            assetKey != null &&
            !(assetProtected?.call(assetSource, assetKey) ?? false)) {
          final old = await db.db.rawQuery(
            '''
            SELECT bytes FROM media_assets a WHERE source_id=? AND asset_key=?
            AND NOT EXISTS (SELECT 1 FROM media_assets b
              WHERE b.relative_file=a.relative_file
              AND (b.source_id!=a.source_id OR b.asset_key!=a.asset_key))
          ''',
            [assetSource, assetKey],
          );
          if (old.isNotEmpty) {
            incoming = (bytes - (old.single['bytes'] as int)).clamp(0, bytes);
          }
        }
      } else if (audioKey != null) {
        final existing = await db.db.query(
          'cache',
          columns: ['bytes'],
          where: 'track_key=?',
          whereArgs: [audioKey],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          incoming = (bytes - (existing.first['bytes'] as int)).clamp(0, bytes);
        }
      }
      await _trim(
        incoming: incoming,
        audioKey: audioKey,
        assetSource: assetSource,
        assetKey: assetKey,
        assetFile: assetFile,
      );
      final result = await commit();
      await _trim(
        audioKey: audioKey,
        assetSource: assetSource,
        assetKey: assetKey,
        assetFile: assetFile,
      );
      return result;
    });
  }

  Future<void> enforce({int incoming = 0}) async {
    await initialize();
    await lock.synchronized(() => _trim(incoming: incoming));
  }

  File _file(String folder, String relative) {
    final base = p.join(dataRoot.path, folder);
    final target = p.normalize(p.join(base, relative));
    if (!p.isWithin(base, target)) throw StateError('无效缓存路径');
    return File(target);
  }

  Future<void> _trim({
    int incoming = 0,
    String? audioKey,
    String? assetSource,
    String? assetKey,
    String? assetFile,
  }) async {
    if ((await usage()).total + incoming <= maxBytes) return;
    final audioRows = await db.db.query('cache', orderBy: 'last_used ASC');
    final assetRows = await db.db.query(
      'media_assets',
      where: 'pinned=0',
      orderBy: 'last_used ASC',
    );
    final candidates =
        <({bool audio, Map<String, Object?> row})>[
          for (final row in audioRows) (audio: true, row: row),
          for (final row in assetRows) (audio: false, row: row),
        ]..sort(
          (a, b) =>
              (a.row['last_used'] as int).compareTo(b.row['last_used'] as int),
        );
    var used = (await usage()).total;
    for (final entry in candidates) {
      if (used + incoming <= maxBytes) break;
      final row = entry.row;
      if (entry.audio) {
        final key = row['track_key'] as String;
        if (key == audioKey || (audioProtected?.call(key) ?? false)) continue;
        final file = _file('audio', row['relative_file'] as String);
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          continue;
        }
        await db.db.delete('cache', where: 'track_key=?', whereArgs: [key]);
        used -= row['bytes'] as int;
      } else {
        final source = row['source_id'] as String;
        final key = row['asset_key'] as String;
        if ((source == assetSource && key == assetKey) ||
            (assetProtected?.call(source, key) ?? false)) {
          continue;
        }
        final relative = row['relative_file'] as String;
        if (relative == assetFile) continue;
        final refs = await db.db.rawQuery(
          'SELECT COUNT(*) AS n FROM media_assets WHERE relative_file=?',
          [relative],
        );
        final isLast = refs.single['n'] == 1;
        if (isLast) {
          final file = _file('media_assets', relative);
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {
            continue;
          }
        }
        await db.db.delete(
          'media_assets',
          where: 'source_id=? AND asset_key=? AND pinned=0',
          whereArgs: [source, key],
        );
        if (isLast) used -= row['bytes'] as int;
        onAssetEvicted?.call(source, key, row['kind'] as String);
      }
    }
    if (incoming > 0 && used + incoming > maxBytes) {
      throw StateError('正在使用或手动保护的资源无法淘汰，统一缓存空间不足');
    }
  }
}
