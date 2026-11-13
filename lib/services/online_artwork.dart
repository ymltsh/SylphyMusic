import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/models.dart';

/// Isolated from music-source adapters: source credentials are NEVER sent to
/// third-party artwork providers.
abstract interface class OnlineArtworkSource {
  Future<List<int>?> fetch(
    Track track, {
    required bool artist,
    bool forceRefresh = false,
  });
  void close();
}

class _ArtworkOperation {
  _ArtworkOperation(this.sourceId);
  final String sourceId;
  final Set<HttpClientRequest> requests = {};
  bool cancelled = false;

  void cancel() {
    cancelled = true;
    for (final request in requests) {
      request.abort();
    }
    requests.clear();
  }
}

/// Metadata-only fallback for artwork that is absent from the configured source.
///
/// Artist: TheAudioDB.
/// Album: TheAudioDB, then MusicBrainz + Cover Art Archive.
/// No account or API key is required for these public endpoints. Requests send
/// artist/album names to these services; no source URL, credentials or audio.
class OnlineArtworkProvider implements OnlineArtworkSource {
  OnlineArtworkProvider({
    Uri? audioDbBase,
    Uri? musicBrainzBase,
    Uri? coverArtBase,
    HttpClient? client,
  }) : _audioDb =
           audioDbBase ??
           Uri.parse('https://www.theaudiodb.com/api/v1/json/123/'),
       _musicBrainz =
           musicBrainzBase ?? Uri.parse('https://musicbrainz.org/ws/2/'),
       _coverArt = coverArtBase ?? Uri.parse('https://coverartarchive.org/'),
       _client =
           client ??
           (HttpClient()..connectionTimeout = const Duration(seconds: 8));

  final Uri _audioDb;
  final Uri _musicBrainz;
  final Uri _coverArt;
  final HttpClient _client;
  final Map<String, Future<List<int>?>> _pending = {};
  final Map<String, DateTime> _misses = {};
  final Map<String, int> _epochs = {};
  final Set<_ArtworkOperation> _operations = {};
  static final _operationZoneKey = Object();
  final List<Completer<void>> _waiters = [];
  int _active = 0;
  Future<void> _musicBrainzTurn = Future<void>.value();
  DateTime? _previousMusicBrainzRequest;
  bool _closed = false;

  static const _maxImageBytes = 8 * 1024 * 1024;
  static const _maxJsonBytes = 1024 * 1024;
  static const _missTtl = Duration(minutes: 30);

  String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  bool _usable(String value) {
    final name = _normalize(value);
    return name.isNotEmpty &&
        !{
          'unknown',
          'unknown artist',
          'unknown album',
          '未知艺术家',
          '未知专辑',
        }.contains(name);
  }

  @override
  Future<List<int>?> fetch(
    Track track, {
    required bool artist,
    bool forceRefresh = false,
  }) {
    final name = artist
        ? track.artist
        : (track.albumArtist.trim().isEmpty ? track.artist : track.albumArtist);
    if (_closed || !_usable(name) || (!artist && !_usable(track.album))) {
      return Future<List<int>?>.value(null);
    }
    final key = jsonEncode([
      track.ref.sourceId,
      _epochs[track.ref.sourceId] ?? 0,
      artist ? 'artist' : 'album',
      _normalize(name),
      if (!artist) _normalize(track.album),
    ]);
    final miss = _misses[key];
    if (!forceRefresh && miss != null && DateTime.now().isBefore(miss)) {
      return Future<List<int>?>.value(null);
    }
    return _pending.putIfAbsent(key, () {
      final operation = _ArtworkOperation(track.ref.sourceId);
      _operations.add(operation);
      final work = runZoned(
        () => _withSlot(() async {
          try {
            final result = artist
                ? await _artistImage(name)
                : await _albumImage(name, track.album);
            if (result == null && !_closed && !operation.cancelled) {
              _misses[key] = DateTime.now().add(_missTtl);
            } else if (result != null) {
              _misses.remove(key);
            }
            return result;
          } catch (_) {
            // Offline, blocked, or rate-limited providers never break playback.
            if (!_closed && !operation.cancelled) {
              _misses[key] = DateTime.now().add(_missTtl);
            }
            return null;
          }
        }),
        zoneValues: {_operationZoneKey: operation},
      ).catchError((Object _) => null);
      unawaited(
        work.whenComplete(() {
          operation.cancel();
          _operations.remove(operation);
          _pending.remove(key);
        }),
      );
      return work;
    });
  }

  Future<T> _withSlot<T>(Future<T> Function() action) async {
    if (_active >= 2) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    } else {
      _active++;
    }
    try {
      _ensureActive();
      return await action();
    } finally {
      if (_waiters.isEmpty) {
        _active--;
      } else {
        _waiters.removeAt(0).complete();
      }
    }
  }

  Future<List<int>?> _artistImage(String name) async {
    final data = await _json(
      _audioDb.resolve('search.php').replace(queryParameters: {'s': name}),
    );
    final items = data?['artists'];
    if (items is! List) return null;
    for (final entry in items.whereType<Map>()) {
      if (_normalize(entry['strArtist']?.toString() ?? '') !=
          _normalize(name)) {
        continue;
      }
      final url = _audioDbImage(entry['strArtistThumb']);
      if (url == null) continue;
      final image = await _image(url, _trustedAudioDbImage);
      if (image != null) return image;
    }
    return null;
  }

  Future<List<int>?> _albumImage(String name, String album) async {
    final data = await _json(
      _audioDb
          .resolve('searchalbum.php')
          .replace(queryParameters: {'s': name, 'a': album}),
    );
    final items = data?['album'];
    if (items is List) {
      for (final entry in items.whereType<Map>()) {
        if (_normalize(entry['strArtist']?.toString() ?? '') !=
                _normalize(name) ||
            _normalize(entry['strAlbum']?.toString() ?? '') !=
                _normalize(album)) {
          continue;
        }
        final url = _audioDbImage(entry['strAlbumThumb']);
        if (url == null) continue;
        final image = await _image(url, _trustedAudioDbImage);
        if (image != null) return image;
      }
    }
    return _musicBrainzAlbum(name, album);
  }

  Future<List<int>?> _musicBrainzAlbum(String name, String album) async {
    // Lucene quotes prevent unintentional fuzzy matching or query injection.
    String quote(String value) =>
        value.replaceAll('\\', '').replaceAll('"', '');
    final query =
        'releasegroup:"${quote(album)}" AND '
        'artistname:"${quote(name)}"';
    await _throttleMusicBrainz();
    final data = await _json(
      _musicBrainz
          .resolve('release-group/')
          .replace(
            queryParameters: {'query': query, 'fmt': 'json', 'limit': '8'},
          ),
    );
    final groups = data?['release-groups'];
    if (groups is! List) return null;
    for (final group in groups.whereType<Map>()) {
      if (_normalize(group['title']?.toString() ?? '') != _normalize(album)) {
        continue;
      }
      final credits = group['artist-credit'];
      if (credits is! List ||
          !credits.whereType<Map>().any((credit) {
            final credited = credit['name']?.toString() ?? '';
            final person = credit['artist'];
            final canonical = person is Map
                ? person['name']?.toString() ?? ''
                : '';
            return _normalize(credited) == _normalize(name) ||
                _normalize(canonical) == _normalize(name);
          })) {
        continue;
      }
      final id = group['id']?.toString() ?? '';
      if (!RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(id)) continue;
      final image = await _image(
        _coverArt.resolve('release-group/$id/front-500'),
        _trustedCoverArtImage,
      );
      if (image != null) return image;
    }
    return null;
  }

  // Serialized across this provider instance, at most one MusicBrainz request
  // per ~1.1 s, including failed responses.
  Future<void> _throttleMusicBrainz() {
    final previous = _musicBrainzTurn;
    final turn = Completer<void>();
    _musicBrainzTurn = turn.future;
    return () async {
      await previous;
      try {
        _ensureActive();
        final last = _previousMusicBrainzRequest;
        if (last != null) {
          final gap =
              const Duration(milliseconds: 1100) -
              DateTime.now().difference(last);
          if (gap > Duration.zero) await Future<void>.delayed(gap);
        }
        _ensureActive();
        _previousMusicBrainzRequest = DateTime.now();
      } finally {
        turn.complete();
      }
    }();
  }

  Uri? _audioDbImage(Object? raw) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    final url = Uri.tryParse(text);
    if (url == null || !_trustedAudioDbImage(_secure(url))) return null;
    return _secure(url);
  }

  bool _isLocal(Uri base) =>
      base.host == '127.0.0.1' ||
      base.host == '::1' ||
      base.host == 'localhost';

  bool _trustedAudioDbImage(Uri url) {
    if (!_safeUrl(url)) return false;
    if (_isLocal(_audioDb)) return url.host == _audioDb.host;
    final host = url.host.toLowerCase();
    return host == 'theaudiodb.com' || host.endsWith('.theaudiodb.com');
  }

  bool _trustedCoverArtImage(Uri url) {
    if (!_safeUrl(url)) return false;
    if (_isLocal(_coverArt)) return url.host == _coverArt.host;
    final host = url.host.toLowerCase();
    return host == 'coverartarchive.org' ||
        host == 'archive.org' ||
        host.endsWith('.archive.org');
  }

  Uri _secure(Uri uri) {
    if (uri.scheme == 'http' && !_isLocal(uri)) {
      return uri.replace(scheme: 'https');
    }
    return uri;
  }

  bool _safeUrl(Uri uri) =>
      (uri.scheme == 'https' || (uri.scheme == 'http' && _isLocal(uri))) &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      uri.fragment.isEmpty;

  Future<Map<String, dynamic>?> _json(Uri uri) async {
    if (!_safeUrl(uri)) return null;
    // Metadata hosts are fixed; don't follow untrusted redirects.
    final response = await _get(uri);
    if (response.statusCode != 200) {
      await response.drain<void>().timeout(const Duration(seconds: 8));
      return null;
    }
    final bytes = await _body(response, _maxJsonBytes);
    if (bytes == null) return null;
    final decoded = jsonDecode(utf8.decode(bytes));
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Future<List<int>?> _image(Uri uri, bool Function(Uri) allowed) async {
    var current = _secure(uri);
    for (var redirects = 0; redirects <= 3; redirects++) {
      if (!allowed(current)) return null;
      final response = await _get(current);
      if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>().timeout(const Duration(seconds: 8));
        if (location == null || redirects == 3) return null;
        current = _secure(current.resolve(location));
        continue;
      }
      if (response.statusCode != 200) {
        await response.drain<void>().timeout(const Duration(seconds: 8));
        return null;
      }
      final bytes = await _body(response, _maxImageBytes);
      return bytes != null && _looksLikeImage(bytes) ? bytes : null;
    }
    return null;
  }

  Future<HttpClientResponse> _get(Uri uri) async {
    _ensureActive();
    final request = await _client
        .getUrl(uri)
        .timeout(const Duration(seconds: 8));
    final operation = Zone.current[_operationZoneKey] as _ArtworkOperation?;
    if (_closed || operation?.cancelled == true) {
      request.abort();
      throw StateError('Artwork request cancelled');
    }
    operation?.requests.add(request);
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'SylphyMusic/1.0.59 (https://github.com/ymltsh/SylphyMusic)',
    );
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    // Deliberately no music-source headers, tokens, cookies or authorization.
    return request.close().timeout(const Duration(seconds: 10));
  }

  Future<List<int>?> _body(HttpClientResponse response, int limit) async {
    if (response.contentLength > limit) return null;
    final data = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      if (data.length + chunk.length > limit) return null;
      data.add(chunk);
    }
    if (response.contentLength >= 0 && response.contentLength != data.length)
      return null;
    return data.takeBytes();
  }

  bool _looksLikeImage(List<int> bytes) {
    if (bytes.length < 12) return false;
    // PNG / JPEG / WebP / GIF. MediaAssetStore performs full codec validation.
    final png =
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47;
    final jpg = bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
    final webp =
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    final gif =
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38;
    return png || jpg || webp || gif;
  }

  @override
  void close() {
    _closed = true;
    for (final operation in _operations.toList()) {
      operation.cancel();
    }
    _client.close(force: true);
    _misses.clear();
  }

  void _ensureActive() {
    final operation = Zone.current[_operationZoneKey] as _ArtworkOperation?;
    if (_closed || operation?.cancelled == true) {
      throw StateError('Artwork request cancelled');
    }
  }

  void suspendSource(String id) {
    _epochs[id] = (_epochs[id] ?? 0) + 1;
    for (final operation in _operations.toList()) {
      if (operation.sourceId == id) operation.cancel();
    }
  }
}
