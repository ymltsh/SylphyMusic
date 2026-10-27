import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:disk_space_2/disk_space_2.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm;
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

import '../core/models.dart';
import '../data/app_db.dart';

class AssetPayload {
  const AssetPayload(
    this.bytes, {
    this.etag,
    this.lastModified,
    this.unchanged = false,
  });
  final List<int> bytes;
  final String? etag, lastModified;
  final bool unchanged;
}

class MediaAsset {
  MediaAsset(this.file, this.row);
  final File file;
  final Map<String, Object?> row;
  String get version => row['version'] as String;
  String get digest => row['sha256'] as String;
  String? get etag => row['etag'] as String?;
  String? get lastModified => row['last_modified'] as String?;
  int get expiresAt => row['expires_at'] as int;
}

typedef AssetChange = ({String sourceId, String key, String kind});
typedef AssetLoader = Future<AssetPayload?> Function(MediaAsset? previous);

/// Immutable files with a transactional SQLite manifest. Readers always see
/// either the previous complete asset or a fully validated new asset.
class MediaAssetStore extends ChangeNotifier {
  MediaAssetStore(
    this.db,
    this.root, {
    this.coverBudget = 200 * 1024 * 1024,
    this.lyricsBudget = 20 * 1024 * 1024,
    DateTime Function()? clock,
    Future<double?> Function()? freeSpace,
  }) : clock = clock ?? DateTime.now,
       freeSpace =
           freeSpace ?? (() => DiskSpace.getFreeDiskSpaceForPath(root.path));
  final AppDb db;
  final Directory root;
  final int coverBudget, lyricsBudget;
  final DateTime Function() clock;
  final Future<double?> Function() freeSpace;
  final Lock _lock = Lock();
  final Map<String, Future<MediaAsset?>> _pending = {};
  final Map<String, ({int until, Object? error})> _backoff = {};
  final Map<String, String> _verified = {};
  final Map<String, List<File>> _retired = {};
  final Set<Future<void>> _maintenance = {};
  final Map<String, int> _epochs = {}, _revisions = {}, _leases = {};
  final Map<String, String> _desiredVersions = {};
  Future<void>? _initializing;
  bool _stopped = false;
  bool _trimNeeded = false;
  AssetChange? lastChange;
  Directory get directory => Directory(p.join(root.path, 'media_assets'));
  String _hash(String value) => sha256.convert(utf8.encode(value)).toString();
  String _identity(String source, String key) => jsonEncode([source, key]);
  int revision(String source, String key) =>
      _revisions[_identity(source, key)] ?? 0;
  void retain(String source, String key) =>
      _leases.update(_identity(source, key), (v) => v + 1, ifAbsent: () => 1);
  void release(String source, String key) {
    final id = _identity(source, key),
        count = (_leases[_identity(source, key)] ?? 0) - 1;
    if (count <= 0) {
      _leases.remove(id);
      if (!_stopped && (_retired.containsKey(id) || _trimNeeded)) {
        final work = _lock.synchronized(() async {
          for (final file in _retired.remove(id) ?? <File>[]) {
            await _unlinkUnused(file);
          }
          await _trim();
        });
        _maintenance.add(work);
        unawaited(
          work.then<void>(
            (_) => _maintenance.remove(work),
            onError: (Object _, StackTrace _) => _maintenance.remove(work),
          ),
        );
      }
    } else {
      _leases[id] = count;
    }
  }

  File _file(String relative) {
    final target = p.normalize(p.join(directory.path, relative));
    if (!p.isWithin(directory.path, target)) throw StateError('无效媒体缓存路径');
    return File(target);
  }

  Future<void> initialize() => _initializing ??= _initialize();
  Future<bool> migratedLegacy(String source, String key) async =>
      (await db.db.query(
        'media_asset_migrations',
        columns: ['asset_key'],
        where: 'source_id=? AND asset_key=?',
        whereArgs: [source, key],
        limit: 1,
      )).isNotEmpty;
  Future<void> markLegacy(String source, String key) async {
    await db.db.insert('media_asset_migrations', {
      'source_id': source,
      'asset_key': key,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _initialize() async {
    await db.db.execute(
      'DELETE FROM media_asset_migrations WHERE source_id NOT IN (SELECT id FROM sources)',
    );
    await Directory(p.join(directory.path, 'objects')).create(recursive: true);
    final tmp = await Directory(p.join(directory.path, 'tmp'))
        .create(recursive: true);
    await for (final entry in tmp.list(followLinks: false)) {
      if (entry is File) await entry.delete();
    }
    final referenced = <String>{};
    var after = 0;
    while (true) {
      final rows = await db.db.rawQuery(
        'SELECT a.rowid AS asset_row,a.*,s.id AS valid_source FROM media_assets a LEFT JOIN sources s ON a.source_id=s.id WHERE a.rowid>? ORDER BY a.rowid LIMIT 250',
        [after],
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        after = row['asset_row'] as int;
        File? file;
        try {
          file = _file(row['relative_file'] as String);
        } catch (_) {
          /* invalid manifest */
        }
        if (row['valid_source'] == null ||
            file == null ||
            !await file.exists() ||
            (row['pinned'] != 1 && await file.length() != row['bytes'])) {
          await db.db.delete(
            'media_assets',
            where: 'rowid=?',
            whereArgs: [after],
          );
        } else {
          referenced.add(file.path);
        }
      }
    }
    await for (final entry in Directory(
      p.join(directory.path, 'objects'),
    ).list(recursive: true, followLinks: false)) {
      if (entry is File && !referenced.contains(entry.path)) {
        await entry.delete();
      }
    }
    await _trim();
  }

  Future<MediaAsset?> read(String source, String key) async {
    await initialize();
    return _lock.synchronized(() async {
      final rows = await db.db.query(
        'media_assets',
        where: 'source_id=? AND asset_key=?',
        whereArgs: [source, key],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.single;
      File? file;
      try {
        file = _file(row['relative_file'] as String);
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file ||
            stat.size != row['bytes']) {
          throw StateError('缓存长度不匹配');
        }
        final signature =
            '${stat.modified.microsecondsSinceEpoch}/${stat.size}/${row['sha256']}';
        if (_verified[file.path] != signature) {
          final bytes = await file.readAsBytes();
          if (sha256.convert(bytes).toString() != row['sha256']) {
            throw StateError('缓存校验失败');
          }
          await _validate(row['kind'] as String, bytes);
          _verified[file.path] = signature;
        }
        await db.db.update(
          'media_assets',
          {'last_used': clock().millisecondsSinceEpoch},
          where: 'source_id=? AND asset_key=?',
          whereArgs: [source, key],
        );
        return MediaAsset(file, row);
      } catch (_) {
        // Manual imports are user data: retain damaged bytes for recovery.
        if (row['pinned'] == 1) return null;
        await db.db.delete(
          'media_assets',
          where: 'source_id=? AND asset_key=?',
          whereArgs: [source, key],
        );
        if (file != null) await _unlinkUnused(file);
        return null;
      }
    });
  }

  Future<MediaAsset?> get(
    SourceProfile source,
    String key,
    String kind,
    String version,
    AssetLoader loader, {
    bool forceRefresh = false,
    Duration ttl = const Duration(hours: 24),
  }) async {
    if (_stopped || !source.enabled) return null;
    final epoch = _epochs[source.id] ?? 0;
    final current = await db.source(source.id);
    if (current == null ||
        !current.enabled ||
        current.url != source.url ||
        current.username != source.username) {
      return null;
    }
    final previous = await read(source.id, key);
    if (_stopped) return previous;
    if (!forceRefresh &&
        previous != null &&
        previous.version == version &&
        previous.expiresAt > clock().millisecondsSinceEpoch) {
      return previous;
    }
    final id = _identity(source.id, key);
    final delay = _backoff[id];
    if (!forceRefresh &&
        delay != null &&
        delay.until > clock().millisecondsSinceEpoch) {
      if (previous == null && delay.error != null) throw delay.error!;
      return previous;
    }
    _desiredVersions[id] = version;
    final requestId = jsonEncode([source.id, key, version, epoch]);
    final refresh = _pending.putIfAbsent(requestId, () {
      final work = Future<MediaAsset?>.microtask(() async {
        try {
          if (_stopped || epoch != (_epochs[source.id] ?? 0)) return previous;
          final payload = await loader(previous);
          if (payload == null) {
            _backoff[id] = (
              until: clock()
                  .add(const Duration(minutes: 1))
                  .millisecondsSinceEpoch,
              error: null,
            );
            return previous;
          }
          final bytes = payload.unchanged && previous != null
              ? await previous.file.readAsBytes()
              : payload.bytes;
          final result = await put(
            source.id,
            key,
            kind,
            version,
            bytes,
            ttl: ttl,
            etag: payload.etag ?? (payload.unchanged ? previous?.etag : null),
            lastModified:
                payload.lastModified ??
                (payload.unchanged ? previous?.lastModified : null),
            guard: () async {
              final active = await db.source(source.id);
              return !_stopped &&
                  epoch == (_epochs[source.id] ?? 0) &&
                  _desiredVersions[id] == version &&
                  active != null &&
                  active.enabled &&
                  active.url == source.url &&
                  active.username == source.username &&
                  active.kind == source.kind;
            },
          );
          _backoff.remove(id);
          return result;
        } catch (error) {
          _backoff[id] = (
            until: clock()
                .add(const Duration(seconds: 30))
                .millisecondsSinceEpoch,
            error: error,
          );
          if (previous != null) return previous;
          rethrow;
        }
      });
      unawaited(
        work.then<void>(
          (_) {
            _pending.remove(requestId);
          },
          onError: (Object _, StackTrace _) {
            _pending.remove(requestId);
          },
        ),
      );
      return work;
    });
    if (previous != null && !forceRefresh) {
      unawaited(
        refresh.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      return previous;
    }
    return refresh;
  }

  Future<void> validate(String kind, List<int> bytes) => _validate(kind, bytes);
  Future<void> _validate(String kind, List<int> bytes) async {
    if (kind != 'cover' && kind != 'lyrics') {
      throw ArgumentError.value(kind, 'kind');
    }
    final max = kind == 'cover' ? 8 * 1024 * 1024 : 1024 * 1024;
    if (bytes.isEmpty || bytes.length > max) throw StateError('媒体缓存内容长度无效');
    if (kind == 'cover') {
      final codec = await ui.instantiateImageCodec(
        Uint8List.fromList(bytes),
        targetWidth: 64,
      );
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    } else {
      if (utf8.decode(bytes).trim().isEmpty) throw StateError('歌词内容为空');
    }
  }

  Future<MediaAsset?> put(
    String source,
    String key,
    String kind,
    String version,
    List<int> bytes, {
    Duration ttl = const Duration(hours: 24),
    bool pinned = false,
    String? etag,
    String? lastModified,
    Future<bool> Function()? guard,
  }) async {
    await initialize();
    await _validate(kind, bytes);
    final epoch = _epochs[source] ?? 0;
    return _lock.synchronized(() async {
      if (_stopped ||
          epoch != (_epochs[source] ?? 0) ||
          (await db.source(source))?.enabled != true ||
          (guard != null && !await guard())) {
        return null;
      }
      double? free;
      try {
        free = await freeSpace();
      } catch (_) {
        /* bounded write still handles filesystem ENOSPC */
      }
      if (free != null && free < 64 + bytes.length / (1024 * 1024)) {
        throw StateError('磁盘可用空间不足，已保留原缓存');
      }
      final digest = sha256.convert(bytes).toString();
      final relative = p.join('objects', _hash(source), '$digest.$kind');
      final target = _file(relative);
      await target.parent.create(recursive: true);
      final temp = File(
        p.join(directory.path, 'tmp', '${const Uuid().v4()}.part'),
      );
      final before = await db.db.query(
        'media_assets',
        where: 'source_id=? AND asset_key=?',
        whereArgs: [source, key],
        limit: 1,
      );
      try {
        await temp.writeAsBytes(bytes, flush: true);
        if (guard != null && !await guard()) return null;
        // Unique temporary names prevent concurrent writers replacing a half file.
        if (await target.exists()) {
          if ((await sha256.bind(target.openRead()).first).toString() !=
              digest) {
            await temp.rename(target.path);
          }
        } else {
          await temp.rename(target.path);
        }
        final now = clock().millisecondsSinceEpoch;
        final row = <String, Object?>{
          'source_id': source,
          'asset_key': key,
          'kind': kind,
          'version': version,
          'relative_file': relative,
          'bytes': bytes.length,
          'sha256': digest,
          'fetched_at': now,
          'last_used': now,
          'expires_at': clock().add(ttl).millisecondsSinceEpoch,
          'pinned': pinned ? 1 : 0,
          'etag': etag,
          'last_modified': lastModified,
        };
        if (_stopped ||
            epoch != (_epochs[source] ?? 0) ||
            (await db.source(source))?.enabled != true ||
            (guard != null && !await guard())) {
          await _unlinkUnused(target);
          return null;
        }
        var committed = false;
        await db.db.transaction((txn) async {
          final active = await txn.query(
            'sources',
            columns: ['id'],
            where: 'id=? AND enabled=1',
            whereArgs: [source],
          );
          if (active.isEmpty || _stopped || epoch != (_epochs[source] ?? 0)) {
            return;
          }
          await txn.insert(
            'media_assets',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          committed = true;
        });
        if (!committed) {
          await _unlinkUnused(target);
          return null;
        }
        if (before.isNotEmpty && before.single['relative_file'] != relative) {
          final oldFile = _file(before.single['relative_file'] as String);
          final id = _identity(source, key);
          if ((_leases[id] ?? 0) > 0) {
            _retired.putIfAbsent(id, () => []).add(oldFile);
          } else {
            await _unlinkUnused(oldFile);
          }
        }
        await _trim(keep: relative);
        if (before.isEmpty ||
            before.single['sha256'] != digest ||
            before.single['version'] != version) {
          final id = _identity(source, key);
          _revisions[id] = (_revisions[id] ?? 0) + 1;
          lastChange = (sourceId: source, key: key, kind: kind);
          notifyListeners();
        }
        return MediaAsset(target, row);
      } finally {
        if (await temp.exists()) await temp.delete();
      }
    });
  }

  Future<void> _unlinkUnused(File file) async {
    final count = await db.db.rawQuery(
      'SELECT COUNT(*) AS n FROM media_assets WHERE relative_file=?',
      [p.relative(file.path, from: directory.path)],
    );
    if (count.single['n'] == 0 && await file.exists()) {
      await file.delete();
      _verified.remove(file.path);
    }
  }

  Future<void> _trim({String? keep}) async {
    var pending = false;
    for (final kind in ['cover', 'lyrics']) {
      final sum = await db.db.rawQuery(
        'SELECT COALESCE(SUM(bytes),0) AS n FROM (SELECT relative_file,MAX(bytes) AS bytes FROM media_assets WHERE kind=? AND pinned=0 AND relative_file NOT IN (SELECT relative_file FROM media_assets WHERE pinned=1) GROUP BY relative_file)',
        [kind],
      );
      var total = sum.single['n'] as int;
      final budget = kind == 'cover' ? coverBudget : lyricsBudget;
      if (total <= budget) continue;
      var afterUsed = -1, afterRow = 0;
      while (total > budget) {
        final candidates = await db.db.rawQuery(
          'SELECT rowid AS asset_row,* FROM media_assets WHERE kind=? AND pinned=0 AND (last_used>? OR (last_used=? AND rowid>?)) ORDER BY last_used,rowid LIMIT 128',
          [kind, afterUsed, afterUsed, afterRow],
        );
        if (candidates.isEmpty) break;
        for (final row in candidates) {
          afterUsed = row['last_used'] as int;
          afterRow = row['asset_row'] as int;
          if (total <= budget) break;
          if (row['relative_file'] == keep ||
              (_leases[_identity(
                        row['source_id'] as String,
                        row['asset_key'] as String,
                      )] ??
                      0) >
                  0) {
            continue;
          }
          await db.db.delete(
            'media_assets',
            where: 'source_id=? AND asset_key=?',
            whereArgs: [row['source_id'], row['asset_key']],
          );
          final file = _file(row['relative_file'] as String);
          await _unlinkUnused(file);
          if (!await file.exists()) total -= row['bytes'] as int;
        }
      }
      if (total > budget) pending = true;
    }
    _trimNeeded = pending;
  }

  void suspendSource(String source) {
    _epochs[source] = (_epochs[source] ?? 0) + 1;
    _backoff.removeWhere((id, _) => (jsonDecode(id) as List).first == source);
  }

  Future<void> clear({String? sourceId, bool includePinned = false}) async {
    await initialize();
    final sources = sourceId != null
        ? [sourceId]
        : (await db.sources()).map((s) => s.id).toList();
    for (final id in sources) {
      suspendSource(id);
    }
    await _lock.synchronized(() async {
      final conditions = [
        if (sourceId != null) 'source_id=?',
        if (!includePinned) 'pinned=0',
      ];
      final where = conditions.isEmpty ? null : conditions.join(' AND ');
      final rows = await db.db.query(
        'media_assets',
        where: where,
        whereArgs: sourceId == null ? null : [sourceId],
      );
      await db.db.delete(
        'media_assets',
        where: where,
        whereArgs: sourceId == null ? null : [sourceId],
      );
      if (includePinned && sourceId != null) {
        await db.db.delete(
          'media_asset_migrations',
          where: 'source_id=?',
          whereArgs: [sourceId],
        );
      }
      for (final row in rows) {
        await _unlinkUnused(_file(row['relative_file'] as String));
      }
      lastChange = null;
      notifyListeners();
    });
  }

  Future<void> shutdown() async {
    _stopped = true;
    await Future.wait(
      _pending.values
          .map(
            (f) => f.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
          )
          .toList(),
    );
    await _lock.synchronized(() async {});
    await Future.wait(_maintenance.toList());
    super.dispose();
  }

  Future<void> waitForIdle() async {
    await Future.wait(
      _pending.values
          .map(
            (f) => f.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
          )
          .toList(),
    );
    await Future.wait(_maintenance.toList());
    await _lock.synchronized(() async {});
  }
}
