import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/services/sources.dart';
import 'package:sylphy_music/services/lyrics.dart';

import 'live_emby_test.dart' show MemoryVault;
import 'media_proxy_test.dart' show NetworkTestBinding;

void main() {
  NetworkTestBinding();
  late HttpServer server;
  late EmbyAdapter adapter;
  var codec = 'text', status = 200;
  var legacy = false;
  var plainOnly = false;
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
    plainOnly = false;
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
            (legacy && r.uri.path.startsWith('/prefix/Items/')) ||
                (plainOnly && r.uri.path.endsWith('.srt'))
            ? 404
            : status;
        r.response.add(
          utf8.encode(
            r.uri.path.endsWith('.srt')
                ? '\uFEFF1\n00:00:01,200 --> 00:00:03,000\n测试歌词\n\n2\n00:00:03,000 --> 00:00:04,000\n第二行\n'
                : plainOnly
                ? '没有时间轴的歌词'
                : '\uFEFF[00:01.20]测试歌词\n[00:03.00]第二行',
          ),
        );
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
  test('embedded text lyrics request timed SRT instead of stripping the timeline via txt', () async {
    final text = await adapter.lyrics(track);
    expect(text, '[00:01.200]测试歌词\n[00:03.000]第二行\n[00:04.000]');
    expect(paths.last, '/prefix/Items/song/media/Subtitles/2/Stream.srt');
    expect(activeLrcIndex(parseLrc(text!), const Duration(seconds: 2)), 0);
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
  test('servers without timed conversion retain plain text and never download audio', () async {
    plainOnly = true;
    expect(await adapter.lyrics(track), '没有时间轴的歌词');
    expect(paths, [
      '/prefix/Users/u/Items/song',
      '/prefix/Items/song/media/Subtitles/2/Stream.srt',
      '/prefix/Videos/song/media/Subtitles/2/Stream.srt',
      '/prefix/Items/song/media/Subtitles/2/Stream.txt',
    ]);
  });
  test('SubRip streams also retain their clock values', () async {
    codec = 'subrip';
    final lines = parseLrc((await adapter.lyrics(track))!);
    expect(lines.first.at.inMilliseconds, 1200);
    expect(lines[1].at.inMilliseconds, 3000);
  });
}
