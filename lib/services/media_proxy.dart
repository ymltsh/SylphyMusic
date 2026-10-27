import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../core/models.dart';
import '../data/app_db.dart';
import 'cache.dart';
import 'sources.dart';
import 'byte_range.dart';

class MediaProxy {
  MediaProxy(this.db, this.cache, this.factory);
  final AppDb db;
  final CacheManager cache;
  final AdapterFactory factory;
  HttpServer? _server;
  final Set<Future<void>> _handlers = {};
  final Map<HttpClient, String> _clients = {};
  final Map<String, int> _epochs = {};
  void revokeSource(String id) {
    _epochs[id] = (_epochs[id] ?? 0) + 1;
    _tickets.removeWhere((_, ticket) => ticket.profile.id == id);
    for (final entry in _clients.entries.toList()) {
      if (entry.value == id) entry.key.close(force: true);
    }
  }

  final Map<String, String> _failures = {};
  String? failureFor(TrackRef ref) => _failures[ref.key];
  final Map<String, ({Track track, SourceProfile profile, DateTime expires})>
  _tickets = {};
  int get port => _server?.port ?? 0;
  Future<void> start() async {
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    _server!.listen((req) {
      final handler = _handle(req);
      _handlers.add(handler);
      unawaited(handler.whenComplete(() => _handlers.remove(handler)));
    });
  }

  Uri ticket(Track track, SourceProfile profile) {
    _failures.remove(track.ref.key);
    if (_server == null) throw StateError('媒体代理未启动');
    _tickets.removeWhere((_, value) => value.expires.isBefore(DateTime.now()));
    final id = '${const Uuid().v4()}-${const Uuid().v4()}';
    _tickets[id] = (
      track: track,
      profile: profile,
      expires: DateTime.now().add(const Duration(hours: 2)),
    );
    return Uri.parse('http://127.0.0.1:$port/audio/$id');
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      if (req.method != 'GET' && req.method != 'HEAD') {
        req.response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final parts = req.uri.pathSegments;
      if (parts.length != 2 || parts[0] != 'audio') {
        req.response.statusCode = HttpStatus.notFound;
        return;
      }
      final ticket = _tickets[parts[1]];
      if (ticket == null || ticket.expires.isBefore(DateTime.now())) {
        req.response.statusCode = HttpStatus.forbidden;
        return;
      }
      final ref = ticket.track.ref;
      final epoch = _epochs[ref.sourceId] ?? 0;
      final source = await db.source(ref.sourceId);
      if (source == null ||
          !source.enabled ||
          source.url != ticket.profile.url ||
          source.username != ticket.profile.username) {
        req.response.statusCode = HttpStatus.forbidden;
        return;
      }
      final range = req.headers.value(HttpHeaders.rangeHeader);
      final cached = await cache.find(ref, touch: true);
      if (epoch != (_epochs[ref.sourceId] ?? 0)) {
        req.response.statusCode = HttpStatus.forbidden;
        return;
      }
      if (cached != null) {
        await _fileResponse(req, ref, cached.file, cached.bytes, range);
        return;
      }
      await _remoteResponse(req, ticket.track, ticket.profile, range);
    } catch (e) {
      final parts = req.uri.pathSegments;
      final track = parts.length == 2 ? _tickets[parts[1]]?.track : null;
      if (track != null) {
        _failures[track.ref.key] = e is HandshakeException ? 'tls' : 'network';
      }
      try {
        req.response.statusCode = HttpStatus.badGateway;
        req.response.write('上游音频读取失败');
      } catch (_) {}
    } finally {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _fileResponse(
    HttpRequest req,
    TrackRef ref,
    File file,
    int length,
    String? range,
  ) async {
    final selected = ByteRange.parse(range, length);
    if (selected == null) {
      req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      req.response.headers.set('Content-Range', 'bytes */$length');
      return;
    }
    final offset = selected.start, end = selected.end;
    req.response.headers.set('Accept-Ranges', 'bytes');
    req.response.headers.contentType = ContentType.binary;
    req.response.contentLength = end - offset + 1;
    if (range != null) {
      req.response.statusCode = HttpStatus.partialContent;
      req.response.headers.set('Content-Range', 'bytes $offset-$end/$length');
    }
    if (req.method == 'HEAD') return;
    cache.lease(ref);
    try {
      await req.response.addStream(file.openRead(offset, end + 1));
    } finally {
      cache.release(ref);
    }
  }

  Future<void> _remoteResponse(
    HttpRequest req,
    Track track,
    SourceProfile profile,
    String? range,
  ) async {
    final adapter = factory.create(profile);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    _clients[client] = profile.id;
    if (range != null && !RegExp(r'^bytes=(\d*)-(\d*)$').hasMatch(range)) {
      req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      adapter.close();
      client.close(force: true);
      _clients.remove(client);
      return;
    }
    try {
      final uri = await adapter.mediaUrl(track);
      final preview = cache.preview(track.ref);
      final selected = preview == null
          ? null
          : ByteRange.parse(range, preview.total);
      final reusable =
          preview != null &&
          selected != null &&
          selected.start < preview.bytes.length;
      if (reusable && selected.end < preview.bytes.length) {
        req.response.statusCode = range == null ? 200 : 206;
        req.response.contentLength = selected.length;
        req.response.headers.set('Accept-Ranges', 'bytes');
        req.response.headers.set('ETag', preview.etag);
        req.response.headers.contentType = preview.contentType;
        if (range != null) {
          req.response.headers.set(
            'Content-Range',
            'bytes ${selected.start}-${selected.end}/${preview.total}',
          );
        }
        if (req.method != 'HEAD') {
          req.response.add(
            preview.bytes.sublist(selected.start, selected.end + 1),
          );
        }
        return;
      }
      final outgoing = await client.openUrl(req.method, uri);
      outgoing.followRedirects = false;
      (await adapter.mediaHeaders()).forEach(
        (k, v) => outgoing.headers.set(k, v),
      );
      outgoing.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (reusable) {
        outgoing.headers.set(
          HttpHeaders.rangeHeader,
          'bytes=${preview.bytes.length}-${selected.end}',
        );
        outgoing.headers.set(HttpHeaders.ifRangeHeader, preview.etag);
      } else if (range != null) {
        outgoing.headers.set(HttpHeaders.rangeHeader, range);
      }
      final upstream = await outgoing.close().timeout(
        const Duration(seconds: 25),
      );
      if (upstream.statusCode != 200 && upstream.statusCode != 206) {
        _failures[track.ref.key] = '${upstream.statusCode}';
        req.response.statusCode = upstream.statusCode;
        return;
      }
      final encoding = upstream.headers.value(
        HttpHeaders.contentEncodingHeader,
      );
      if (encoding != null && encoding != 'identity') {
        req.response.statusCode = HttpStatus.badGateway;
        return;
      }
      if (reusable &&
          (upstream.statusCode != 206 ||
              upstream.headers.value('etag') != preview.etag ||
              upstream.headers.value('content-range') !=
                  'bytes ${preview.bytes.length}-${selected.end}/${preview.total}')) {
        cache.invalidatePreview();
        await upstream.drain<void>();
        await _remoteResponse(req, track, profile, range);
        return;
      }
      if (!reusable && range != null && upstream.statusCode != 206) {
        req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        return;
      }
      final cr = upstream.headers.value('content-range');
      final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(cr ?? '');
      if (!reusable && upstream.statusCode == 206) {
        final expected = match == null
            ? null
            : ByteRange.parse(range, int.parse(match.group(3)!));
        if (expected == null ||
            expected.start != int.parse(match!.group(1)!) ||
            expected.end != int.parse(match.group(2)!)) {
          req.response.statusCode = HttpStatus.badGateway;
          return;
        }
      }
      req.response.statusCode = reusable
          ? (range == null ? 200 : 206)
          : upstream.statusCode;
      req.response.headers.set(
        'Accept-Ranges',
        upstream.headers.value('accept-ranges') ?? 'bytes',
      );
      req.response.headers.contentType =
          upstream.headers.contentType ?? ContentType('audio', 'mpeg');
      if (reusable) {
        req.response.contentLength = selected.length;
        if (range != null) {
          req.response.headers.set(
            'Content-Range',
            'bytes ${selected.start}-${selected.end}/${preview.total}',
          );
        }
      } else if (cr != null) {
        req.response.headers.set('Content-Range', cr);
      }
      if (!reusable && upstream.contentLength >= 0) {
        req.response.contentLength = upstream.contentLength;
      }
      if (req.method == 'HEAD') return;
      Stream<List<int>> combined() async* {
        if (reusable) yield preview.bytes.sublist(selected.start);
        yield* upstream.timeout(const Duration(seconds: 25));
      }

      final full = reusable
          ? selected.start == 0 && selected.end == preview.total - 1
          : upstream.statusCode == 200 ||
                (match != null &&
                    match.group(1) == '0' &&
                    int.parse(match.group(2)!) + 1 ==
                        int.parse(match.group(3)!));
      if (full) {
        await cache.captureRelay(
          track.ref,
          combined(),
          (bytes) async {
            req.response.add(bytes);
            await req.response.flush();
          },
          expected: reusable ? selected.length : upstream.contentLength,
          full: full,
          tag: upstream.headers.value('etag') ?? '',
          onCancel: () => client.close(force: true),
          metadataVersion: track.resourceVersion,
        );
      } else {
        await req.response.addStream(combined());
      }
    } finally {
      client.close(force: true);
      _clients.remove(client);
      adapter.close();
    }
  }

  Future<void> dispose() async {
    cache.cancelAll(permanent: true);
    for (final client in _clients.keys) {
      client.close(force: true);
    }
    _failures.clear();
    _tickets.clear();
    await _server?.close(force: true);
    await Future.wait(_handlers.toList());
    _server = null;
  }
}
