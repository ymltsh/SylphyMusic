import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/services/sources.dart';

import 'live_emby_test.dart' show MemoryVault;
import 'media_proxy_test.dart' show NetworkTestBinding;

void main() {
  NetworkTestBinding();
  late HttpServer server;
  late EmbyAdapter adapter;
  var codec = 'text', status = 200;
  var legacy = false;
  final paths = <String>[];
  const track = Track(
    ref: TrackRef('s', 'song'),
    title: '',
    artist: '',
    album: '',
  );
  setUp(() async {
    codec = 'text';
    status = 200;
    legacy = false;
    paths.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      paths.add(r.uri.path);
      expect(r.headers.value('X-Emby-Token'), 'fixture-token');
      if (r.uri.path == '/prefix/Users/u/Items/song') {
        r.response.write(
          jsonEncode({
            'MediaSources': [
              {
                'Id': 'media',
                'MediaStreams': [
                  {'Type': 'Audio', 'Index': 0},
                  {
                    'Type': 'Subtitle',
                    'Codec': codec,
                    'Index': 2,
                    'IsExternal': codec == 'lrc',
                  },
                ],
              },
            ],
          }),
        );
      } else {
        r.response.statusCode =
            legacy && r.uri.path.startsWith('/prefix/Items/') ? 404 : status;
        r.response.add(utf8.encode('\uFEFF[00:01.20]测试歌词\n[00:03.00]第二行'));
      }
      await r.response.close();
    });
    final vault = MemoryVault();
    await vault.write('s', 'token', 'fixture-token');
    await vault.write('s', 'userId', 'u');
    adapter = EmbyAdapter(
      SourceProfile(
        id: 's',
        name: 'fixture',
        kind: SourceKind.emby,
        url: 'http://127.0.0.1:${server.port}/prefix',
        username: 'fixture',
      ),
      vault,
    );
  });
  tearDown(() async {
    adapter.close();
    await server.close(force: true);
  });
  test('embedded text lyrics use txt, retain UTF-8 timestamps and refresh stale metadata', () async {
    expect(await adapter.lyrics(track), '[00:01.20]测试歌词\n[00:03.00]第二行');
    expect(paths.last, '/prefix/Items/song/media/Subtitles/2/Stream.txt');
  });
  test('external LRC uses its own format and supports legacy route', () async {
    codec = 'lrc';
    legacy = true;
    expect(await adapter.lyrics(track), contains('[00:03.00]'));
    expect(paths.last, '/prefix/Videos/song/media/Subtitles/2/Stream.lrc');
  });
  test('missing lyric stream performs no audio download', () async {
    codec = 'unsupported';
    expect(await adapter.lyrics(track), isNull);
    expect(paths.length, 1);
  });
  test('permission errors remain errors and can be retried', () async {
    status = 403;
    await expectLater(adapter.lyrics(track), throwsA(isA<HttpFailure>()));
    status = 200;
    expect(await adapter.lyrics(track), isNotEmpty);
  });
}
