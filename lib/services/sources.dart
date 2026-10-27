import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../core/models.dart';
import 'local_library.dart' show audioExtensions;
import 'lyrics.dart';

part 'webdav.dart';

class RemotePlaylist {
  const RemotePlaylist({
    required this.id,
    required this.name,
    required this.tracks,
    this.entryIds = const [],
    this.readonly = false,
  });
  final String id, name;
  final List<String> tracks;
  final List<String> entryIds;
  final bool readonly;
}

abstract class MusicAdapter {
  MusicAdapter(this.profile);
  final SourceProfile profile;
  Future<void> login(String password);
  Future<void> validateConnection() async {
    await fetchPlaylists();
  }

  Future<List<Track>> fetchLibrary();
  Stream<List<Track>> libraryPages() async* {
    yield await fetchLibrary();
  }

  Future<List<RemotePlaylist>> fetchPlaylists();
  Future<RemotePlaylist> fetchPlaylist(String id);
  Future<RemotePlaylist> createPlaylist(String name);
  Future<void> mutatePlaylist(RemotePlaylist before, List<String> desired);
  Future<void> deletePlaylist(String id);
  Future<void> renamePlaylist(String id, String name) async =>
      throw UnsupportedError('此来源暂不支持歌单改名');
  Future<Uri> mediaUrl(Track track);
  Future<String?> lyrics(Track track);
  Future<Map<String, String>> mediaHeaders();
  Future<Uri?> coverUrl(Track track) async => null;
  Future<List<Uri>> coverUrls(Track track) async {
    final url = await coverUrl(track);
    return url == null ? [] : [url];
  }

  void close();
}

class AuthVault {
  const AuthVault();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  Future<void> write(String id, String name, String value) =>
      _storage.write(key: 'source.$id.$name', value: value);
  Future<String?> read(String id, String name) =>
      _storage.read(key: 'source.$id.$name');
  Future<void> delete(String id) async {
    for (final name in ['token', 'password', 'userId', 'serverId']) {
      await _storage.delete(key: 'source.$id.$name');
    }
  }
}

Uri appendPath(SourceProfile p, String segment, [Map<String, String>? query]) {
  final base = Uri.parse(p.url);
  if (base.scheme != 'https' && base.scheme != 'http') {
    throw const FormatException('仅支持 HTTP 或 HTTPS');
  }
  if (base.userInfo.isNotEmpty) throw const FormatException('URL 不允许包含用户名或密码');
  if (base.host.isEmpty || base.hasQuery || base.hasFragment) {
    throw const FormatException('服务器地址需要有效主机，且不能含查询参数或片段');
  }
  final prefix = base.path.endsWith('/') ? base.path : '${base.path}/';
  return base.replace(
    path: '$prefix${segment.replaceFirst(RegExp(r'^/'), '')}',
    queryParameters: query,
  );
}

class StrictTransport {
  final http.Client _client = http.Client();
  Future<http.Response> request(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    bool retrySafe = false,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _once(method, url, headers: headers, body: body);
      } catch (error) {
        final transient =
            error is SocketException ||
            error is TimeoutException ||
            (error is http.ClientException &&
                !RegExp(
                  'certificate|handshake|ssl|tls',
                  caseSensitive: false,
                ).hasMatch(error.message)) ||
            (error is HttpFailure &&
                [408, 429, 502, 503, 504].contains(error.status));
        if (!retrySafe || !transient || attempt >= 2) {
          if (error is http.ClientException ||
              error is SocketException ||
              error is TimeoutException ||
              error is HandshakeException) {
            throw StateError('连接失败或安全连接校验失败，请检查网络与服务器配置');
          }
          rethrow;
        }
        await Future<void>.delayed(
          Duration(milliseconds: 250 * (1 << attempt) + Random().nextInt(150)),
        );
      }
    }
  }

  Future<http.Response> _once(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    // package:http IOClient follows redirects automatically; reject final origin mismatch
    // and HTTPS downgrade. Do not attach secrets to an unexpected redirect origin.
    final r = http.Request(method, url)..followRedirects = false;
    r.headers.addAll(headers ?? {});
    if (body != null) {
      r.body = body is String ? body : jsonEncode(body);
      if (body is! String) r.headers['Content-Type'] = 'application/json';
    }
    final streamed = await _client.send(r).timeout(const Duration(seconds: 25));
    if (streamed.statusCode >= 300 && streamed.statusCode < 400) {
      throw StateError('拒绝未经验证的 HTTP 重定向 (${streamed.statusCode})');
    }
    final resp = await http.Response.fromStream(streamed)
        .timeout(const Duration(seconds: 45));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpFailure(resp.statusCode, switch (resp.statusCode) {
        401 => '登录已失效，请重新登录',
        403 => '当前账号没有访问权限',
        404 => '服务器资源不存在',
        _ => '服务器请求失败',
      });
    }
    return resp;
  }

  void close() => _client.close();
}

class HttpFailure implements Exception {
  const HttpFailure(this.status, this.detail);
  final int status;
  final String detail;
  @override
  String toString() => 'HTTP $status: $detail';
}

class EmbyAdapter extends MusicAdapter {
  EmbyAdapter(super.profile, this.vault);
  final AuthVault vault;
  final StrictTransport transport = StrictTransport();
  Future<Map<String, String>> _headers() async {
    final token = await vault.read(profile.id, 'token');
    return {
      'Accept': 'application/json',
      'X-Emby-Authorization':
          'MediaBrowser Client="Sylphy Music", Device="Flutter", DeviceId="${profile.id}", Version="0.2.0"',
      'X-Emby-Token': ?token,
    };
  }

  Future<dynamic> _api(
    String method,
    String path, [
    Map<String, String>? query,
    Object? body,
  ]) async {
    final resp = await transport.request(
      method,
      appendPath(profile, path, query),
      headers: await _headers(),
      body: body,
      retrySafe: method == 'GET',
    );
    if (resp.body.trim().isEmpty) return <String, dynamic>{};
    return jsonDecode(resp.body);
  }

  @override
  Future<void> login(String password) async {
    final r = await transport.request(
      'POST',
      appendPath(profile, 'Users/AuthenticateByName'),
      headers: await _headers(),
      body: {'Username': profile.username, 'Pw': password},
    );
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final token = data['AccessToken'] as String?;
    if (token == null || token.isEmpty) {
      throw StateError('Emby 未返回 AccessToken');
    }
    await vault.write(profile.id, 'token', token);
    final serverId = data['ServerId']?.toString();
    if (serverId != null && serverId.isNotEmpty) {
      await vault.write(profile.id, 'serverId', serverId);
    }
    await vault.write(
      profile.id,
      'userId',
      (data['User'] as Map?)?['Id']?.toString() ?? '',
    );
  }

  Future<String> get _userId async =>
      (await vault.read(profile.id, 'userId')) ?? profile.remoteUserId;

  @override
  Future<void> validateConnection() async {
    final public = await transport.request(
      'GET',
      appendPath(profile, 'System/Info/Public'),
      retrySafe: true,
    );
    final info = jsonDecode(public.body) as Map;
    final expected = await vault.read(profile.id, 'serverId');
    if (expected != null && info['Id']?.toString() != expected) {
      throw StateError('服务器身份已变化，请重新编辑连接并登录');
    }
    final id = await _userId;
    if (id.isEmpty) throw StateError('登录信息不完整，请重新登录');
    final user = await _api('GET', 'Users/$id') as Map;
    if (user['Id']?.toString() != id) throw StateError('服务器账号身份不匹配，请重新登录');
  }

  Future<List<Map<String, dynamic>>> _pagedItems(
    String path,
    Map<String, String> query, {
    bool playlistEntries = false,
  }) async {
    final result = <Map<String, dynamic>>[];
    await for (final page in _itemPages(
      path,
      query,
      playlistEntries: playlistEntries,
    )) {
      result.addAll(page);
    }
    return result;
  }

  Stream<List<Map<String, dynamic>>> _itemPages(
    String path,
    Map<String, String> query, {
    bool playlistEntries = false,
  }) async* {
    final seen = <String>{};
    String? lastPage;
    for (var start = 0; ;) {
      final data = await _api('GET', path, {
        ...query,
        'StartIndex': '$start',
        'Limit': '250',
      }) as Map<String, dynamic>;
      if (data['Items'] is! List) throw StateError('服务器没有返回有效列表，已保留旧索引');
      final raw = data['Items'] as List;
      if (raw.isEmpty) break;
      final page = raw
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final total = data['TotalRecordCount'] as num?;
      final signature = jsonEncode(page);
      if (total == null && signature == lastPage) {
        throw StateError('服务器分页没有前进，已保留旧索引');
      }
      lastPage = signature;
      for (final item in page) {
        final id = item[playlistEntries ? 'PlaylistItemId' : 'Id']?.toString();
        if (!playlistEntries && (id == null || id.isEmpty)) {
          throw StateError('服务器返回了无效资源身份');
        }
        if (id != null && id.isNotEmpty && !seen.add(id)) {
          throw StateError('服务器分页出现重复资源身份，已停止刷新');
        }
      }
      yield page;
      start += page.length;
      if (total != null && start >= total) break;
    }
  }

  Track _track(Map<String, dynamic> x) {
    final artists =
        (x['Artists'] as List?)?.map((e) => e.toString()).toList() ?? [];
    return Track(
      ref: TrackRef(profile.id, x['Id'].toString()),
      title: x['Name']?.toString() ?? '',
      artist: artists.isEmpty ? '未知艺术家' : artists.join(', '),
      album: x['Album']?.toString() ?? '',
      albumArtist: x['AlbumArtist']?.toString() ?? '',
      durationMs: ((x['RunTimeTicks'] as num? ?? 0) / 10000).round(),
      year: (x['ProductionYear'] as num?)?.toInt() ?? 0,
      number: (x['IndexNumber'] as num?)?.toInt() ?? 0,
      disc: (x['ParentIndexNumber'] as num?)?.toInt() ?? 0,
      coverId: (x['ImageTags'] as Map?)?['Primary'] != null
          ? x['Id'].toString()
          : x['AlbumPrimaryImageTag'] != null
          ? x['AlbumId']?.toString() ?? x['Id'].toString()
          : x['Id'].toString(),
      remote: {
        ...x,
        'format':
            x['Container'] ??
            ((x['MediaSources'] as List?)
                ?.whereType<Map>()
                .firstOrNull)?['Container'],
        'sampleRate': (x['MediaStreams'] as List?)
            ?.whereType<Map>()
            .where((stream) => stream['Type'] == 'Audio')
            .firstOrNull?['SampleRate'],
        'bitrate': (x['MediaStreams'] as List?)
            ?.whereType<Map>()
            .where((stream) => stream['Type'] == 'Audio')
            .firstOrNull?['BitRate'],
      },
    );
  }

  @override
  Future<List<Track>> fetchLibrary() async {
    final result = <Track>[];
    await for (final page in libraryPages()) {
      result.addAll(page);
    }
    return result;
  }

  @override
  Stream<List<Track>> libraryPages() async* {
    final userId = await _userId;
    if (userId.isEmpty) throw StateError('Emby 未保存用户 ID，请重新登录');
    await for (final page in _itemPages('Users/$userId/Items', {
      'Recursive': 'true',
      'IncludeItemTypes': 'Audio',
      'Fields': 'Genres,DateCreated,DateModified,MediaSources,MediaStreams,Album,AlbumArtist,Artists,ProductionYear',
    })) {
      yield page.map(_track).toList();
    }
  }

  @override
  Future<List<RemotePlaylist>> fetchPlaylists() async {
    final u = await _userId;
    return (await _pagedItems('Users/$u/Items', {
          'Recursive': 'true',
          'IncludeItemTypes': 'Playlist',
        }))
        .map(
          (item) => RemotePlaylist(
            id: item['Id'].toString(),
            name: item['Name']?.toString() ?? '未命名',
            tracks: const [],
            readonly: item['CanEdit'] == false,
          ),
        )
        .toList();
  }

  @override
  Future<RemotePlaylist> fetchPlaylist(String id) async {
    final u = await _userId;
    final metadata =
        await _api('GET', 'Users/$u/Items/$id') as Map<String, dynamic>;
    if (metadata['Type'] != 'Playlist') throw StateError('远程对象不是歌单');
    final items = await _pagedItems('Playlists/$id/Items', {
      'UserId': u,
    }, playlistEntries: true);
    return RemotePlaylist(
      id: id,
      name: metadata['Name']?.toString() ?? '',
      readonly: metadata['CanEdit'] == false,
      tracks: items
          .map((e) => TrackRef(profile.id, e['Id'].toString()).key)
          .toList(),
      entryIds: items
          .map((e) => e['PlaylistItemId']?.toString() ?? '')
          .toList(),
    );
  }

  @override
  Future<RemotePlaylist> createPlaylist(String name) async {
    final u = await _userId;
    final r = await _api('POST', 'Playlists', {
      'UserId': u,
      'Name': name,
      'MediaType': 'Audio',
    }) as Map<String, dynamic>;
    final id = (r['Id'] ?? r['id'])?.toString();
    if (id == null) throw StateError('Emby 未返回新歌单 ID');
    return RemotePlaylist(id: id, name: name, tracks: const []);
  }

  @override
  Future<void> mutatePlaylist(
    RemotePlaylist before,
    List<String> desired,
  ) async {
    final u = await _userId;
    var common = 0;
    while (common < before.tracks.length &&
        common < desired.length &&
        before.tracks[common] == desired[common]) {
      common++;
    }
    // Non-transactional remote mutation: never erase the matching prefix.
    final ids = before.entryIds
        .skip(common)
        .where((e) => e.isNotEmpty)
        .toList();
    if (ids.length != before.tracks.length - common) {
      throw StateError('服务器缺少 PlaylistItemId，拒绝危险的覆盖');
    }
    if (ids.isNotEmpty) {
      await _api('DELETE', 'Playlists/${before.id}/Items', {
        'UserId': u,
        'EntryIds': ids.join(','),
      });
    }
    final toAdd = desired
        .skip(common)
        .map((e) => TrackRef.parse(e).id)
        .toList();
    if (toAdd.isNotEmpty) {
      await _api('POST', 'Playlists/${before.id}/Items', {
        'UserId': u,
        'Ids': toAdd.join(','),
      });
    }
  }

  @override
  Future<void> deletePlaylist(String id) async {
    final playlist = await fetchPlaylist(id);
    if (playlist.readonly) throw StateError('服务器歌单只读');
    await _api('DELETE', 'Items/$id');
  }

  @override
  Future<void> renamePlaylist(String id, String name) async {
    final u = await _userId;
    final metadata =
        await _api('GET', 'Users/$u/Items/$id') as Map<String, dynamic>;
    if (metadata['Type'] != 'Playlist' || metadata['CanEdit'] == false) {
      throw StateError('目标不是可编辑歌单');
    }
    await _api('POST', 'Items/$id', null, {...metadata, 'Name': name});
  }

  @override
  Future<String?> lyrics(Track track) async {
    // Refresh streams: an existing library index may predate server lyric scans.
    final user = await _userId;
    final item = await _api('GET', 'Users/$user/Items/${track.ref.id}', {
      'Fields': 'MediaSources,MediaStreams',
    }) as Map;
    final sources =
        (item['MediaSources'] as List?)?.whereType<Map>().toList() ?? [];
    if (sources.isEmpty) {
      sources.add({'Id': track.ref.id, 'MediaStreams': item['MediaStreams']});
    }
    String? plainFallback;
    for (final source in sources) {
      final streams = (source['MediaStreams'] ?? item['MediaStreams']) as List?;
      for (final stream in streams?.whereType<Map>() ?? const <Map>[]) {
        final codec = stream['Codec']?.toString().toLowerCase();
        if (stream['Type'] != 'Subtitle' ||
            !(stream['IsTextSubtitleStream'] == true ||
                [
                  'lrc',
                  'text',
                  'txt',
                  'srt',
                  'subrip',
                  'vtt',
                  'webvtt',
                  'ass',
                  'ssa',
                ].contains(codec))) {
          continue;
        }
        final index = int.tryParse('${stream['Index']}');
        if (index == null || index < 0) continue;
        final mediaId = source['Id']?.toString() ?? track.ref.id;
        // Stream.txt can strip every timestamp from embedded text lyrics.
        // Ask Emby for a timed subtitle conversion before a plain-text fallback.
        final formats = codec == 'lrc' ? ['lrc', 'srt', 'txt'] : ['srt', 'txt'];
        for (final format in formats) {
          for (final route in ['Items', 'Videos']) {
            try {
              final response = await transport.request(
                'GET',
                appendPath(
                  profile,
                  '$route/${track.ref.id}/$mediaId/Subtitles/$index/Stream.$format',
                ),
                headers: {...await _headers(), 'Accept': 'text/plain'},
                retrySafe: true,
              );
              if (response.bodyBytes.length > 1024 * 1024) {
                throw StateError('服务器歌词超过 1 MiB');
              }
              final text = normalizeSubtitleLyrics(
                utf8.decode(response.bodyBytes),
              );
              if (text.isNotEmpty) {
                if (parseLrc(text).isNotEmpty) return text;
                plainFallback ??= text;
              }
              break;
            } on HttpFailure catch (error) {
              if (error.status == 404 && route == 'Items') continue;
              if ([400, 404, 406, 415].contains(error.status)) break;
              rethrow;
            }
          }
        }
      }
    }
    return plainFallback;
  }

  @override
  Future<Uri> mediaUrl(Track track) async =>
      appendPath(profile, 'Audio/${track.ref.id}/stream', {'Static': 'true'});
  @override
  Future<Map<String, String>> mediaHeaders() => _headers();
  @override
  Future<Uri?> coverUrl(Track track) async => (await coverUrls(track)).first;
  @override
  Future<List<Uri>> coverUrls(Track track) async {
    final images = <String, String?>{};
    void add(Object? id, Object? tag) {
      if (id == null || id.toString().isEmpty) return;
      images.putIfAbsent(id.toString(), () => tag?.toString());
    }

    final ownTag = (track.remote['ImageTags'] as Map?)?['Primary'];
    if (ownTag != null) add(track.ref.id, ownTag);
    final albumTag = track.remote['AlbumPrimaryImageTag'];
    if (albumTag != null) add(track.remote['AlbumId'], albumTag);
    final parentTag = track.remote['ParentPrimaryImageTag'];
    if (parentTag != null) {
      add(track.remote['ParentPrimaryImageItemId'], parentTag);
    }
    // Old indexed rows may have an album cover_id even when only the song has art.
    add(track.ref.id, null);
    add(track.remote['AlbumId'], null);
    add(track.coverId, null);
    return [
      for (final image in images.entries)
        appendPath(
          profile,
          'Items/${Uri.encodeComponent(image.key)}/Images/Primary',
          {
            if (image.value?.isNotEmpty == true) 'tag': image.value!,
            'MaxWidth': '800',
            'Quality': '90',
          },
        ),
    ];
  }

  @override
  void close() => transport.close();
}

class SubsonicAdapter extends MusicAdapter {
  bool _readonly(Map data) =>
      data['readonly'] == true ||
      (data['owner'] is String &&
          (data['owner'] as String).isNotEmpty &&
          (data['owner'] as String).toLowerCase() !=
              profile.username.toLowerCase());
  SubsonicAdapter(super.profile, this.vault);
  final AuthVault vault;
  final StrictTransport transport = StrictTransport();
  @override
  Future<void> validateConnection() async {
    await _api('ping');
  }

  Future<Uri> _url(String method, [Map<String, String>? q]) async {
    final password = await vault.read(profile.id, 'password');
    if (password == null) throw StateError('缺少 OpenSubsonic 密码');
    final salt = const Uuid().v4().replaceAll('-', '').substring(0, 12);
    final token = md5.convert(utf8.encode('$password$salt')).toString();
    return appendPath(profile, 'rest/$method.view', {
      'u': profile.username,
      't': token,
      's': salt,
      'v': '1.16.1',
      'c': 'SylphyMusic',
      'f': 'json',
      ...?q,
    });
  }

  Future<Map<String, dynamic>> _api(
    String method, [
    Map<String, String>? q,
  ]) async {
    final r = await transport.request(
      'GET',
      await _url(method, q),
      retrySafe: const {
        'ping',
        'getAlbumList2',
        'getAlbum',
        'getPlaylists',
        'getPlaylist',
        'getLyrics',
        'getLyricsBySongId',
      }.contains(method),
      headers: const {'Accept': 'application/json'},
    );
    final data =
        (jsonDecode(r.body) as Map<String, dynamic>)['subsonic-response']
            as Map<String, dynamic>;
    if (data['status'] != 'ok') {
      final code = (data['error'] as Map?)?['code'];
      if (code == 40) throw const HttpFailure(401, 'OpenSubsonic 登录失败');
      if (code == 50) throw const HttpFailure(403, 'OpenSubsonic 无操作权限');
      throw StateError('OpenSubsonic 请求失败（错误码 $code）');
    }
    return data;
  }

  @override
  Future<void> login(String password) async {
    await vault.write(profile.id, 'password', password);
    try {
      await _api('ping');
    } catch (_) {
      await vault.write(profile.id, 'password', '');
      rethrow;
    }
  }

  Track _track(Map<String, dynamic> x) => Track(
    ref: TrackRef(profile.id, x['id'].toString()),
    title: x['title']?.toString() ?? '',
    artist: x['artist']?.toString() ?? '未知艺术家',
    album: x['album']?.toString() ?? '',
    albumArtist: x['albumArtist']?.toString() ?? '',
    durationMs: ((x['duration'] as num? ?? 0) * 1000).round(),
    coverId: x['coverArt']?.toString() ?? '',
    year: (x['year'] as num?)?.toInt() ?? 0,
    number: (x['track'] as num?)?.toInt() ?? 0,
    disc: (x['discNumber'] as num?)?.toInt() ?? 0,
    remote: {
      ...x,
      'format': x['suffix']?.toString().toUpperCase(),
      'sampleRate': x['samplingRate'] ?? x['sampleRate'],
      'bitrate': (x['bitRate'] as num?)?.toInt() == null
          ? null
          : (x['bitRate'] as num).toInt() * 1000,
    },
  );
  @override
  Future<List<Track>> fetchLibrary() async {
    final tracks = <Track>[];
    await for (final page in libraryPages()) {
      tracks.addAll(page);
    }
    return tracks;
  }

  @override
  Stream<List<Track>> libraryPages() async* {
    final seenAlbums = <String>{};
    for (var offset = 0; offset < 1000000; offset += 300) {
      final res = await _api('getAlbumList2', {
        'type': 'alphabeticalByName',
        'size': '300',
        'offset': '$offset',
      });
      final albums = ((res['albumList2'] as Map?)?['album'] as List? ?? []);
      for (final a in albums.whereType<Map<String, dynamic>>()) {
        if (!seenAlbums.add(a['id'].toString())) {
          throw StateError('服务器专辑分页没有前进，已保留旧索引');
        }
        final data = await _api('getAlbum', {'id': a['id'].toString()});
        final album = data['album'] as Map?;
        final page = <Track>[];
        for (final song
            in (album?['song'] as List? ?? [])
                .whereType<Map<String, dynamic>>()) {
          page.add(_track(song));
          if (page.length == 250) {
            yield List.of(page);
            page.clear();
          }
        }
        if (page.isNotEmpty) yield page;
      }
      if (albums.length < 300) break;
    }
  }

  @override
  Future<List<RemotePlaylist>> fetchPlaylists() async {
    final r = await _api('getPlaylists');
    return ((r['playlists'] as Map?)?['playlist'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(
          (e) => RemotePlaylist(
            id: e['id'].toString(),
            name: e['name']?.toString() ?? '',
            tracks: const [],
            readonly: _readonly(e),
          ),
        )
        .toList();
  }

  @override
  Future<RemotePlaylist> fetchPlaylist(String id) async {
    final r = await _api('getPlaylist', {'id': id});
    final data = r['playlist'] as Map? ?? {};
    final list = (data['entry'] as List? ?? [])
        .whereType<Map<String, dynamic>>();
    return RemotePlaylist(
      id: id,
      name: data['name']?.toString() ?? '',
      readonly: _readonly(data),
      tracks: list
          .map((s) => TrackRef(profile.id, s['id'].toString()).key)
          .toList(),
    );
  }

  @override
  Future<RemotePlaylist> createPlaylist(String name) async {
    final r = await _api('createPlaylist', {'name': name});
    final id = (r['playlist'] as Map?)?['id']?.toString();
    if (id == null) throw StateError('OpenSubsonic 未返回歌单 ID');
    return RemotePlaylist(id: id, name: name, tracks: const []);
  }

  @override
  Future<void> mutatePlaylist(
    RemotePlaylist before,
    List<String> desired,
  ) async {
    if (before.readonly) throw StateError('服务器歌单只读');
    var prefix = 0;
    while (prefix < before.tracks.length &&
        prefix < desired.length &&
        before.tracks[prefix] == desired[prefix]) {
      prefix++;
    }
    // Repeated query params are required: construct URI with multi-value below.
    final drop = List.generate(
      before.tracks.length - prefix,
      (i) => (before.tracks.length - 1 - i).toString(),
    );
    if (drop.isNotEmpty) {
      await _apiMulti(
        'updatePlaylist',
        {'playlistId': before.id},
        'songIndexToRemove',
        drop,
      );
    }
    final add = desired.skip(prefix).map((k) => TrackRef.parse(k).id).toList();
    if (add.isNotEmpty) {
      await _apiMulti(
        'updatePlaylist',
        {'playlistId': before.id},
        'songIdToAdd',
        add,
      );
    }
  }

  Future<void> _apiMulti(
    String endpoint,
    Map<String, String> q,
    String key,
    List<String> values,
  ) async {
    final base = await _url(endpoint, q);
    final suffix = values
        .map((v) => '$key=${Uri.encodeQueryComponent(v)}')
        .join('&');
    final uri = Uri.parse('$base&$suffix');
    final r = await transport.request('GET', uri);
    final body =
        (jsonDecode(r.body) as Map<String, dynamic>)['subsonic-response']
            as Map;
    if (body['status'] != 'ok') {
      throw StateError('OpenSubsonic 歌单写入失败');
    }
  }

  @override
  Future<void> deletePlaylist(String id) async {
    await _api('deletePlaylist', {'id': id});
  }

  @override
  Future<void> renamePlaylist(String id, String name) async {
    await _api('updatePlaylist', {'playlistId': id, 'name': name});
  }

  @override
  Future<String?> lyrics(Track track) async {
    try {
      final response = await _api('getLyricsBySongId', {'id': track.ref.id});
      final entries =
          ((response['lyricsList'] as Map?)?['structuredLyrics'] as List? ?? [])
              .whereType<Map>();
      final value =
          entries.where((entry) => entry['synced'] == true).firstOrNull ??
          entries.firstOrNull;
      if (value != null) {
        final lines = (value['line'] as List? ?? []).whereType<Map>();
        return lines
            .map((line) {
              final ms = (line['start'] as num?)?.toInt();
              final text = line['value']?.toString() ?? '';
              if (ms == null || value['synced'] != true) return text;
              return '[${(ms ~/ 60000).toString().padLeft(2, '0')}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}.${(ms % 1000).toString().padLeft(3, '0')}]$text';
            })
            .join('\n');
      }
    } catch (_) {
      /* Older Subsonic servers use the text endpoint below. */
    }
    try {
      final response = await _api('getLyrics', {
        'artist': track.artist,
        'title': track.title,
      });
      return (response['lyrics'] as Map?)?['value']?.toString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uri> mediaUrl(Track track) async =>
      _url('stream', {'id': track.ref.id, 'format': 'raw'});
  @override
  Future<Map<String, String>> mediaHeaders() async => const {};
  @override
  Future<Uri?> coverUrl(Track track) async => track.coverId.isEmpty
      ? null
      : _url('getCoverArt', {'id': track.coverId, 'size': '800'});
  @override
  void close() => transport.close();
}

class AdapterFactory {
  AdapterFactory(this.vault);
  final AuthVault vault;
  MusicAdapter create(SourceProfile profile) => switch (profile.kind) {
    SourceKind.emby => EmbyAdapter(profile, vault),
    SourceKind.subsonic => SubsonicAdapter(profile, vault),
    SourceKind.webdav => WebDavAdapter(profile, vault),
    SourceKind.local => throw UnsupportedError('本地音乐使用直接文件路径'),
  };
}
