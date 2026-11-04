part of 'sources.dart';

/// Jellyfin native HTTP API. Deliberately separate from Emby authentication.
class JellyfinAdapter extends MusicAdapter {
  JellyfinAdapter(super.profile, this.vault);

  final AuthVault vault;
  final StrictTransport transport = StrictTransport();

  Future<Map<String, String>> _headers() async {
    final token = await vault.read(profile.id, 'token');
    return {
      'Accept': 'application/json',
      'Authorization':
          'MediaBrowser Client="SylphyMusic", Device="Flutter", '
          'DeviceId="${profile.id}", Version="0.2.0"'
          '${token == null || token.isEmpty ? '' : ', Token="$token"'}',
    };
  }

  Future<Map<String, dynamic>> _api(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final response = await transport.request(
      method,
      appendPath(profile, path, query),
      headers: await _headers(),
      body: body,
      retrySafe: method == 'GET',
    );
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<String> get _userId async {
    final userId = await vault.read(profile.id, 'userId');
    if (userId == null || userId.isEmpty) {
      throw StateError('Jellyfin 账号信息已失效，请重新登录');
    }
    return userId;
  }

  @override
  Future<void> login(String password) async {
    final info = await _api('GET', 'System/Info/Public');
    final serverId = info['Id']?.toString();
    if (serverId == null || serverId.isEmpty) {
      throw StateError('无法识别 Jellyfin 服务器');
    }
    final result = await _api(
      'POST',
      'Users/AuthenticateByName',
      body: {'Username': profile.username, 'Pw': password},
    );
    final token = result['AccessToken']?.toString();
    final userId = (result['User'] as Map?)?['Id']?.toString();
    if (token == null || token.isEmpty || userId == null || userId.isEmpty) {
      throw StateError('Jellyfin 未返回有效的登录身份');
    }
    await vault.write(profile.id, 'token', token);
    await vault.write(profile.id, 'serverId', serverId);
    await vault.write(profile.id, 'userId', userId);
    await validateConnection();
  }

  @override
  Future<void> validateConnection() async {
    final info = await _api('GET', 'System/Info/Public');
    final expectedServer = await vault.read(profile.id, 'serverId');
    if (expectedServer == null || info['Id']?.toString() != expectedServer) {
      throw StateError('Jellyfin 服务器身份不匹配');
    }
    final me = await _api('GET', 'Users/Me');
    if (me['Id']?.toString() != await _userId) {
      throw StateError('Jellyfin 账号身份不匹配');
    }
  }

  Stream<List<Map<String, dynamic>>> _pages(
    String path,
    Map<String, String> query,
  ) async* {
    var offset = 0;
    String? lastPage;
    final seen = <String>{};
    while (true) {
      final result = await _api(
        'GET',
        path,
        query: {...query, 'StartIndex': '$offset', 'Limit': '250'},
      );
      final items = result['Items'];
      if (items is! List) throw StateError('Jellyfin 返回无效的分页结果');
      if (items.isEmpty) {
        final total = (result['TotalRecordCount'] as num?)?.toInt();
        if (total != null && offset < total) {
          throw StateError('Jellyfin 提前结束分页，已保留旧索引');
        }
        break;
      }
      final page = <Map<String, dynamic>>[];
      for (final raw in items) {
        if (raw is! Map) throw StateError('Jellyfin 返回无效的媒体条目');
        final item = Map<String, dynamic>.from(raw);
        final id = item['Id']?.toString();
        if (id == null || id.isEmpty) throw StateError('Jellyfin 曲目缺少 ID');
        // Playlist entries may repeat the same track; library and playlist lists differ.
        if (!path.startsWith('Playlists/') && !seen.add(id)) {
          throw StateError('Jellyfin 分页重复，拒绝覆盖本地索引');
        }
        page.add(item);
      }
      final signature = jsonEncode(page);
      if (signature == lastPage) throw StateError('Jellyfin 分页未前进');
      lastPage = signature;
      final total = (result['TotalRecordCount'] as num?)?.toInt();
      if (total != null && offset + page.length > total) {
        throw StateError('Jellyfin 分页数量不一致，已保留旧索引');
      }
      yield page;
      offset += page.length;
      if (total != null && offset >= total) break;
      if (page.length < 250 && total == null) break;
    }
  }

  Track _toTrack(Map<String, dynamic> item) {
    final id = item['Id'].toString();
    final artists =
        (item['Artists'] as List?)
            ?.map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .toList() ??
        const <String>[];
    final media = (item['MediaSources'] as List?)?.whereType<Map>().firstOrNull;
    final albumId = item['AlbumId']?.toString() ?? '';
    return Track(
      ref: TrackRef(profile.id, id),
      title: item['Name']?.toString() ?? '',
      artist: artists.isEmpty ? '未知艺术家' : artists.join(', '),
      album: item['Album']?.toString() ?? '',
      albumArtist: item['AlbumArtist']?.toString() ?? '',
      durationMs: ((item['RunTimeTicks'] as num? ?? 0) / 10000).round(),
      year: (item['ProductionYear'] as num?)?.toInt() ?? 0,
      disc: (item['ParentIndexNumber'] as num?)?.toInt() ?? 0,
      number: (item['IndexNumber'] as num?)?.toInt() ?? 0,
      coverId: albumId.isNotEmpty ? albumId : id,
      remote: {
        ...item,
        'size': media?['Size'],
        'contentType': item['Container'] ?? media?['Container'],
      },
    );
  }

  @override
  Stream<List<Track>> libraryPages() async* {
    await for (final page in _pages('Items', {
      'UserId': await _userId,
      'Recursive': 'true',
      'IncludeItemTypes': 'Audio',
      'Fields': 'MediaSources,MediaStreams,Genres,DateModified,Album,AlbumArtist,Artists',
    })) {
      yield page.map(_toTrack).toList();
    }
  }

  @override
  Future<List<Track>> fetchLibrary() async {
    final tracks = <Track>[];
    await for (final page in libraryPages()) {
      tracks.addAll(page);
    }
    return tracks;
  }

  @override
  Future<List<RemotePlaylist>> fetchPlaylists() async {
    final result = <RemotePlaylist>[];
    await for (final page in _pages('Items', {
      'UserId': await _userId,
      'Recursive': 'true',
      'IncludeItemTypes': 'Playlist',
    })) {
      result.addAll(
        page.map(
          (item) => RemotePlaylist(
            id: item['Id'].toString(),
            name: item['Name']?.toString() ?? '未命名',
            tracks: const [],
            readonly: true,
          ),
        ),
      );
    }
    return result;
  }

  @override
  Future<RemotePlaylist> fetchPlaylist(String id) async {
    final item = await _api(
      'GET',
      'Users/${await _userId}/Items/${Uri.encodeComponent(id)}',
    );
    if (item['Type'] != 'Playlist') throw StateError('Jellyfin 对象不是歌单');
    final tracks = <String>[];
    final entryIds = <String>[];
    await for (final page in _pages(
      'Playlists/${Uri.encodeComponent(id)}/Items',
      {'UserId': await _userId},
    )) {
      for (final track in page) {
        tracks.add(TrackRef(profile.id, track['Id'].toString()).key);
        entryIds.add(track['PlaylistItemId']?.toString() ?? '');
      }
    }
    return RemotePlaylist(
      id: id,
      name: item['Name']?.toString() ?? '',
      tracks: tracks,
      entryIds: entryIds,
      readonly: true,
    );
  }

  @override
  Future<RemotePlaylist> createPlaylist(String name) async =>
      throw UnsupportedError('Jellyfin 歌单写入暂未开放');

  @override
  Future<void> mutatePlaylist(
    RemotePlaylist before,
    List<String> desired,
  ) async => throw UnsupportedError('Jellyfin 歌单写入暂未开放');

  @override
  Future<void> deletePlaylist(String id) async =>
      throw UnsupportedError('Jellyfin 歌单写入暂未开放');

  @override
  Future<Uri> mediaUrl(Track track) async => appendPath(
    profile,
    'Audio/${Uri.encodeComponent(track.ref.id)}/stream',
    {'Static': 'true'},
  );

  @override
  Future<Map<String, String>> mediaHeaders() => _headers();

  @override
  Future<List<Uri>> coverUrls(Track track) async {
    final ids = <String>[];
    if ((track.remote['ImageTags'] as Map?)?['Primary'] != null) {
      ids.add(track.ref.id);
    }
    final albumId = track.remote['AlbumId']?.toString() ?? '';
    if (albumId.isNotEmpty) ids.add(albumId);
    ids.add(track.ref.id);
    return ids
        .toSet()
        .map(
          (id) => appendPath(
            profile,
            'Items/${Uri.encodeComponent(id)}/Images/Primary',
            {'MaxWidth': '800', 'Quality': '90'},
          ),
        )
        .toList();
  }

  @override
  Future<Uri?> coverUrl(Track track) async =>
      (await coverUrls(track)).firstOrNull;

  @override
  Future<String?> lyrics(Track track) async {
    Map<String, dynamic> data;
    try {
      data = await _api(
        'GET',
        'Audio/${Uri.encodeComponent(track.ref.id)}/Lyrics',
      );
    } on HttpFailure catch (error) {
      if (error.status == 404) return null;
      rethrow;
    }
    final lines = data['Lyrics'];
    if (lines is! List) return null;
    final text = <String>[];
    for (final raw in lines) {
      if (raw is! Map) continue;
      final value = raw['Text']?.toString() ?? '';
      if (value.isEmpty) continue;
      final ticks = raw['Start'] ?? raw['StartTicks'];
      if (ticks is num && ticks >= 0) {
        final hundredths = (ticks / 100000).round();
        final minutes = hundredths ~/ 6000;
        final seconds = (hundredths ~/ 100) % 60;
        final centiseconds = hundredths % 100;
        text.add(
          '[${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${centiseconds.toString().padLeft(2, '0')}]$value',
        );
      } else {
        text.add(value);
      }
    }
    return text.isEmpty ? null : text.join('\n');
  }

  @override
  void close() => transport.close();
}
