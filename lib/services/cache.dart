import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:disk_space_2/disk_space_2.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:synchronized/synchronized.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm;

import '../core/models.dart';
import '../data/app_db.dart';
import 'sources.dart';
import 'openlist_lite.dart';

class CacheEntry {
  const CacheEntry({
    required this.ref,
    required this.file,
    required this.bytes,
    required this.sha,
    required this.lastUsed,
    required this.tag,
  });
  final TrackRef ref;
  final File file;
  final int bytes, lastUsed;
  final String sha, tag;
}

class TransferToken {
  TransferToken({this.automatic = false});
  // A foreground download may claim an in-progress automatic download.
  bool automatic;
  bool cancelled = false;
  void Function()? onCancel;
  void cancel() {
    if (cancelled) return;
    cancelled = true;
    onCancel?.call();
  }
}

class AudioPreview {
  const AudioPreview(this.bytes, this.total, this.etag, this.contentType);
  final Uint8List bytes;
  final int total;
  final String etag;
  final ContentType? contentType;
}

class CacheManager {
  CacheManager(this.store, this.factory, this.root);
  final AppDb store;
  final AdapterFactory factory;
  final Directory root;
  final Map<String, TransferToken> _active = {};
  final Lock _commits = Lock();
  final Set<Future<void>> _cleanup = {};
  final Map<String, int> _leases = {};
  final Map<String, List<File>> _retiredFiles = {};
  final Map<String, String> _verifiedSignatures = {};
  final Set<String> _deleteWhenReleased = {};
  final Map<String, AudioPreview> _previews = {};
  final Map<String, Future<void>> _downloads = {};
  final Map<String, TransferToken> _downloadTokens = {};
  bool _stopped = false;
  final Map<String, int> _sourceEpochs = {};
  String? _prefetchSourceId;
  Future<void> cancelSource(String id) async {
    _sourceEpochs[id] = (_sourceEpochs[id] ?? 0) + 1;
    if (_prefetchSourceId == id) invalidatePreview();
    _previews.removeWhere((key, _) => TrackRef.parse(key).sourceId == id);
    final keys = {..._active.keys, ..._downloadTokens.keys};
    final pending = <Future<void>>[];
    for (final key in keys) {
      final ref = TrackRef.parse(key);
      if (ref.sourceId != id) continue;
      await cancel(ref);
      final download = _downloads[key];
      if (download != null) pending.add(download.catchError((Object _) {}));
    }
    await Future.wait(pending);
  }

  final Set<String> _wholeDemands = {};
  final Set<String> _previewAttempts = {};
  bool playbackActive = false, playbackBuffering = false;
  void updatePlaybackPriority({required bool active, required bool buffering}) {
    playbackActive = active;
    playbackBuffering = buffering;
  }

  Future<void> _backgroundBudget(TransferToken token, {int bytes = 0}) async {
    while (playbackActive && playbackBuffering && !token.cancelled) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (token.cancelled) throw StateError('缓存任务已取消');
    if (playbackActive && bytes > 0) {
      // Apply TCP backpressure to background reads while audio is active.
      await Future<void>.delayed(
        Duration(microseconds: bytes * 1000000 ~/ (2 * 1024 * 1024)),
      );
    }
  }

  int _previewGeneration = 0;
  HttpClient? _prefetchClient;
  AudioPreview? preview(TrackRef ref) => _previews[ref.key];
  int maxBytes = 5 * 1024 * 1024 * 1024;
  int get concurrent => _active.length;
  Future<void> _spaceGuard([int requested = 0]) async {
    final path = root.path;
    final freeMb = await DiskSpace.getFreeDiskSpaceForPath(path);
    final totalMb = await DiskSpace.getTotalDiskSpace;
    if (freeMb == null || totalMb == null) {
      throw StateError('无法确认存储空间安全余量，已暂停新增缓存');
    }
    final desktop = Platform.isWindows || Platform.isLinux;
    final reserveMb = desktop
        ? (totalMb * 0.02).clamp(2048.0, 10240.0)
        : (totalMb * 0.05).clamp(1024.0, 4096.0);
    if (freeMb * 1024 * 1024 - requested < reserveMb * 1024 * 1024) {
      await enforceQuota();
      final refreshed = await DiskSpace.getFreeDiskSpaceForPath(path);
      if (refreshed == null ||
          refreshed * 1024 * 1024 - requested < reserveMb * 1024 * 1024) {
        throw StateError('磁盘剩余空间低于安全保留值，缓存暂停');
      }
    }
  }

  Future<void> initialize() async {
    if (Platform.isWindows || Platform.isLinux) {
      maxBytes = 10 * 1024 * 1024 * 1024;
    }
    await Directory(p.join(root.path, 'ready')).create(recursive: true);
    final temp = Directory(p.join(root.path, 'tmp'));
    await temp.create(recursive: true);
    await for (final f in temp.list()) {
      try {
        await f.delete(recursive: true);
      } catch (_) {}
    }
    final rows = await store.db.query('cache');
    for (final r in rows) {
      if (!await File(p.join(root.path, r['relative_file'] as String))
          .exists()) {
        await store.db.delete(
          'cache',
          where: 'track_key=?',
          whereArgs: [r['track_key']],
        );
      }
    }
    final indexed = rows.map((r) => r['relative_file']).toSet();
    await for (final file in Directory(p.join(root.path, 'ready')).list()) {
      if (file is File &&
          !indexed.contains(p.relative(file.path, from: root.path))) {
        await file.delete();
      }
    }
    final quota = await store.setting('cache_limit');
    if (quota != null) maxBytes = int.tryParse(quota) ?? maxBytes;
  }

  String _filename(TrackRef ref) =>
      sha256.convert(utf8.encode(ref.key)).toString();
  Future<CacheEntry?> find(TrackRef ref, {bool touch = false}) async {
    final row = (await store.db.query(
      'cache',
      where: 'track_key=?',
      whereArgs: [ref.key],
      limit: 1,
    ));
    if (row.isEmpty) return null;
    final m = row.first;
    final file = File(p.join(root.path, m['relative_file'] as String));
    final track = await store.track(ref);
    final stat = await file.stat();
    final signature =
        '${m['sha256']}/${stat.modified.microsecondsSinceEpoch}/${stat.size}';
    final wrongVersion =
        track != null &&
        (m['metadata_version'] as String? ?? '').isNotEmpty &&
        m['metadata_version'] != track.resourceVersion;
    final wrongHash =
        stat.type == FileSystemEntityType.file &&
        stat.size == m['bytes'] &&
        _verifiedSignatures[ref.key] != signature &&
        (await sha256.bind(file.openRead()).first).toString() != m['sha256'];
    if (stat.type != FileSystemEntityType.file ||
        stat.size != m['bytes'] ||
        wrongVersion ||
        wrongHash) {
      await store.db.delete(
        'cache',
        where: 'track_key=?',
        whereArgs: [ref.key],
      );
      _verifiedSignatures.remove(ref.key);
      if (await file.exists()) {
        if ((_leases[ref.key] ?? 0) == 0) {
          await file.delete();
        } else {
          _retiredFiles.putIfAbsent(ref.key, () => []).add(file);
        }
      }
      return null;
    }
    _verifiedSignatures[ref.key] = signature;
    if (touch) {
      await store.db.update(
        'cache',
        {'last_used': DateTime.now().millisecondsSinceEpoch},
        where: 'track_key=?',
        whereArgs: [ref.key],
      );
    }
    return CacheEntry(
      ref: ref,
      file: file,
      bytes: m['bytes'] as int,
      sha: m['sha256'] as String,
      lastUsed: m['last_used'] as int,
      tag: m['resource_tag'] as String,
    );
  }

  Future<bool> contains(TrackRef ref) => find(ref).then((x) => x != null);
  void lease(TrackRef ref) =>
      _leases.update(ref.key, (v) => v + 1, ifAbsent: () => 1);
  void release(TrackRef ref) {
    final n = (_leases[ref.key] ?? 0) - 1;
    if (n <= 0) {
      _leases.remove(ref.key);
      final retired = _retiredFiles.remove(ref.key) ?? [];
      if (retired.isNotEmpty) {
        final cleanup = Future<void>(() async {
          for (final file in retired) {
            if (await file.exists()) await file.delete();
          }
        });
        _cleanup.add(cleanup);
        unawaited(cleanup.whenComplete(() => _cleanup.remove(cleanup)));
      }
      if (_deleteWhenReleased.remove(ref.key)) {
        final cleanup = Future<void>(() async {
          final row = await store.db.query(
            'cache',
            where: 'track_key=?',
            whereArgs: [ref.key],
            limit: 1,
          );
          if (row.isNotEmpty) {
            await store.db.delete(
              'cache',
              where: 'track_key=?',
              whereArgs: [ref.key],
            );
            try {
              await File(
                p.join(root.path, row.first['relative_file'] as String),
              ).delete();
            } catch (_) {}
          }
        });
        _cleanup.add(cleanup);
        unawaited(cleanup.whenComplete(() => _cleanup.remove(cleanup)));
      }
    } else {
      _leases[ref.key] = n;
    }
  }

  /// A cache job owns its explicit download, not the playback relay for the
  /// same track. Pausing a dataSync service must never close the mpv upstream.
  void cancelDownload(TrackRef ref) {
    _downloadTokens[ref.key]?.cancel();
  }

  Future<void> cancel(TrackRef ref, {bool automaticOnly = false}) async {
    final token = _active[ref.key];
    if (!automaticOnly) cancelDownload(ref);
    if (automaticOnly && _wholeDemands.contains(ref.key)) return;
    if (token != null && (!automaticOnly || token.automatic)) token.cancel();
    // An automatic whole-file transfer can still be resolving the source or
    // waiting behind a relay before it is registered in _active.
    final download = _downloadTokens[ref.key];
    if (automaticOnly && download?.automatic == true) download!.cancel();
    _previews.remove(ref.key);
  }

  Future<void> clear({String? sourceId, Set<String>? keys}) async {
    for (final key in _active.keys.toList()) {
      final ref = TrackRef.parse(key);
      if ((sourceId == null || ref.sourceId == sourceId) &&
          (keys == null || keys.contains(key))) {
        await cancel(ref);
      }
    }
    _previews.removeWhere(
      (key, _) =>
          (sourceId == null || TrackRef.parse(key).sourceId == sourceId) &&
          (keys == null || keys.contains(key)),
    );
    final rows = await store.db.query('cache');
    for (final row in rows) {
      final key = row['track_key'] as String;
      final ref = TrackRef.parse(key);
      if ((sourceId != null && ref.sourceId != sourceId) ||
          (keys != null && !keys.contains(key))) {
        continue;
      }
      await cancel(ref);
      if ((_leases[key] ?? 0) > 0) {
        _deleteWhenReleased.add(key);
        continue;
      } // Cleanup after active reader releases.
      await store.db.delete('cache', where: 'track_key=?', whereArgs: [key]);
      try {
        await File(p.join(root.path, row['relative_file'] as String)).delete();
      } catch (_) {}
    }
  }

  Future<void> enforceQuota({int incoming = 0}) async {
    final rows = await store.db.query('cache', orderBy: 'last_used ASC');
    var total = rows.fold<int>(0, (n, r) => n + (r['bytes'] as int));
    for (final row in rows) {
      if (total + incoming <= maxBytes) break;
      final key = row['track_key'] as String;
      if ((_leases[key] ?? 0) > 0) continue;
      try {
        await File(p.join(root.path, row['relative_file'] as String)).delete();
      } catch (_) {
        continue;
      }
      await store.db.delete('cache', where: 'track_key=?', whereArgs: [key]);
      total -= row['bytes'] as int;
    }
  }

  Future<void> _commit(
    TrackRef ref,
    File tmp,
    int bytes,
    String tag,
    TransferToken token,
    String metadataVersion,
  ) => _commits.synchronized(
    () => _commitLocked(ref, tmp, bytes, tag, token, metadataVersion),
  );

  Future<void> _commitLocked(
    TrackRef ref,
    File tmp,
    int bytes,
    String tag,
    TransferToken token,
    String metadataVersion,
  ) async {
    final hash = (await sha256.bind(tmp.openRead()).first).toString();
    if (token.cancelled) return;
    await enforceQuota(incoming: bytes);
    if (token.cancelled) return;
    final rows = await store.db.query('cache', columns: ['bytes']);
    if (rows.fold<int>(0, (sum, row) => sum + (row['bytes'] as int)) + bytes >
        maxBytes) {
      throw StateError('正在使用的缓存无法淘汰，已暂停新增缓存');
    }
    final rel = p.join('ready', '${_filename(ref)}-${const Uuid().v4()}');
    final dest = File(p.join(root.path, rel));
    if (await dest.exists()) await dest.delete();
    await tmp.rename(dest.path); // Same-volume atomic rename.
    if (token.cancelled) {
      await dest.delete();
      return;
    }
    await store.db.insert('cache', {
      'track_key': ref.key,
      'relative_file': rel,
      'bytes': bytes,
      'sha256': hash,
      'resource_tag': tag,
      'metadata_version': metadataVersion,
      'last_used': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (token.cancelled) {
      await store.db.delete(
        'cache',
        where: 'track_key=?',
        whereArgs: [ref.key],
      );
      if (await dest.exists()) await dest.delete();
    }
    await enforceQuota();
  }

  Future<void> captureRelay(
    TrackRef ref,
    Stream<List<int>> upstream,
    Future<void> Function(List<int>) emit, {
    required int expected,
    required bool full,
    String tag = '',
    void Function()? onCancel,
    String metadataVersion = '',
  }) async {
    final canOwn =
        !_stopped && !_active.containsKey(ref.key) && await find(ref) == null;
    if (!canOwn) {
      await for (final b in upstream) {
        try {
          await emit(b);
        } catch (_) {
          break;
        }
      }
      return;
    }
    try {
      await _spaceGuard(expected > 0 ? expected : 0);
    } catch (_) {
      // Playback must never be blocked by the optional cache pipeline.
      await for (final b in upstream) {
        try {
          await emit(b);
        } catch (_) {
          break;
        }
      }
      return;
    }
    if (_active.containsKey(ref.key)) {
      await for (final chunk in upstream) {
        await emit(chunk);
      }
      return;
    }
    final token = TransferToken(automatic: true);
    token.onCancel = onCancel;
    _active[ref.key] = token;
    final tmp = File(p.join(root.path, 'tmp', '${const Uuid().v4()}.partial'));
    IOSink? sink;
    var socketBroken = false, got = 0, discard = false;
    try {
      if (!full || expected <= 0 || expected > maxBytes) {
        await for (final b in upstream) {
          if (token.cancelled) break;
          try {
            await emit(b);
          } catch (_) {
            break;
          }
        }
        return;
      }
      sink = tmp.openWrite();
      await for (final chunk in upstream) {
        if (token.cancelled) break;
        if (socketBroken) await _backgroundBudget(token, bytes: chunk.length);
        if (!socketBroken) {
          try {
            await emit(chunk);
          } catch (_) {
            socketBroken = true;
          }
        }
        if (!discard) {
          if (got + chunk.length > maxBytes) {
            discard = true;
            await sink?.close();
            sink = null;
          } else {
            sink?.add(chunk);
            got += chunk.length;
          }
        }
      }
      if (sink != null) {
        await sink.flush();
        await sink.close();
        sink = null;
      }
      if (!discard &&
          !token.cancelled &&
          got > 0 &&
          got <= maxBytes &&
          (expected < 0 || got == expected)) {
        await _commit(ref, tmp, got, tag, token, metadataVersion);
      }
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      _active.remove(ref.key);
    }
  }

  Future<void> fetchWhole(
    Track track,
    SourceProfile profile, {
    TransferToken? token,
    bool automatic = false,
  }) async {
    final key = track.ref.key;
    final existing = _downloads[key];
    if (existing != null) {
      if (!automatic) {
        // A manual request takes ownership of a shared automatic transfer.
        _wholeDemands.add(key);
        final running = _downloadTokens[key];
        if (running != null) running.automatic = false;
      }
      return existing;
    }
    final demandToken = token ?? TransferToken(automatic: automatic);
    _downloadTokens[key] = demandToken;
    if (!automatic) _wholeDemands.add(key);
    final future = _fetchWhole(track, profile, token: demandToken);
    _downloads[key] = future;
    try {
      await future;
    } finally {
      _downloads.remove(key);
      _wholeDemands.remove(key);
      _downloadTokens.remove(key);
    }
  }

  Future<void> _fetchWhole(
    Track track,
    SourceProfile profile, {
    TransferToken? token,
  }) async {
    final epoch = _sourceEpochs[profile.id] ?? 0;
    if (_stopped || token?.cancelled == true) throw StateError('缓存任务已取消');
    if (await contains(track.ref)) return;
    while (_active.containsKey(track.ref.key)) {
      if (token?.cancelled == true) throw StateError('缓存任务已取消');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (_stopped || token?.cancelled == true) throw StateError('缓存任务已取消');
    if (await contains(track.ref)) return;
    await _spaceGuard();
    final current = await store.source(profile.id);
    if (epoch != (_sourceEpochs[profile.id] ?? 0) ||
        current == null ||
        !current.enabled ||
        current.url != profile.url ||
        current.username != profile.username) {
      throw StateError('来源已停用或连接已变化');
    }
    // captureRelay may have claimed this track while _spaceGuard/store.source
    // was awaiting. Never overwrite its token with a download token: doing so
    // loses cancellation ownership and can leak an in-flight relay.
    while (_active.containsKey(track.ref.key)) {
      if (_stopped || token?.cancelled == true) {
        throw StateError('缓存任务已取消');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (_stopped ||
        token?.cancelled == true ||
        epoch != (_sourceEpochs[profile.id] ?? 0)) {
      throw StateError('缓存任务已取消或来源已变化');
    }
    final adapter = factory.create(profile);
    final t = token ?? TransferToken();
    _active[track.ref.key] = t;
    final tmp = File(p.join(root.path, 'tmp', '${const Uuid().v4()}.partial'));
    HttpClient? client;
    IOSink? sink;
    final openListLease = 'cache:${const Uuid().v4()}';
    try {
      await OpenListLite.acquireTask(profile.url, openListLease);
      await _backgroundBudget(t);
      client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
      t.onCancel = () => client?.close(force: true);
      final uri = await adapter.mediaUrl(track);
      final req = await client.getUrl(uri);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      (await adapter.mediaHeaders()).forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close().timeout(const Duration(seconds: 25));
      if (resp.statusCode != 200) {
        throw HttpException('整曲缓存需要 HTTP 200，收到 ${resp.statusCode}');
      }
      final expected = resp.contentLength;
      final encoding = resp.headers.value(HttpHeaders.contentEncodingHeader);
      if (encoding != null && encoding != 'identity') {
        throw StateError('服务器未返回原始音频表示');
      }
      if (expected > maxBytes) throw StateError('单曲大小超过缓存容量上限');
      if (expected <= 0) throw StateError('服务器未提供完整音频长度，不能确认整曲缓存');
      await _spaceGuard(expected);
      sink = tmp.openWrite();
      var read = 0;
      await for (final part in resp.timeout(const Duration(seconds: 25))) {
        if (t.cancelled) throw StateError('缓存任务已取消');
        await _backgroundBudget(t, bytes: part.length);
        sink.add(part);
        read += part.length;
        if (read > maxBytes) throw StateError('音频超过缓存预算');
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (read == 0 || (expected >= 0 && read != expected)) {
        throw StateError('整曲长度不匹配，已拒绝提交');
      }
      if (t.cancelled) throw StateError('缓存任务已取消');
      await _commit(
        track.ref,
        tmp,
        read,
        resp.headers.value('etag') ?? '',
        t,
        track.resourceVersion,
      );
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      client?.close(force: true);
      adapter.close();
      _active.remove(track.ref.key);
      await OpenListLite.releaseTask(profile.url, openListLease);
    }
  }

  // P2 is transient and capped: never stored in the READY library.
  Future<void> prefetchNext(
    Track track,
    SourceProfile profile, {
    int bytesLimit = 2 * 1024 * 1024,
    String? planId,
  }) async {
    if (!profile.enabled || profile.kind == SourceKind.local) return;
    if (playbackBuffering || !_previewAttempts.add(planId ?? track.ref.key)) {
      return;
    }
    bytesLimit = bytesLimit.clamp(1, 2 * 1024 * 1024);
    final generation = ++_previewGeneration;
    _prefetchClient?.close(force: true);
    _prefetchClient = null;
    _prefetchSourceId = profile.id;
    if (await contains(track.ref) || _previews.containsKey(track.ref.key)) {
      return;
    }
    final current = await store.source(profile.id);
    if (generation != _previewGeneration ||
        current == null ||
        !current.enabled ||
        current.url != profile.url ||
        current.username != profile.username) {
      return;
    }
    final adapter = factory.create(profile);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    _prefetchClient = client;
    final openListLease = 'prefetch:${const Uuid().v4()}';
    try {
      await OpenListLite.acquireTask(profile.url, openListLease);
      final req = await client
          .getUrl(await adapter.mediaUrl(track))
          .timeout(const Duration(seconds: 15));
      req.followRedirects = false;
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-${bytesLimit - 1}');
      (await adapter.mediaHeaders()).forEach((k, v) => req.headers.set(k, v));
      final r = await req.close().timeout(const Duration(seconds: 15));
      final encoding = r.headers.value(HttpHeaders.contentEncodingHeader);
      if (encoding != null && encoding != 'identity') return;
      if (r.statusCode != 206) return;
      final range = r.headers.value('content-range') ?? '';
      final match = RegExp(r'^bytes 0-(\d+)/(\d+)$').firstMatch(range);
      final etag = r.headers.value('etag') ?? '';
      // Strong validators prevent combining bytes from different resources.
      if (match == null || etag.isEmpty || etag.startsWith('W/')) return;
      final expected = int.parse(match.group(1)!) + 1;
      final total = int.parse(match.group(2)!);
      if (expected > bytesLimit || total < expected) return;
      final out = BytesBuilder(copy: false);
      await for (final chunk in r.timeout(const Duration(seconds: 15))) {
        if (out.length + chunk.length > bytesLimit) {
          out.add(chunk.sublist(0, bytesLimit - out.length));
          break;
        }
        out.add(chunk);
      }
      if (out.length != expected || generation != _previewGeneration) return;
      _previews.clear();
      _previews[track.ref.key] = AudioPreview(
        out.takeBytes(),
        total,
        etag,
        r.headers.contentType,
      );
    } catch (_) {
    } finally {
      client.close(force: true);
      if (identical(_prefetchClient, client)) _prefetchClient = null;
      adapter.close();
      await OpenListLite.releaseTask(profile.url, openListLease);
    }
  }

  void invalidatePreview() {
    _prefetchSourceId = null;
    _previewGeneration++;
    _prefetchClient?.close(force: true);
    _prefetchClient = null;
    _previews.clear();
  }

  void beginQueueSession() {
    invalidatePreview();
    _previewAttempts.clear();
  }

  void cancelAll({bool permanent = false}) {
    if (permanent) _stopped = true;
    invalidatePreview();
    for (final token in _active.values) {
      token.cancel();
    }
    for (final token in _downloadTokens.values) {
      token.cancel();
    }
  }

  Future<void> shutdown() async {
    cancelAll(permanent: true);
    await Future.wait(
      _downloads.values.map((future) => future.catchError((Object _) {})),
    );
    await _commits.synchronized(() async {});
    await Future.wait(_cleanup.toList());
  }
}
