import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:disk_space_2/disk_space_2.dart';

import '../core/models.dart';
import '../data/app_db.dart';
import 'sources.dart';

class ArtworkStore {
  ArtworkStore(this.db, this.factory, this.root);
  final AppDb db;
  final AdapterFactory factory;
  final Directory root;
  final Map<String, Future<File?>> _pending = {};
  final Set<Future<File?>> _loads = {};
  final Map<HttpClient, String> _clients = {};
  final Map<String, int> _epochs = {};
  final Map<String, int> _purges = {};
  bool _stopped = false;
  String _hash(String value) => sha256.convert(utf8.encode(value)).toString();
  Future<File?> load(Track track) {
    if (_stopped) return Future.value(null);
    return _pending.putIfAbsent(track.ref.key, () {
      final future = _load(track).catchError((Object _) => null);
      _loads.add(future);
      unawaited(future.whenComplete(() => _loads.remove(future)));
      return future;
    });
  }

  Future<File?> _load(Track track) async {
    final epoch = _epochs[track.ref.sourceId] ?? 0;
    final purge = _purges[track.ref.sourceId] ?? 0;
    final source = await db.source(track.ref.sourceId);
    if (source == null || !source.enabled) return null;
    if (epoch != (_epochs[source.id] ?? 0)) return null;
    if (source.kind == SourceKind.local) {
      final value = track.remote['coverPath']?.toString();
      return value == null ? null : File(value);
    }
    final file = File(
      p.join(
        root.path,
        'covers',
        _hash(source.id),
        '${_hash('${track.coverId.isEmpty ? track.ref.id : track.coverId}/${track.remote['AlbumPrimaryImageTag'] ?? track.remote['DateModified'] ?? ''}')}.image',
      ),
    );
    if (await file.exists()) {
      await file.setLastModified(DateTime.now());
      return file;
    }
    if (epoch != (_epochs[source.id] ?? 0)) return null;
    final adapter = factory.create(source);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    _clients[client] = source.id;
    try {
      final url = await adapter.coverUrl(track);
      if (url == null) return null;
      final free = await DiskSpace.getFreeDiskSpaceForPath(root.path);
      final total = await DiskSpace.getTotalDiskSpace;
      if (free == null || total == null) return null;
      final reserve = (Platform.isAndroid ? total * .05 : total * .02).clamp(
        Platform.isAndroid ? 1024.0 : 2048.0,
        Platform.isAndroid ? 4096.0 : 10240.0,
      );
      if (free < reserve + 8) return null;
      final request = await client.getUrl(url);
      request.followRedirects = false;
      (await adapter.mediaHeaders()).forEach(
        (k, v) => request.headers.set(k, v),
      );
      final response = await request.close();
      if (response.statusCode != 200 ||
          response.contentLength > 8 * 1024 * 1024) {
        return null;
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        if (bytes.length + chunk.length > 8 * 1024 * 1024) return null;
        bytes.addAll(chunk);
      }
      final current = await db.source(source.id);
      if (_stopped ||
          epoch != (_epochs[source.id] ?? 0) ||
          bytes.isEmpty ||
          current == null ||
          !current.enabled ||
          current.url != source.url) {
        return null;
      }
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
      if (_stopped || epoch != (_epochs[source.id] ?? 0)) {
        // A stop keeps completed artwork; explicit removal alone purges a
        // response that raced with the deletion of its source directory.
        if (purge != (_purges[source.id] ?? 0) && await file.exists()) {
          await file.delete();
        }
        return null;
      }
      await _trim(file);
      return file;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
      _clients.remove(client);
      adapter.close();
    }
  }

  Future<void> clearSource(String id) async {
    _purges[id] = (_purges[id] ?? 0) + 1;
    suspendSource(id);
    final directory = Directory(p.join(root.path, 'covers', _hash(id)));
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  void suspendSource(String id) {
    _epochs[id] = (_epochs[id] ?? 0) + 1;
    for (final entry in _clients.entries.toList()) {
      if (entry.value == id) entry.key.close(force: true);
    }
    _pending.removeWhere((key, _) => TrackRef.parse(key).sourceId == id);
  }

  void invalidate() => _pending.clear();

  Future<void> shutdown() async {
    _stopped = true;
    for (final client in _clients.keys.toList()) {
      client.close(force: true);
    }
    await Future.wait(_loads.toList());
  }

  Future<void> _trim(File keep) async {
    final directory = Directory(p.join(root.path, 'covers'));
    final records = <({File file, int bytes, DateTime used})>[];
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        final stat = await entity.stat();
        records.add((file: entity, bytes: stat.size, used: stat.modified));
      }
    }
    var total = records.fold<int>(0, (sum, row) => sum + row.bytes);
    records.sort((a, b) => a.used.compareTo(b.used));
    for (final record in records) {
      if (total <= 200 * 1024 * 1024) break;
      if (record.file.path == keep.path) continue;
      try {
        await record.file.delete();
        total -= record.bytes;
      } catch (_) {}
    }
    if (records.length > 500) _pending.clear();
  }
}
