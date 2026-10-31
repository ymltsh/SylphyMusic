import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../data/app_db.dart';
import 'media_assets.dart';
import 'sources.dart';
import 'webdav_tags.dart';

class ArtworkStore {
  ArtworkStore(
    this.db,
    this.factory,
    this.root, {
    MediaAssetStore? assets,
    WebDavTags? tags,
  }) : assets = assets ?? MediaAssetStore(db, root),
       _ownsAssets = assets == null,
       tags = tags ?? WebDavTags(factory),
       _ownsTags = tags == null;
  final AppDb db;
  final AdapterFactory factory;
  final Directory root;
  final MediaAssetStore assets;
  final bool _ownsAssets;
  final WebDavTags tags;
  final bool _ownsTags;
  final Map<HttpClient, String> _clients = {};
  final List<Completer<void>> _waiting = [];
  final Set<Future<File?>> _loads = {};
  final Map<String, int> _epochs = {};
  int _readers = 0;
  bool _stopped = false;
  String key(Track track) => jsonEncode([
    'cover',
    track.remote.containsKey('format') ? track.ref.key : track.artworkIdentity,
    'Primary',
    800,
    90,
    track.remote.containsKey('format') ? 2 : 1,
  ]);
  int revision(Track track) => assets.revision(track.ref.sourceId, key(track));
  void retain(Track track) => assets.retain(track.ref.sourceId, key(track));
  void release(Track track) => assets.release(track.ref.sourceId, key(track));
  Future<File?> load(Track track, {bool forceRefresh = false}) {
    if (_stopped) return Future.value(null);
    final future = _load(track, forceRefresh).catchError((Object _) => null);
    _loads.add(future);
    unawaited(future.whenComplete(() => _loads.remove(future)));
    return future;
  }

  String _hash(String value) => sha256.convert(utf8.encode(value)).toString();
  Future<File?> _load(Track track, bool force) async {
    final epoch = _epochs[track.ref.sourceId] ?? 0;
    final source = await db.source(track.ref.sourceId);
    if (source == null || !source.enabled || _stopped) return null;
    if (source.kind == SourceKind.local) {
      final path = track.remote['coverPath']?.toString();
      return path != null && await File(path).exists() ? File(path) : null;
    }
    // Lazily adopt pre-manifest artwork without requiring the server online.
    final oldVersion = jsonEncode([
      track.coverId,
      (track.remote['ImageTags'] as Map?)?['Primary'],
      track.remote['AlbumId'],
      track.remote['AlbumPrimaryImageTag'],
      track.remote['ParentPrimaryImageItemId'],
      track.remote['ParentPrimaryImageTag'],
      track.remote['DateModified'],
      track.remote['coverPath'],
    ]);
    final legacy = File(
      p.join(
        root.path,
        'covers',
        _hash(source.id),
        '${_hash('${track.ref.key}/$oldVersion')}.image',
      ),
    );
    await assets.link(track.ref, key(track), 'cover');
    final asset = await assets.get(
      source,
      key(track),
      'cover',
      track.artworkVersion,
      (previous) async {
        if (source.kind == SourceKind.webdav) {
          final embedded = await tags.load(source, track, force: force);
          if (embedded.cover != null) {
            try {
              await assets.validate('cover', embedded.cover!);
              return AssetPayload(embedded.cover!);
            } catch (_) {
              /* An invalid embedded picture must not hide a sidecar. */
            }
          }
        }
        if (_stopped || epoch != (_epochs[source.id] ?? 0)) return null;
        if (previous == null && !force && await legacy.exists()) {
          final bytes = await legacy.readAsBytes();
          // Validation is performed by the shared store; bad legacy files fall
          // through to a remote read instead of becoming permanent failures.
          try {
            await assets.validate('cover', bytes);
            return AssetPayload(bytes);
          } catch (_) {
            /* fetch a clean image */
          }
        }
        return _download(track, source, previous);
      },
      forceRefresh: force,
    );
    if (asset != null && await legacy.exists()) await legacy.delete();
    return asset?.file;
  }

  Future<AssetPayload?> _download(
    Track track,
    SourceProfile source,
    MediaAsset? previous,
  ) async {
    final epoch = _epochs[source.id] ?? 0;
    if (_readers < 6) {
      _readers++;
    } else {
      final slot = Completer<void>();
      _waiting.add(slot);
      await slot.future;
    }
    HttpClient? client;
    MusicAdapter? adapter;
    try {
      if (_stopped || epoch != (_epochs[source.id] ?? 0)) return null;
      adapter = factory.create(source);
      final urls = await adapter.coverUrls(track);
      if (_stopped || epoch != (_epochs[source.id] ?? 0)) return null;
      client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
      _clients[client] = source.id;
      for (final url in urls) {
        final request = await client
            .getUrl(url)
            .timeout(const Duration(seconds: 12));
        request.followRedirects = false;
        (await adapter.mediaHeaders()).forEach(
          (k, v) => request.headers.set(k, v),
        );
        if (previous?.version == track.artworkVersion) {
          if (previous?.etag != null) {
            request.headers.set('If-None-Match', previous!.etag!);
          }
          if (previous?.lastModified != null) {
            request.headers.set('If-Modified-Since', previous!.lastModified!);
          }
        }
        final response = await request.close().timeout(
          const Duration(seconds: 12),
        );
        if (response.statusCode == 404) {
          await response.drain<void>().timeout(const Duration(seconds: 12));
          continue;
        }
        if (response.statusCode == 304 && previous != null) {
          await response.drain<void>();
          return const AssetPayload([], unchanged: true);
        }
        if (response.statusCode != 200) throw StateError('封面读取失败');
        if (response.contentLength > 8 * 1024 * 1024) {
          throw StateError('封面超过 8 MiB');
        }
        final bytes = <int>[];
        await for (final part in response.timeout(
          const Duration(seconds: 20),
        )) {
          if (bytes.length + part.length > 8 * 1024 * 1024) {
            throw StateError('封面超过 8 MiB');
          }
          bytes.addAll(part);
        }
        if (response.contentLength >= 0 &&
            bytes.length != response.contentLength) {
          throw StateError('封面未完整下载');
        }
        if (_stopped || epoch != (_epochs[source.id] ?? 0)) return null;
        return AssetPayload(
          bytes,
          etag: response.headers.value('etag'),
          lastModified: response.headers.value('last-modified'),
        );
      }
      return null;
    } finally {
      if (client != null) {
        client.close(force: true);
        _clients.remove(client);
      }
      adapter?.close();
      if (_waiting.isEmpty) {
        _readers--;
      } else {
        _waiting.removeAt(0).complete();
      }
    }
  }

  void suspendSource(String id) {
    tags.suspendSource(id);
    _epochs[id] = (_epochs[id] ?? 0) + 1;
    assets.suspendSource(id);
    for (final entry in _clients.entries.toList()) {
      if (entry.value == id) entry.key.close(force: true);
    }
  }

  Future<void> clearSource(String id) async {
    suspendSource(id);
    await assets.clear(sourceId: id, includePinned: true);
    final old = Directory(p.join(root.path, 'covers', _hash(id)));
    if (await old.exists()) await old.delete(recursive: true);
  }

  void invalidate() {} // Persistent freshness is driven by the selected image version.
  Future<void> shutdown() async {
    _stopped = true;
    if (_ownsTags) await tags.shutdown();
    for (final client in _clients.keys.toList()) {
      client.close(force: true);
    }
    await Future.wait(_loads.toList());
    if (_ownsAssets) await assets.shutdown();
  }
}
