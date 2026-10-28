import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../core/models.dart';
import 'embedded_tags.dart';
import 'sources.dart';
import 'cache.dart';
import 'local_library.dart';

// Keep the isolate closure outside the network method's captured context.
Future<EmbeddedTags> _parseTags(
  Uint8List bytes,
  EmbeddedTags Function(Uint8List) parse,
) => Isolate.run(() => parse(bytes));

/// Bounded range reads for visible/playing WebDAV tracks. This service never
/// writes partial audio into CacheManager or marks it READY.
class WebDavTags {
  WebDavTags(this.factory, {this.cache, this.onTags});
  final AdapterFactory factory;
  final CacheManager? cache;

  /// Invoked after a successful read (including an already-cached audio file).
  /// A database failure must never prevent artwork or lyrics from loading.
  final Future<void> Function(Track track, EmbeddedTags tags)? onTags;
  final Map<String, Future<EmbeddedTags>> _pending = {};
  final Map<String, ({EmbeddedTags tags, DateTime until})> _recent = {};
  final Map<HttpClient, String> _clients = {};
  final Map<String, int> _epochs = {};
  final List<Completer<void>> _waiting = [];
  int _readers = 0;
  bool _stopped = false;
  static const maxBytes = 12 * 1024 * 1024;

  Future<EmbeddedTags> load(
    SourceProfile source,
    Track track, {
    bool force = false,
  }) {
    if (_stopped || !source.enabled || source.kind != SourceKind.webdav) {
      return Future.value(const EmbeddedTags());
    }
    final epoch = _epochs[source.id] ?? 0;
    final key = jsonEncode([
      source.id,
      source.url,
      source.username,
      track.ref.id,
      track.resourceVersion,
      epoch,
    ]);
    if (!force) {
      final recent = _recent[key];
      if (recent != null && recent.until.isAfter(DateTime.now())) {
        return Future.value(recent.tags);
      }
    }
    return _pending.putIfAbsent(key, () async {
      try {
        final tags = await _load(source, track, epoch);
        if (tags.hasMusicMetadata &&
            !_stopped &&
            epoch == (_epochs[source.id] ?? 0)) {
          try {
            await onTags?.call(track, tags);
          } catch (_) {
            // Metadata persistence must not hide cover/lyrics results.
          }
        }
        if (!_stopped && epoch == (_epochs[source.id] ?? 0)) {
          // At most two covers retained between the independent artwork and
          // lyric consumers. Persistent bytes live in MediaAssetStore.
          _recent.remove(key);
          _recent[key] = (
            tags: tags,
            until: DateTime.now().add(const Duration(seconds: 30)),
          );
          while (_recent.length > 2) {
            _recent.remove(_recent.keys.first);
          }
        }
        return tags;
      } catch (_) {
        return const EmbeddedTags(); // Sidecars/complete local audio remain usable.
      } finally {
        _pending.remove(key);
      }
    });
  }

  Future<EmbeddedTags> _load(
    SourceProfile source,
    Track track,
    int epoch,
  ) async {
    if (_readers >= 3) {
      final gate = Completer<void>();
      _waiting.add(gate);
      await gate.future;
    } else {
      _readers++;
    }
    HttpClient? client;
    MusicAdapter? adapter;
    try {
      if (_stopped || epoch != (_epochs[source.id] ?? 0)) {
        return const EmbeddedTags();
      }
      final audioCache = cache;
      if (audioCache != null) {
        audioCache.lease(track.ref);
        try {
          final ready = await audioCache.find(track.ref);
          if (ready != null) {
            final embedded = await LocalLibrary.embeddedAssets(ready.file);
            if (_stopped || epoch != (_epochs[source.id] ?? 0)) {
              return const EmbeddedTags();
            }
            if (embedded.cover != null ||
                embedded.lyrics?.isNotEmpty == true ||
                embedded.hasMusicMetadata) {
              return embedded;
            }
          }
        } finally {
          audioCache.release(track.ref);
        }
      }
      adapter = factory.create(source);
      final uri = await adapter.mediaUrl(track);
      final headers = await adapter.mediaHeaders();
      client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
      _clients[client] = source.id;
      var budget = maxBytes, requests = 0;
      int? total;
      String? etag, modified;
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      Future<Uint8List> read(int start, int length) async {
        if (_stopped ||
            epoch != (_epochs[source.id] ?? 0) ||
            ++requests > 64 ||
            length <= 0 ||
            length > budget ||
            DateTime.now().isAfter(deadline)) {
          throw StateError('标签读取已停止');
        }
        budget -= length;
        final request = await client!
            .getUrl(uri)
            .timeout(const Duration(seconds: 12));
        request.followRedirects = false;
        headers.forEach(request.headers.set);
        request.headers.set('Accept-Encoding', 'identity');
        request.headers.set('Range', 'bytes=$start-${start + length - 1}');
        final expected = etag ?? track.remote['etag']?.toString();
        final expectedDate =
            modified ?? track.remote['DateModified']?.toString();
        if (expected != null &&
            expected.isNotEmpty &&
            !expected.startsWith('W/')) {
          request.headers.set('If-Match', expected);
        } else if (expectedDate?.isNotEmpty == true) {
          request.headers.set('If-Unmodified-Since', expectedDate!);
        }
        final response = await request.close().timeout(
          const Duration(seconds: 12),
        );
        // Reject ignored ranges before consuming a potentially huge audio body.
        final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
            .firstMatch(response.headers.value('content-range') ?? '');
        if (response.statusCode != 206 ||
            range == null ||
            int.parse(range[1]!) != start ||
            int.parse(range[2]!) != start + length - 1 ||
            (response.contentLength >= 0 && response.contentLength != length)) {
          throw StateError('服务器未返回完整标签范围');
        }
        final size = int.parse(range[3]!);
        final responseEtag = response.headers.value('etag');
        final responseDate = response.headers.value('last-modified');
        final indexedSize = track.remote['size'];
        if (size < start + length ||
            (total != null && total != size) ||
            (indexedSize is int && indexedSize > 0 && indexedSize != size) ||
            (expected?.isNotEmpty == true &&
                responseEtag != null &&
                responseEtag != expected) ||
            (expectedDate?.isNotEmpty == true &&
                responseDate != null &&
                responseDate != expectedDate)) {
          throw StateError('音频已变化，请重新同步');
        }
        total = size;
        etag ??= responseEtag;
        modified ??= responseDate;
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.timeout(
          const Duration(seconds: 15),
        )) {
          if (bytes.length + chunk.length > length) throw StateError('标签响应超长');
          bytes.add(chunk);
        }
        if (bytes.length != length) throw StateError('标签响应截断');
        return bytes.takeBytes();
      }

      final header = await read(0, 10);
      Uint8List bytes;
      EmbeddedTags Function(Uint8List) parse;
      if (ascii.decode(header.sublist(0, 3), allowInvalid: true) == 'ID3') {
        final size = tagUint(header, 6, 4, syncSafe: true);
        if (size == 0) return const EmbeddedTags();
        bytes = Uint8List.fromList([...header, ...await read(10, size)]);
        parse = parseId3Tags;
      } else if (ascii.decode(header.sublist(0, 4), allowInvalid: true) ==
          'fLaC') {
        var p = 4, end = 4;
        for (var i = 0; i < 60; i++) {
          final block = await read(p, 4);
          end = p + 4 + tagUint(block, 1, 3);
          if (end > maxBytes || end > total!) throw StateError('FLAC 标签过大');
          if (block[0] & 128 != 0) break;
          p = end;
          if (i == 59) throw StateError('FLAC 标签过多');
        }
        bytes = await read(0, end);
        parse = parseFlacTags;
      } else if (ascii.decode(header.sublist(4, 8), allowInvalid: true) ==
          'ftyp') {
        var p = 0;
        Uint8List? moov;
        for (var i = 0; i < 60 && p + 8 <= total!; i++) {
          final box = await read(p, 8);
          var size = tagUint(box, 0, 4), head = 8;
          if (size == 1) {
            size = tagUint(await read(p + 8, 8), 0, 8);
            head = 16;
          }
          if (size == 0) size = total! - p;
          if (size < head || p + size > total!) throw StateError('无效 MP4 标签');
          if (latin1.decode(box.sublist(4)) == 'moov') {
            moov = await read(p, size);
            break;
          }
          p +=
              size; // Skip mdat without fetching audio, even when moov is last.
        }
        if (moov == null) return const EmbeddedTags();
        bytes = moov;
        parse = parseMp4Tags;
      } else {
        return const EmbeddedTags();
      }
      final tags = await _parseTags(bytes, parse);
      if (_stopped || epoch != (_epochs[source.id] ?? 0)) {
        return const EmbeddedTags();
      }
      return EmbeddedTags(
        cover: (tags.cover?.length ?? 0) <= 8 * 1024 * 1024 ? tags.cover : null,
        lyrics: utf8.encode(tags.lyrics ?? '').length <= 1024 * 1024
            ? tags.lyrics
            : null,
        title: tags.title,
        artist: tags.artist,
        album: tags.album,
        albumArtist: tags.albumArtist,
        year: tags.year,
        trackNumber: tags.trackNumber,
        discNumber: tags.discNumber,
      );
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
    _epochs[id] = (_epochs[id] ?? 0) + 1;
    _recent.clear();
    for (final entry in _clients.entries.toList()) {
      if (entry.value == id) entry.key.close(force: true);
    }
  }

  Future<void> shutdown() async {
    _stopped = true;
    _recent.clear();
    for (final client in _clients.keys.toList()) {
      client.close(force: true);
    }
    await Future.wait(_pending.values.toList());
  }
}
