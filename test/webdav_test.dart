import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/services/sources.dart';

import 'live_emby_test.dart' show MemoryVault;
import 'media_proxy_test.dart' show NetworkTestBinding;

String davRow(String href, {bool directory = false, int status = 200}) =>
    '<D:response><D:href>${const HtmlEscape().convert(href)}</D:href><D:propstat><D:prop>'
    '<D:resourcetype>${directory ? '<D:collection/>' : ''}</D:resourcetype>'
    '<D:getcontentlength>10240</D:getcontentlength><D:getetag>"v1"</D:getetag>'
    '<D:getlastmodified>Mon, 26 Oct 2026 00:00:00 GMT</D:getlastmodified>'
    '</D:prop><D:status>HTTP/1.1 $status Fixture</D:status></D:propstat></D:response>';
String davXml(List<String> rows) =>
    '<D:multistatus xmlns:D="DAV:">${rows.join()}</D:multistatus>';

void main() {
  NetworkTestBinding();
  late HttpServer server;
  late WebDavAdapter adapter;
  late MemoryVault vault;
  final requests = <String>[];
  var mode = 'normal';
  setUp(() async {
    mode = 'normal';
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      requests.add('${r.method} ${r.uri.path}');
      expect(
        r.headers.value('Authorization'),
        'Basic ${base64Encode(utf8.encode('user:secret'))}',
      );
      if (r.method == 'PROPFIND') {
        expect(r.headers.value('Depth'), '1');
        expect(await utf8.decoder.bind(r).join(), contains('propfind'));
        if (mode == 'unauthorized') {
          r.response.statusCode = 401;
        } else if (mode == 'malformed') {
          r.response.statusCode = 207;
          r.response.write('<not-dav/>');
        } else if (mode == 'redirect') {
          r.response.statusCode = 302;
          r.response.headers.set('Location', 'http://127.0.0.1:1/steal');
        } else {
          r.response.statusCode = 207;
          if (r.uri.path == '/dav/') {
            r.response.write(
              davXml([
                davRow('/dav/', directory: true),
                davRow('/dav/Artist/', directory: true),
                davRow('https://foreign.invalid/secret.mp3'),
                davRow('/outside/secret.mp3'),
                davRow('/dav/../outside/'),
              ]),
            );
          } else if (r.uri.path == '/dav/Artist/') {
            r.response.write(
              davXml([
                davRow('/dav/Artist/', directory: true),
                davRow('/dav/Artist/Album%20%E4%B8%AD', directory: true),
              ]),
            );
          } else {
            final dir = '/dav/Artist/Album%20%E4%B8%AD/';
            r.response.write(
              davXml([
                davRow(dir, directory: true),
                for (var i = 0; i < (mode == 'large' ? 503 : 1); i++)
                  davRow(
                    '$dir${i == 0 ? '%E6%AD%8C%20%23%25%26' : '$i'}.flac',
                    status: mode == 'denied' ? 403 : 200,
                  ),
                davRow('$dir%E6%AD%8C%20%23%25%26.LRC'),
                davRow('${dir}cover.jpg'),
              ]),
            );
          }
        }
      } else {
        r.response.add(utf8.encode('[00:01.00]测试'));
      }
      await r.response.close();
    });
    vault = MemoryVault();
    adapter = WebDavAdapter(
      SourceProfile(
        id: 'dav',
        name: 'fixture',
        kind: SourceKind.webdav,
        url: 'http://127.0.0.1:${server.port}/dav',
        username: 'user',
      ),
      vault,
    );
  });
  tearDown(() async {
    adapter.close();
    await server.close(force: true);
  });
  test(
    'recursive scan, encoded paths, filename groups, sidecar cover and lyrics',
    () async {
      await adapter.login('secret');
      final tracks = await adapter.fetchLibrary();
      expect(tracks.length, 1);
      final t = tracks.single;
      expect(t.title, '歌 #%&');
      expect(t.album, 'Album 中');
      expect(t.artist, 'Artist');
      final url = await adapter.mediaUrl(t);
      expect(url.pathSegments.last, '歌 #%&.flac');
      expect(url.hasQuery, false);
      expect(url.hasFragment, false);
      expect((await adapter.coverUrl(t))!.pathSegments.last, 'cover.jpg');
      expect(await adapter.lyrics(t), '[00:01.00]测试');
      expect(
        t.remote.values.any((v) => v.toString().contains('secret')),
        false,
      );
      expect(
        requests.any((s) => s.contains('outside') || s.contains('foreign')),
        false,
      );
    },
  );
  test(
    'large directory yields bounded pages without duplicating tracks',
    () async {
      mode = 'large';
      await adapter.login('secret');
      final pages = await adapter.libraryPages().toList();
      expect(pages.map((p) => p.length), [250, 250, 3]);
    },
  );
  test('auth validation, malformed XML and denied child fail rather than empty snapshot', () async {
    mode = 'unauthorized';
    await expectLater(adapter.login('secret'), throwsA(isA<HttpFailure>()));
    expect(await vault.read('dav', 'password'), isNull);
    mode = 'normal';
    await adapter.login('secret');
    mode = 'malformed';
    await expectLater(adapter.fetchLibrary(), throwsStateError);
    mode = 'denied';
    await expectLater(adapter.fetchLibrary(), throwsStateError);
    mode = 'unauthorized';
    await expectLater(
      adapter.validateConnection(),
      throwsA(isA<HttpFailure>()),
    );
  });
  test('rejects redirect and unsafe persisted resource paths', () async {
    mode = 'redirect';
    await expectLater(adapter.login('secret'), throwsStateError);
    for (final id in [
      '../escape.mp3',
      '/outside.mp3',
      'https://foreign.invalid/x.mp3',
      'x%2Fy.mp3',
      'song.mp3?token=bad',
    ]) {
      await expectLater(
        adapter.mediaUrl(
          Track(ref: TrackRef('dav', id), title: '', artist: '', album: ''),
        ),
        throwsStateError,
      );
    }
  });
  test('WebDAV exposes no server playlist mutations', () async {
    expect(await adapter.fetchPlaylists(), isEmpty);
    await expectLater(adapter.createPlaylist('test'), throwsUnsupportedError);
  });
}
