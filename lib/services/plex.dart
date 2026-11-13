part of 'sources.dart';

/// Basic Plex Media Server adapter using a user-supplied server access token.
/// PIN/JWT account authorization and transcoding are deliberately out of scope.
class PlexAdapter extends MusicAdapter {
  @override
  Future<List<Uri>> artistCoverUrls(Track track) async {
    var thumb = _safeRelativeKey(track.remote['grandparentThumb']);
    if (thumb.isEmpty) {
      final data = await _container(
        'library/metadata/${Uri.encodeComponent(track.ref.id)}',
      );
      final item = _entries(data, 'Metadata').firstOrNull;
      thumb = _safeRelativeKey(item?['grandparentThumb']);
    }
    return thumb.isEmpty ? [] : [_resourceUrl(thumb)];
  }

  PlexAdapter(super.profile, this.vault);

  final AuthVault vault;
  final StrictTransport transport = StrictTransport();

  Future<Map<String, String>> _headers({bool jsonResponse = false}) async {
    final token = await vault.read(profile.id, 'token');
    if (token == null || token.isEmpty) {
      throw StateError('缺少 Plex 访问令牌，请编辑连接');
    }
    return {
      'X-Plex-Token': token,
      'X-Plex-Client-Identifier': profile.id,
      'X-Plex-Product': 'SylphyMusic',
      'X-Plex-Version': '0.2.0',
      if (jsonResponse) 'Accept': 'application/json',
    };
  }

  Future<Map<String, dynamic>> _container(
    String path, {
    Map<String, String>? query,
    Map<String, String>? pageHeaders,
  }) async {
    final response = await transport.request(
      'GET',
      appendPath(profile, path, query),
      headers: {...await _headers(jsonResponse: true), ...?pageHeaders},
      retrySafe: true,
    );
    final data = jsonDecode(response.body);
    if (data is! Map || data['MediaContainer'] is! Map) {
      throw StateError('Plex 未返回 JSON MediaContainer，请检查服务器版本');
    }
    return Map<String, dynamic>.from(data['MediaContainer'] as Map);
  }

  List<Map<String, dynamic>> _entries(Map<String, dynamic> data, String key) {
    final raw = data[key];
    if (raw == null) return const [];
    if (raw is! List) throw StateError('Plex 返回的 $key 不是列表');
    return raw.map((entry) {
      if (entry is! Map) throw StateError('Plex 返回了无效条目');
      return Map<String, dynamic>.from(entry);
    }).toList();
  }

  Future<Map<String, dynamic>> _identity() async {
    // /identity is public, but it only provides server identity, not permission.
    final response = await transport.request(
      'GET',
      appendPath(profile, 'identity'),
      headers: const {'Accept': 'application/json'},
      retrySafe: true,
    );
    final data = jsonDecode(response.body);
    if (data is! Map || data['MediaContainer'] is! Map) {
      throw StateError('无法识别 Plex Media Server');
    }
    return Map<String, dynamic>.from(data['MediaContainer'] as Map);
  }

  @override
  Future<void> login(String password) async {
    if (password.trim().isEmpty) throw StateError('请填写 Plex 访问令牌');
    await vault.write(profile.id, 'token', password.trim());
    try {
      final server = await _identity();
      final id = server['machineIdentifier']?.toString();
      if (id == null || id.isEmpty) throw StateError('Plex 未返回服务器标识');
      await _container('library/sections'); // Verify the supplied token.
      await vault.write(profile.id, 'serverId', id);
    } catch (_) {
      await vault.write(profile.id, 'token', '');
      rethrow;
    }
  }

  @override
  Future<void> validateConnection() async {
    final server = await _identity();
    final expected = await vault.read(profile.id, 'serverId');
    if (expected == null ||
        server['machineIdentifier']?.toString() != expected) {
      throw StateError('Plex 服务器身份已改变，请添加独立来源');
    }
    await _container('library/sections');
  }

  /// Streaming pagination. A failed or looping page must not publish a partial index.
  Stream<List<Map<String, dynamic>>> _pages(
    String path, {
    Map<String, String>? query,
    String itemField = 'Metadata',
  }) async* {
    var offset = 0;
    String? lastPage;
    final seen = <String>{};
    while (true) {
      final data = await _container(
        path,
        query: query,
        pageHeaders: {
          'X-Plex-Container-Start': '$offset',
          'X-Plex-Container-Size': '250',
        },
      );
      final page = _entries(data, itemField);
      if (page.isEmpty) {
        final total = (data['totalSize'] as num?)?.toInt();
        if (total != null && offset < total) {
          throw StateError('Plex 提前结束分页，已保留旧索引');
        }
        break;
      }
      final signature = jsonEncode(page);
      if (signature == lastPage) throw StateError('Plex 分页未前进');
      lastPage = signature;
      for (final item in page) {
        final id =
            (itemField == 'Metadata' && path.startsWith('playlists/')
                    ? item['playlistItemID'] ?? item['ratingKey']
                    : item['ratingKey'])
                ?.toString();
        if (id == null || id.isEmpty) {
          throw StateError('Plex 列表条目缺少标识');
        }
        // Duplicate tracks are allowed in playlists, but pages must advance.
        if (!path.startsWith('playlists/') && !seen.add(id)) {
          throw StateError('Plex 分页出现重复曲目，已保留旧索引');
        }
      }
      final total = (data['totalSize'] as num?)?.toInt();
      if (total != null && offset + page.length > total) {
        throw StateError('Plex 分页数量不一致，已保留旧索引');
      }
      yield page;
      offset += page.length;
      if (total != null && offset >= total) break;
      if (total == null && page.length < 250) break;
      if (offset > 1000000) throw StateError('Plex 分页超过安全限制');
    }
  }

  Track _toTrack(Map<String, dynamic> item) {
    final media = _entries(item, 'Media').firstOrNull;
    final part = media == null ? null : _entries(media, 'Part').firstOrNull;
    final id = item['ratingKey']?.toString() ?? '';
    if (id.isEmpty) throw StateError('Plex 曲目缺少 ratingKey');
    final thumb = _safeRelativeKey(item['thumb']);
    final parentThumb = _safeRelativeKey(item['parentThumb']);
    final cover = thumb.isNotEmpty ? thumb : parentThumb;
    final partKey = _safeRelativeKey(part?['key']);
    return Track(
      ref: TrackRef(profile.id, id),
      title: item['title']?.toString() ?? '',
      artist: item['grandparentTitle']?.toString() ?? '未知艺术家',
      album: item['parentTitle']?.toString() ?? '',
      albumArtist: item['grandparentTitle']?.toString() ?? '',
      durationMs: (item['duration'] as num?)?.round() ?? 0,
      year: (item['year'] as num?)?.toInt() ?? 0,
      disc: (item['parentIndex'] as num?)?.toInt() ?? 0,
      number: (item['index'] as num?)?.toInt() ?? 0,
      coverId: cover,
      remote: {
        'plexPartKey': partKey,
        'size': part?['size'],
        'changed': item['updatedAt'],
        'contentType': part?['container'] ?? media?['container'],
        'coverPath': cover,
        'coverUpdatedAt': item['updatedAt'],
        'thumb': thumb,
        'parentThumb': parentThumb,
        'grandparentThumb': _safeRelativeKey(item['grandparentThumb']),
        'grandparentRatingKey': item['grandparentRatingKey'],
      },
    );
  }

  @override
  Stream<List<Track>> libraryPages() async* {
    final sections = _entries(
      await _container('library/sections'),
      'Directory',
    );
    final music = sections.where((section) => section['type'] == 'artist');
    for (final section in music) {
      final id = section['key']?.toString();
      if (id == null || id.isEmpty || !RegExp(r'^\d+$').hasMatch(id)) {
        throw StateError('Plex 音乐库缺少有效 Section ID');
      }
      await for (final page in _pages(
        'library/sections/$id/all',
        query: {'type': '10'},
      )) {
        if (page.any((item) => item['type'] != 'track')) {
          throw StateError('Plex 音乐库返回非歌曲条目，已保留旧索引');
        }
        yield page.map(_toTrack).toList();
      }
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
    await for (final page in _pages(
      'playlists',
      query: {'playlistType': 'audio'},
    )) {
      for (final item in page) {
        final id = item['ratingKey']?.toString();
        if (id == null || id.isEmpty) continue;
        result.add(
          RemotePlaylist(
            id: id,
            name: item['title']?.toString() ?? '未命名',
            tracks: const [],
            readonly: true,
          ),
        );
      }
    }
    return result;
  }

  @override
  Future<RemotePlaylist> fetchPlaylist(String id) async {
    final playlists = await fetchPlaylists();
    final meta = playlists.where((item) => item.id == id).firstOrNull;
    if (meta == null) throw StateError('Plex 歌单不存在或无权限');
    final keys = <String>[];
    final entryIds = <String>[];
    await for (final page in _pages(
      'playlists/${Uri.encodeComponent(id)}/items',
    )) {
      for (final item in page) {
        final ratingKey = item['ratingKey']?.toString();
        if (ratingKey == null || ratingKey.isEmpty) continue;
        keys.add(TrackRef(profile.id, ratingKey).key);
        entryIds.add(item['playlistItemID']?.toString() ?? '');
      }
    }
    return RemotePlaylist(
      id: id,
      name: meta.name,
      tracks: keys,
      entryIds: entryIds,
      readonly: true,
    );
  }

  @override
  Future<RemotePlaylist> createPlaylist(String name) async =>
      throw UnsupportedError('Plex 歌单写入暂未开放');

  @override
  Future<void> mutatePlaylist(
    RemotePlaylist before,
    List<String> desired,
  ) async => throw UnsupportedError('Plex 歌单写入暂未开放');

  @override
  Future<void> deletePlaylist(String id) async =>
      throw UnsupportedError('Plex 歌单写入暂未开放');

  /// Reject external and token-bearing keys before persisting source metadata.
  String _safeRelativeKey(Object? key) {
    final text = key?.toString() ?? '';
    if (text.isEmpty) return '';
    try {
      _resourceUrl(text);
      return text;
    } on StateError {
      return '';
    }
  }

  /// Only accept server-relative resource keys; never forward tokens to other hosts.
  Uri _resourceUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.hasAuthority ||
        uri.scheme.isNotEmpty ||
        uri.hasFragment ||
        uri.pathSegments.any((segment) => segment == '..') ||
        uri.queryParameters.keys.any(
          (name) =>
              name.toLowerCase().contains('token') ||
              name.toLowerCase().contains('auth'),
        ) ||
        uri.path.isEmpty) {
      throw StateError('Plex 返回了不安全的资源地址');
    }
    return appendPath(
      profile,
      uri.path.replaceFirst(RegExp(r'^/'), ''),
      uri.queryParameters.isEmpty ? null : uri.queryParameters,
    );
  }

  @override
  Future<Uri> mediaUrl(Track track) async {
    var partKey = track.remote['plexPartKey']?.toString() ?? '';
    if (partKey.isEmpty) {
      final data = await _container(
        'library/metadata/${Uri.encodeComponent(track.ref.id)}',
      );
      final item = _entries(data, 'Metadata').firstOrNull;
      if (item != null) {
        final media = _entries(item, 'Media').firstOrNull;
        if (media != null) {
          partKey =
              _entries(media, 'Part').firstOrNull?['key']?.toString() ?? '';
        }
      }
    }
    if (partKey.isEmpty) throw UnsupportedError('Plex 曲目没有可直连的音频 Part');
    return _resourceUrl(partKey);
  }

  @override
  Future<Map<String, String>> mediaHeaders() => _headers();

  @override
  Future<List<Uri>> coverUrls(Track track) async {
    final urls = <Uri>[];
    for (final candidate in [
      track.remote['thumb'],
      track.remote['parentThumb'],
    ]) {
      final path = candidate?.toString() ?? '';
      if (path.isEmpty) continue;
      try {
        final uri = _resourceUrl(path);
        if (!urls.contains(uri)) urls.add(uri);
      } on StateError {
        // Plex can provide external artwork URLs; never send credentials there.
      }
    }
    return urls;
  }

  @override
  Future<Uri?> coverUrl(Track track) async =>
      (await coverUrls(track)).firstOrNull;

  @override
  Future<String?> lyrics(Track track) async => null;

  @override
  void close() => transport.close();
}
