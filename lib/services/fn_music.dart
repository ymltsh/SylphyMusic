part of 'sources.dart';

/// Read-only fnOS Music integration (the built-in /music application).
///
/// Accounts belong to the Music application, not necessarily to the NAS OS.
/// A source is isolated by sourceId and uses the same protected credential
/// vault, staging index, loopback playback proxy, and cache as other adapters.
class FnMusicAdapter extends MusicAdapter {
  FnMusicAdapter(super.profile, this.vault);

  final AuthVault vault;
  final StrictTransport transport = StrictTransport();

  Uri _url(String path, [Map<String, String>? query]) =>
      appendPath(profile, 'api/v1/$path', query);

  Future<Map<String, String>> _headers() async {
    final token = await vault.read(profile.id, 'token');
    return {
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Cookie': 'music-token=$token',
    };
  }

  Future<dynamic> _api(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool public = false,
  }) async {
    final response = await transport.request(
      method,
      _url(path, query),
      headers: public ? const {'Accept': 'application/json'} : await _headers(),
      body: body,
      retrySafe: method == 'GET',
    );
    final envelope = jsonDecode(response.body) as Map<String, dynamic>;
    final code = (envelope['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      if (code == 99999 || code == 120001) {
        throw const HttpFailure(401, '飞牛音乐登录已失效，请重新验证');
      }
      throw StateError(
        '飞牛音乐请求失败（$code：${envelope['msg']?.toString() ?? '未知错误'}）',
      );
    }
    return envelope['data'];
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map<String, dynamic> ? value : <String, dynamic>{};

  int _int(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  Future<void> login(String password) async {
    final config = _map(await _api('GET', 'sys/config', public: true));
    final data = _map(
      await _api(
        'POST',
        'user/password-login',
        public: true,
        body: {
          'username': profile.username,
          'password': sha256.convert(utf8.encode(password)).toString(),
          'deviceId': profile.id.replaceAll('-', ''),
        },
      ),
    );
    final token = data['userToken']?.toString() ?? '';
    if (token.isEmpty) throw StateError('飞牛音乐未返回登录令牌');
    await vault.write(profile.id, 'token', token);
    final serverId = config['serverGUID']?.toString() ?? '';
    if (serverId.isNotEmpty) {
      await vault.write(profile.id, 'serverId', serverId);
    }
    final user = _map(data['user']);
    final userId = user['guid']?.toString() ?? '';
    if (userId.isNotEmpty) {
      await vault.write(profile.id, 'userId', userId);
    }
    await validateConnection();
  }

  @override
  Future<void> validateConnection() async {
    final info = _map(await _api('GET', 'sys/config', public: true));
    final serverId = await vault.read(profile.id, 'serverId');
    if (serverId != null &&
        serverId.isNotEmpty &&
        info['serverGUID']?.toString() != serverId) {
      throw StateError('飞牛音乐服务器身份已变化，请添加独立来源');
    }
    final raw = _map(await _api('GET', 'user/me'));
    final user = raw['user'] is Map<String, dynamic>
        ? raw['user'] as Map<String, dynamic>
        : raw;
    final userId = await vault.read(profile.id, 'userId');
    if (userId != null &&
        userId.isNotEmpty &&
        user['guid']?.toString() != userId) {
      throw StateError('飞牛音乐账号身份不匹配，请添加独立来源');
    }
  }

  Track _track(Map<String, dynamic> value) {
    final album = _map(value['album']);
    final audio = _map(value['audioSpec']);
    final artists = (value['artists'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((e) => e['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
    final guid = value['guid']?.toString() ?? '';
    final durationSeconds = _int(value['duration'] ?? audio['duration']);
    return Track(
      ref: TrackRef(profile.id, guid),
      title: value['title']?.toString() ?? '未知标题',
      artist: artists.isEmpty ? '未知艺术家' : artists.join(' / '),
      album: album['name']?.toString() ?? '',
      albumArtist: artists.isEmpty ? '' : artists.first,
      durationMs: durationSeconds * 1000,
      coverId: value['coverId']?.toString() ?? '',
      year: _int(value['year']),
      disc: _int(value['discNo']),
      number: _int(value['trackNo']),
      missing:
          value['accessStatus'] == 3 ||
          value['accessStatus'] == '3' ||
          value['isAudioFileDeleted'] == true ||
          value['audioFileDeleted'] == true,
      remote: {
        'size': audio['size'],
        'changed': value['updatedAt'],
        'format': audio['format']?.toString().toUpperCase(),
        'bitrate': audio['bitrate'],
        'sampleRate': audio['sampleRate'],
        'bitDepth': audio['bitDepth'],
        'coverUpdatedAt': value['updatedAt'],
      },
    );
  }

  @override
  Stream<List<Track>> libraryPages() async* {
    const size = 200;
    var received = 0;
    String? firstPreviousPage;
    for (var page = 1; page <= 100000; page++) {
      final data = _map(
        await _api(
          'GET',
          'track/list',
          query: {'page': '$page', 'size': '$size'},
        ),
      );
      final entries = (data['list'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final total = _int(data['total']);
      if (entries.isEmpty) {
        if (page == 1 && total == 0) return;
        throw StateError('飞牛音乐分页意外提前结束，旧索引已保留');
      }
      final first = entries.first['guid']?.toString() ?? '';
      if (first.isEmpty || first == firstPreviousPage) {
        throw StateError('飞牛音乐分页没有前进，旧索引已保留');
      }
      firstPreviousPage = first;
      if (entries.any((e) => (e['guid']?.toString() ?? '').isEmpty)) {
        throw StateError('飞牛音乐返回无身份曲目，旧索引已保留');
      }
      received += entries.length;
      yield entries.map(_track).toList();
      if (total > 0 && received >= total) return;
      if (entries.length < size) {
        if (total > 0 && received < total) {
          throw StateError('飞牛音乐索引不完整，旧索引已保留');
        }
        return;
      }
    }
    throw StateError('飞牛音乐索引页数超出安全上限');
  }

  @override
  Future<List<Track>> fetchLibrary() async {
    final tracks = <Track>[];
    await for (final page in libraryPages()) {
      tracks.addAll(page);
    }
    return tracks;
  }

  /// Cloud playlists can be browsed, but server-side writes are deliberately
  /// disabled: the remote mutation API does not guarantee duplicate ordering.
  @override
  Future<List<RemotePlaylist>> fetchPlaylists() async {
    const size = 200;
    final result = <RemotePlaylist>[];
    for (var page = 1; page <= 10000; page++) {
      final data = _map(
        await _api(
          'GET',
          'playlist/list',
          query: {'page': '$page', 'size': '$size'},
        ),
      );
      final entries = (data['list'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final total = _int(data['total']);
      if (entries.isEmpty) {
        if (page == 1 && total == 0) return result;
        throw StateError('飞牛音乐歌单分页意外结束');
      }
      for (final entry in entries) {
        final guid = entry['guid']?.toString() ?? '';
        if (guid.isEmpty || result.any((r) => r.id == guid)) {
          throw StateError('飞牛音乐歌单身份重复或丢失');
        }
        result.add(
          RemotePlaylist(
            id: guid,
            name: entry['name']?.toString() ?? '',
            tracks: const [],
            readonly: true,
          ),
        );
      }
      if (total > 0 && result.length >= total) return result;
      if (entries.length < size) {
        if (total > 0 && result.length < total) {
          throw StateError('飞牛音乐歌单列表不完整');
        }
        return result;
      }
    }
    throw StateError('飞牛音乐歌单页数超出安全上限');
  }

  @override
  Future<RemotePlaylist> fetchPlaylist(String id) async {
    const size = 200;
    final tracks = <String>[];
    for (var page = 1; page <= 10000; page++) {
      final data = _map(
        await _api(
          'GET',
          'track/playlist-detail/list',
          query: {'playlistGUID': id, 'page': '$page', 'size': '$size'},
        ),
      );
      final entries = (data['list'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final total = _int(data['total']);
      if (entries.isEmpty) {
        if (page == 1 && total == 0) {
          return RemotePlaylist(
            id: id,
            name: '',
            tracks: tracks,
            readonly: true,
          );
        }
        throw StateError('飞牛音乐歌单曲目分页意外结束');
      }
      for (final entry in entries) {
        final guid = entry['guid']?.toString() ?? '';
        if (guid.isEmpty) throw StateError('飞牛音乐歌单存在无身份曲目');
        tracks.add(TrackRef(profile.id, guid).key);
      }
      if (total > 0 && tracks.length >= total) break;
      if (entries.length < size) {
        if (total > 0 && tracks.length < total) {
          throw StateError('飞牛音乐歌单曲目不完整');
        }
        break;
      }
    }
    return RemotePlaylist(id: id, name: '', tracks: tracks, readonly: true);
  }

  @override
  Future<RemotePlaylist> createPlaylist(String name) async =>
      throw UnsupportedError('暂未开放飞牛音乐云歌单写入');

  @override
  Future<void> mutatePlaylist(
    RemotePlaylist before,
    List<String> desired,
  ) async => throw UnsupportedError('暂未开放飞牛音乐云歌单写入');

  @override
  Future<void> deletePlaylist(String id) async =>
      throw UnsupportedError('暂未开放飞牛音乐云歌单写入');

  @override
  Future<Uri> mediaUrl(Track track) async {
    if (track.missing) throw StateError('飞牛音乐源文件已失效');
    return _url('track/stream', {'guid': track.ref.id});
  }

  @override
  Future<Map<String, String>> mediaHeaders() async {
    final token = await vault.read(profile.id, 'token');
    if (token == null || token.isEmpty) {
      throw const HttpFailure(401, '飞牛音乐登录已失效，请重新验证');
    }
    return {'Cookie': 'music-token=$token'};
  }

  @override
  Future<Uri?> coverUrl(Track track) async {
    if (track.coverId.isEmpty) return null;
    return _url('static/cover', {
      'coverId': track.coverId,
      'size': '800',
      if (_int(track.remote['coverUpdatedAt']) > 0)
        't': '${_int(track.remote['coverUpdatedAt'])}',
    });
  }

  @override
  Future<String?> lyrics(Track track) async {
    final data = _map(
      await _api('GET', 'lyric/list', query: {'trackGUID': track.ref.id}),
    );
    final entries = (data['list'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (entries.isEmpty) return null;
    final preferred = data['preferred']?.toString();
    final lyric =
        entries.where((e) => e['guid']?.toString() == preferred).firstOrNull ??
        entries.first;
    return lyric['content']?.toString();
  }

  @override
  void close() => transport.close();
}
