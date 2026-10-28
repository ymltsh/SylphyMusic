import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../data/app_db.dart';
import 'cache.dart';
import 'lyrics.dart';
import 'media_assets.dart';
import 'sources.dart';
import 'webdav_tags.dart';

class LyricsStore {
  LyricsStore(
    this.db,
    this.factory,
    this.assets,
    this.cache,
    this.root, {
    WebDavTags? tags,
  }) : tags = tags ?? WebDavTags(factory, cache: cache),
       _ownsTags = tags == null;
  final WebDavTags tags;
  final bool _ownsTags;
  final AppDb db;
  final AdapterFactory factory;
  final MediaAssetStore assets;
  final CacheManager cache;
  final Directory root;
  final Map<MusicAdapter, String> _adapters = {};
  final Set<Future<String?>> _loads = {};
  final Map<String, int> _epochs = {};
  bool _stopped = false;
  String key(Track track) => 'lyrics-v3:${track.ref.key}';
  String manualKey(Track track) => 'lyrics-manual:${track.ref.key}';
  int revision(Track track) =>
      assets.revision(track.ref.sourceId, key(track)) +
      assets.revision(track.ref.sourceId, manualKey(track));
  File _legacy(Track track, [String suffix = '']) => File(
    p.join(
      root.path,
      'lyrics',
      sha256.convert(utf8.encode(track.ref.sourceId)).toString(),
      '${sha256.convert(utf8.encode(track.ref.key))}$suffix.lrc',
    ),
  );

  Future<String?> load(Track track, {bool forceRefresh = false}) {
    if (_stopped) return Future.value(null);
    final future = _load(track, forceRefresh);
    _loads.add(future);
    unawaited(
      future.then<void>(
        (_) => _loads.remove(future),
        onError: (Object _, StackTrace _) => _loads.remove(future),
      ),
    );
    return future;
  }

  Future<String?> _load(Track track, bool force) async {
    final epoch = _epochs[track.ref.sourceId] ?? 0;
    final source = await db.source(track.ref.sourceId);
    if (source == null || !source.enabled || _stopped) return null;
    var manual = await assets.read(source.id, manualKey(track));
    final oldManual = _legacy(track, '.manual');
    if (manual == null && await oldManual.exists()) {
      manual = await assets.put(
        source.id,
        manualKey(track),
        'lyrics',
        'manual-v1',
        await oldManual.readAsBytes(),
        pinned: true,
      );
      if (manual != null) await oldManual.delete();
    }
    if (manual != null) return manual.file.readAsString();
    if (source.kind == SourceKind.local) {
      final lrc = File(
        p.setExtension(
          track.remote['path']?.toString() ?? track.ref.id,
          '.lrc',
        ),
      );
      return await lrc.exists()
          ? lrc.readAsString()
          : track.remote['lyrics']?.toString();
    }
    // Old remote files are imported lazily. Plain Emby text is deliberately
    // stale once, so a timed upgrade runs in the background without hiding it.
    if (await assets.read(source.id, key(track)) == null &&
        !await assets.migratedLegacy(source.id, key(track))) {
      for (final suffix in ['.emby-timed-v2', '']) {
        final old = _legacy(track, suffix);
        if (!await old.exists()) continue;
        final bytes = await old.readAsBytes();
        if (bytes.isEmpty) continue;
        final text = utf8.decode(bytes);
        final stale = source.kind == SourceKind.emby && parseLrc(text).isEmpty;
        try {
          final adopted = await assets.put(
            source.id,
            key(track),
            'lyrics',
            track.resourceVersion,
            bytes,
            ttl: stale ? Duration.zero : const Duration(hours: 24),
          );
          if (adopted != null) await assets.markLegacy(source.id, key(track));
          // The old unmarked file may have been a manual import in early
          // releases. Preserve it as a recovery copy during timed upgrades.
          break;
        } catch (_) {
          /* keep legacy bytes until a replacement succeeds */
        }
      }
    }
    final asset = await assets.get(
      source,
      key(track),
      'lyrics',
      source.kind == SourceKind.webdav
          ? 'embedded-v1:${track.resourceVersion}'
          : track.resourceVersion,
      (previous) async {
        if (_stopped) return null;
        if (source.kind == SourceKind.webdav) {
          final embedded = await tags.load(source, track, force: force);
          if (embedded.lyrics?.trim().isNotEmpty == true) {
            return AssetPayload(utf8.encode(embedded.lyrics!));
          }
        }
        if (_stopped || epoch != (_epochs[source.id] ?? 0)) return null;
        final adapter = factory.create(source);
        _adapters[adapter] = source.id;
        try {
          final text = await adapter.lyrics(track);
          return text?.trim().isNotEmpty == true
              ? AssetPayload(utf8.encode(text!))
              : null;
        } finally {
          adapter.close();
          _adapters.remove(adapter);
        }
      },
      forceRefresh: force,
      ttl: const Duration(hours: 6),
    );
    if (asset == null) return null;
    final text = await asset.file.readAsString();
    // Also normalize already-cached Emby SRT responses from older builds.
    return source.kind == SourceKind.emby
        ? normalizeSubtitleLyrics(text)
        : text;
  }

  Future<void> importFile(Track track, File file) async {
    if (await file.length() > 1024 * 1024) throw StateError('歌词文件不能超过 1 MiB');
    final text = await file.readAsString();
    final imported = await assets.put(
      track.ref.sourceId,
      manualKey(track),
      'lyrics',
      'manual-v1',
      utf8.encode(text),
      pinned: true,
    );
    if (imported == null) throw StateError('来源不可用，未修改手动歌词');
  }

  void suspendSource(String id) {
    tags.suspendSource(id);
    _epochs[id] = (_epochs[id] ?? 0) + 1;
    for (final entry in _adapters.entries.toList()) {
      if (entry.value == id) entry.key.close();
    }
  }

  Future<void> clearSource(String id) async {
    suspendSource(id);
    final legacy = Directory(
      p.join(root.path, 'lyrics', sha256.convert(utf8.encode(id)).toString()),
    );
    if (await legacy.exists()) await legacy.delete(recursive: true);
  }

  Future<void> shutdown() async {
    _stopped = true;
    if (_ownsTags) await tags.shutdown();
    for (final adapter in _adapters.keys.toList()) {
      adapter.close();
    }
    await Future.wait(
      _loads
          .map(
            (f) => f.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
          )
          .toList(),
    );
  }
}
