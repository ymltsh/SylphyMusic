part of 'sources.dart';

class _DavEntry {
  const _DavEntry(this.uri, this.properties, this.directory);
  final Uri uri;
  final Map<String, String> properties;
  final bool directory;
}

/// Directory choice returned by a read-only WebDAV PROPFIND.
class WebDavDirectory {
  const WebDavDirectory(this.path, this.name);

  /// Percent-encoded path relative to the WebDAV URL.
  final String path;
  final String name;
}

/// Read-only WebDAV source. All hrefs stay inside the configured collection;
/// credentials never occur in URLs or in persisted track metadata.
class WebDavAdapter extends MusicAdapter {
  WebDavAdapter(super.profile, this.vault);
  final AuthVault vault;
  final StrictTransport transport = StrictTransport();
  Uri get _root => appendPath(profile, '');

  Uri _directory(String relativePath) {
    if (relativePath.isEmpty) return _root;
    final relative = Uri.parse(relativePath);
    if (relative.hasScheme ||
        relative.hasAuthority ||
        relative.hasQuery ||
        relative.hasFragment ||
        relative.path.startsWith('/') ||
        relative.pathSegments.any(
          (s) =>
              s.isEmpty ||
              s == '.' ||
              s == '..' ||
              s.contains('/') ||
              s.contains('\\'),
        )) {
      throw const FormatException('无效的 WebDAV 基础目录');
    }
    final uri = _root.resolve(
      Uri(pathSegments: [...relative.pathSegments, '']).toString(),
    );
    if (!_inside(uri)) throw const FormatException('WebDAV 目录超出服务器根路径');
    return uri;
  }

  Uri get _scanRoot => _directory(profile.webdavBasePath);
  static const _propfind = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/><d:getetag/><d:getcontenttype/></d:prop></d:propfind>''';

  Future<Map<String, String>> _headers([String? password]) async {
    final secret = password ?? await vault.read(profile.id, 'password');
    if (secret == null) throw StateError('缺少 WebDAV 密码，请重新登录');
    if (profile.username.contains(':')) {
      throw const FormatException('WebDAV 用户名不能包含冒号');
    }
    return {
      'Authorization':
          'Basic ${base64Encode(utf8.encode('${profile.username}:$secret'))}',
    };
  }

  bool _inside(Uri uri) {
    final root = _root;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final prefix = root.pathSegments.where((s) => s.isNotEmpty).toList();
    return uri.origin == root.origin &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        segments.length >= prefix.length &&
        !segments.any(
          (s) => s == '.' || s == '..' || s.contains('/') || s.contains('\\'),
        ) &&
        List.generate(
          prefix.length,
          (i) => segments[i] == prefix[i],
        ).every((x) => x);
  }

  String _id(Uri uri) => Uri(
    pathSegments: uri.pathSegments
        .skip(_root.pathSegments.where((s) => s.isNotEmpty).length)
        .where((s) => s.isNotEmpty),
  ).toString();

  Uri _uri(String id) {
    final uri = _root.resolve(id);
    if (!_inside(uri) || id.isEmpty || id.startsWith('/')) {
      throw StateError('无效 WebDAV 资源路径');
    }
    return uri;
  }

  Iterable<XmlElement> _children(XmlElement element, String local) => element
      .childElements
      .where((e) => e.name.local == local && e.namespaceUri == 'DAV:');

  Future<List<_DavEntry>> _list(Uri directory, {String? password}) async {
    final response = await transport.request(
      'PROPFIND',
      directory,
      headers: {
        ...await _headers(password),
        'Depth': '1',
        'Content-Type': 'application/xml; charset=utf-8',
      },
      body: _propfind,
      retrySafe: true,
    );
    if (response.statusCode != 207) throw StateError('服务器未返回 WebDAV 多状态目录');
    if (response.bodyBytes.length > 16 * 1024 * 1024) {
      throw StateError('WebDAV 单目录过大，请拆分音乐目录');
    }
    final xml = XmlDocument.parse(utf8.decode(response.bodyBytes));
    if (xml.rootElement.name.local != 'multistatus' ||
        xml.rootElement.namespaceUri != 'DAV:') {
      throw StateError('无效 WebDAV 目录响应');
    }
    final result = <_DavEntry>[];
    for (final row in _children(xml.rootElement, 'response')) {
      final href = _children(row, 'href').firstOrNull?.innerText.trim();
      if (href == null || href.isEmpty) throw StateError('WebDAV 目录缺少资源路径');
      final uri = directory.resolve(href);
      if (!_inside(uri)) continue;
      final status = _children(row, 'status').firstOrNull?.innerText;
      if (status != null &&
          !RegExp(r'^HTTP/\S+ 2\d\d(?: |$)').hasMatch(status)) {
        throw StateError('WebDAV 子目录或资源不可读取，已保留旧索引');
      }
      final props = <String, String>{};
      var valid = false, collection = false;
      for (final stat in _children(row, 'propstat')) {
        final status = _children(stat, 'status').firstOrNull?.innerText ?? '';
        if (!RegExp(r'^HTTP/\S+ 2\d\d(?: |$)').hasMatch(status)) continue;
        final prop = _children(stat, 'prop').firstOrNull;
        if (prop == null) continue;
        valid = true;
        for (final value in prop.childElements.where(
          (e) => e.namespaceUri == 'DAV:',
        )) {
          props[value.name.local] = value.innerText;
          if (value.name.local == 'resourcetype') {
            collection = _children(value, 'collection').isNotEmpty;
          }
        }
      }
      if (!valid || !props.containsKey('resourcetype')) {
        throw StateError('WebDAV 目录属性不完整，已保留旧索引');
      }
      result.add(_DavEntry(uri, props, collection));
    }
    // A successful empty multistatus is often a broken auth/proxy response.
    if (!result.any(
      (entry) => entry.directory && _id(entry.uri) == _id(directory),
    )) {
      throw StateError('WebDAV 未返回目录自身信息，请检查音乐目录地址');
    }
    return result;
  }

  /// Browse one level at a time. Never stores the password or downloads files.
  Future<List<WebDavDirectory>> listDirectories(
    String path, {
    String? password,
  }) async {
    final directory = _directory(path);
    final entries = await _list(directory, password: password);
    final depth = directory.pathSegments.where((s) => s.isNotEmpty).length;
    return entries
        .where(
          (e) =>
              e.directory &&
              e.uri.pathSegments.where((s) => s.isNotEmpty).length == depth + 1,
        )
        .map(
          (e) => WebDavDirectory(
            _id(e.uri),
            e.uri.pathSegments.where((s) => s.isNotEmpty).last,
          ),
        )
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  Future<void> login(String password) async {
    await _list(_scanRoot, password: password);
    await vault.write(profile.id, 'password', password);
  }

  @override
  Future<void> validateConnection() async {
    await _list(_scanRoot);
  }

  @override
  Future<List<Track>> fetchLibrary() async => [
    await for (final page in libraryPages()) ...page,
  ];

  @override
  Stream<List<Track>> libraryPages() async* {
    final pending = <(Uri, int)>[(_scanRoot, 0)];
    final visited = <String>{}, seenTracks = <String>{};
    var page = <Track>[];
    while (pending.isNotEmpty) {
      final (directory, level) = pending.removeLast();
      final dirId = _id(directory);
      if (!visited.add(dirId)) continue;
      if (visited.length > 100000) throw StateError('WebDAV 目录数量过多，已停止扫描');
      final entries = await _list(directory);
      final depth = directory.pathSegments.where((s) => s.isNotEmpty).length;
      final children = entries
          .where(
            (e) =>
                e.uri.pathSegments.where((s) => s.isNotEmpty).length ==
                depth + 1,
          )
          .toList();
      final files = {
        for (final e in children.where((e) => !e.directory))
          e.uri.pathSegments.last.toLowerCase(): e,
      };
      for (final entry in children) {
        if (entry.directory) {
          if (profile.webdavMaxDepth < 0 || level < profile.webdavMaxDepth) {
            pending.add((
              entry.uri.path.endsWith('/')
                  ? entry.uri
                  : entry.uri.replace(
                      pathSegments: [...entry.uri.pathSegments, ''],
                    ),
              level + 1,
            ));
          }
          continue;
        }
        final name = entry.uri.pathSegments.last;
        final dot = name.lastIndexOf('.');
        if (dot < 0 ||
            !audioExtensions.contains(name.substring(dot).toLowerCase())) {
          continue;
        }
        final id = _id(entry.uri);
        if (!seenTracks.add(id)) continue;
        final stem = name.substring(0, dot);
        final lyric =
            files['${stem.toLowerCase()}.lrc'] ??
            files['${stem.toLowerCase()}.txt'];
        final cover = [
          '${stem.toLowerCase()}.jpg',
          '${stem.toLowerCase()}.png',
          'cover.jpg',
          'cover.png',
          'folder.jpg',
          'folder.png',
          'front.jpg',
          'front.png',
          'cover.webp',
        ].map((name) => files[name]).whereType<_DavEntry>().firstOrNull;
        final relative = Uri.parse(id).pathSegments;
        page.add(
          Track(
            ref: TrackRef(profile.id, id),
            title: stem,
            artist: relative.length >= 3
                ? relative[relative.length - 3]
                : '未知艺术家',
            album: relative.length >= 2
                ? relative[relative.length - 2]
                : '未知专辑',
            coverId: cover == null ? '' : _id(cover.uri),
            remote: {
              'size': int.tryParse(entry.properties['getcontentlength'] ?? ''),
              'DateModified': entry.properties['getlastmodified'],
              'etag': entry.properties['getetag'],
              'format': name.substring(dot + 1).toUpperCase(),
              if (lyric != null) 'lyricsId': _id(lyric.uri),
            },
          ),
        );
        if (page.length == 250) {
          yield page;
          page = [];
        }
      }
    }
    if (page.isNotEmpty) yield page;
  }

  @override
  Future<Uri> mediaUrl(Track track) async => _uri(track.ref.id);
  @override
  Future<Map<String, String>> mediaHeaders() => _headers();
  @override
  Future<Uri?> coverUrl(Track track) async =>
      track.coverId.isEmpty ? null : _uri(track.coverId);
  @override
  Future<String?> lyrics(Track track) async {
    final known = track.remote['lyricsId']?.toString();
    final id = track.ref.id;
    final dot = id.lastIndexOf('.');
    final candidates = known != null
        ? [known]
        : dot < 0
        ? <String>[]
        : ['${id.substring(0, dot)}.lrc', '${id.substring(0, dot)}.txt'];
    for (final candidate in candidates) {
      try {
        final response = await transport.request(
          'GET',
          _uri(candidate),
          headers: await _headers(),
          retrySafe: true,
        );
        if (response.bodyBytes.length > 1024 * 1024) {
          throw StateError('服务器歌词超过 1 MiB');
        }
        final text = utf8
            .decode(response.bodyBytes)
            .replaceFirst('\uFEFF', '')
            .trim();
        if (text.isNotEmpty) return text;
      } on HttpFailure catch (e) {
        if (e.status != 404) rethrow;
      }
    }
    return null;
  }

  @override
  Future<List<RemotePlaylist>> fetchPlaylists() async => [];
  Never _noPlaylist() => throw UnsupportedError('WebDAV 使用本地歌单');
  @override
  Future<RemotePlaylist> fetchPlaylist(String id) async => _noPlaylist();
  @override
  Future<RemotePlaylist> createPlaylist(String name) async => _noPlaylist();
  @override
  Future<void> mutatePlaylist(
    RemotePlaylist before,
    List<String> desired,
  ) async => _noPlaylist();
  @override
  Future<void> deletePlaylist(String id) async => _noPlaylist();
  @override
  void close() => transport.close();
}
