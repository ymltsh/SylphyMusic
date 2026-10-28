import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:sylphy_music/core/app_controller.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/services/lyrics.dart';
import 'package:sylphy_music/services/sources.dart' show HttpFailure;

import 'live_emby_test.dart' show MemoryVault;
import 'media_proxy_test.dart' show NetworkTestBinding;

void main() {
  NetworkTestBinding();
  final library =
      Platform.environment['SYLPHY_MPV_LIBRARY'] ??
      'build/windows/x64/runner/Debug/libmpv-2.dll';
  final available = File(library).existsSync();
  late Directory root;
  late SylphyApp app;
  late HttpServer server;
  var hits = 0, status = 200;
  var plainOnly = false;
  var lrcHits = 0, lrcStatus = 200;
  const track = Track(
    ref: TrackRef('fixture', 'song'),
    title: 'Synthetic song',
    artist: '',
    album: '',
  );
  File legacy() => File(
    '${root.path}/lyrics/${sha256.convert(utf8.encode(track.ref.sourceId))}/${sha256.convert(utf8.encode(track.ref.key))}.lrc',
  );
  setUp(() async {
    if (!available) return;
    MediaKit.ensureInitialized(libmpv: File(library).absolute.path);
    root = await Directory.systemTemp.createTemp('sylphy-lyric-cache-');
    hits = 0;
    status = 200;
    plainOnly = false;
    lrcHits = 0;
    lrcStatus = 200;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      if (r.uri.path == '/lyrics') {
        lrcHits++;
        r.response.statusCode = lrcStatus;
        r.response.write('[00:02.00]Supplement');
        await r.response.close();
        return;
      }
      hits++;
      r.response.statusCode = status;
      if (r.uri.path.endsWith('/Users/u/Items/song')) {
        r.response.write(
          jsonEncode({
            'MediaSources': [
              {
                'Id': 'media',
                'MediaStreams': [
                  {
                    'Index': 2,
                    'Type': 'Subtitle',
                    'Codec': 'text',
                    'IsTextSubtitleStream': true,
                  },
                ],
              },
            ],
          }),
        );
      } else if (r.uri.path.endsWith('.srt')) {
        if (plainOnly) {
          r.response.statusCode = 404;
        } else {
          r.response.write('1\n00:00:01,250 --> 00:00:03,000\nTimed line\n');
        }
      } else {
        r.response.write('Plain server text');
      }
      await r.response.close();
    });
    final vault = MemoryVault();
    await vault.write('fixture', 'userId', 'u');
    await vault.write('fixture', 'token', 'fixture-token');
    app = await SylphyApp.bootstrap(
      dataRoot: root,
      credentialVault: vault,
      resumeBackground: false,
      platformIntegration: false,
    );
    await app.db.putSource(
      SourceProfile(
        id: 'fixture',
        name: 'fixture',
        kind: SourceKind.emby,
        url: 'http://127.0.0.1:${server.port}/prefix',
        username: 'fixture',
      ),
    );
  });
  tearDown(() async {
    if (!available) return;
    await app.disposeAsync();
    await server.close(force: true);
    await root.delete(recursive: true);
  });
  group('Emby lyric cache upgrade', () {
    test(
      'restored track caches lyrics without opening a lyrics widget',
      () async {
        await app.db.replaceSourceTracks('fixture', [track]);
        app.playback.snapshot = QueueSnapshot(
          tracks: [track.ref.key],
          order: const [0],
        );
        final vault = app.vault;
        await app.disposeAsync();
        app = await SylphyApp.bootstrap(
          dataRoot: root,
          credentialVault: vault,
          resumeBackground: false,
          platformIntegration: false,
        );
        var cached = await app.assets.read('fixture', app.lyrics.key(track));
        for (var i = 0; i < 200 && cached == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          cached = await app.assets.read('fixture', app.lyrics.key(track));
        }
        expect(cached, isNotNull);
        expect(await cached!.file.readAsString(), contains('Timed line'));
        expect(hits, greaterThan(0));
        expect(app.playback.currentRef, track.ref);
        expect(app.playback.playing, isFalse);
      },
    );

    test(
      'online fallback is opt in, source lyrics win and cache works offline',
      () async {
        await app.apiSettings.setLrcApiUrl(
          'http://127.0.0.1:${server.port}/lyrics',
        );
        status = 403;
        await expectLater(app.loadLyrics(track), throwsA(isA<HttpFailure>()));
        expect(lrcHits, 0);
        await app.apiSettings.setLrcApiEnabled(true);
        expect(
          await app.loadLyrics(track, forceRefresh: true),
          '[00:02.00]Supplement',
        );
        expect(lrcHits, 1);
        status = 503;
        final before = hits;
        expect(await app.loadLyrics(track), '[00:02.00]Supplement');
        expect(hits, before);
        expect(lrcHits, 1);
        status = 200;
        expect(
          await app.loadLyrics(track, forceRefresh: true),
          contains('Timed line'),
        );
        expect(lrcHits, 1);
      },
    );

    test(
      'local lyrics precede fallback and empty local lyrics use it',
      () async {
        await app.apiSettings.setLrcApiUrl(
          'http://127.0.0.1:${server.port}/lyrics',
        );
        await app.apiSettings.setLrcApiEnabled(true);
        await app.db.putSource(
          const SourceProfile(
            id: 'local',
            name: 'local',
            kind: SourceKind.local,
            url: 'file:///',
            username: '',
          ),
        );
        final audio = File('${root.path}/local.wav');
        final local = Track(
          ref: TrackRef('local', audio.path),
          title: 'Synthetic',
          artist: '',
          album: '',
        );
        expect(await app.loadLyrics(local), '[00:02.00]Supplement');
        expect(lrcHits, 1);
        await File('${root.path}/local.lrc').writeAsString('[00:01]Local');
        expect(await app.loadLyrics(local), '[00:01]Local');
        expect(lrcHits, 1);
      },
    );

    test('failed supplement preserves the primary error', () async {
      await app.apiSettings.setLrcApiUrl(
        'http://127.0.0.1:${server.port}/lyrics',
      );
      await app.apiSettings.setLrcApiEnabled(true);
      status = 403;
      lrcStatus = 503;
      await expectLater(app.loadLyrics(track), throwsA(isA<HttpFailure>()));
      expect(lrcHits, 1);
    });

    test(
      'cached reversed SRT normalizes offline while manual imports stay intact',
      () async {
        const subtitle = '1\n00:00:05,000 --> 00:00:00,000\nInstrumental';
        await app.assets.put(
          track.ref.sourceId,
          app.lyrics.key(track),
          'lyrics',
          track.resourceVersion,
          utf8.encode(subtitle),
          ttl: const Duration(hours: 6),
        );
        status = 503;
        expect(await app.loadLyrics(track), '[00:05.000]Instrumental');
        expect(hits, 0);
        final cached = await app.assets.read(
          track.ref.sourceId,
          app.lyrics.key(track),
        );
        expect(await cached!.file.readAsString(), subtitle);
        final manual = await File('${root.path}/manual.srt')
            .writeAsString(subtitle);
        await app.importLyricsFile(track, manual);
        expect(await app.loadLyrics(track), subtitle);
        expect(hits, 0);
      },
    );

    test('cleared migrated lyrics are not silently reimported from the recovery copy', () async {
      await legacy().parent.create(recursive: true);
      await legacy().writeAsString('[00:01.00]Recovery copy');
      expect(await app.loadLyrics(track), '[00:01.00]Recovery copy');
      await app.assets.clear();
      status = 403;
      await expectLater(app.loadLyrics(track), throwsA(isA<HttpFailure>()));
      expect(await legacy().exists(), true);
    });
    test(
      'plain lyrics remain a fresh local hit until a deliberate refresh',
      () async {
        plainOnly = true;
        expect(await app.loadLyrics(track), 'Plain server text');
        final before = hits;
        expect(await app.loadLyrics(track), 'Plain server text');
        expect(hits, before);
        plainOnly = false;
        expect(
          parseLrc((await app.loadLyrics(track, forceRefresh: true))!),
          isNotEmpty,
        );
      },
    );
    test('concurrent requests share one metadata and subtitle fetch', () async {
      final texts = await Future.wait(
        List.generate(12, (_) => app.loadLyrics(track)),
      );
      expect(texts.toSet().length, 1);
      expect(hits, 2);
    });
    test(
      'closing and reopening the application preserves offline lyrics',
      () async {
        final text = await app.loadLyrics(track), vault = app.vault;
        await app.disposeAsync();
        status = 503;
        final before = hits;
        app = await SylphyApp.bootstrap(
          dataRoot: root,
          credentialVault: vault,
          resumeBackground: false,
          platformIntegration: false,
        );
        expect(await app.loadLyrics(track), text);
        expect(hits, before);
      },
    );
    test('ordinary metadata cleanup leaves manual lyrics intact', () async {
      await app.loadLyrics(track);
      final file = await File('${root.path}/manual.txt')
          .writeAsString('My own lyrics');
      await app.importLyricsFile(track, file);
      await app.assets.clear();
      final before = hits;
      expect(await app.loadLyrics(track), 'My own lyrics');
      expect(hits, before);
    });
    test('legacy plain cache refreshes into timed lyrics without deleting the old bytes', () async {
      await legacy().parent.create(recursive: true);
      await legacy().writeAsString('Legacy plain lyrics');
      final text = await app.loadLyrics(track, forceRefresh: true);
      expect(parseLrc(text!).first.at.inMilliseconds, 1250);
      expect(await legacy().readAsString(), 'Legacy plain lyrics');
      final before = hits;
      expect(await app.loadLyrics(track), text);
      expect(hits, before);
    });
    test(
      'manual imports remain higher priority than upgraded remote lyrics',
      () async {
        await app.loadLyrics(track);
        final original = await File('${root.path}/manual.txt')
            .writeAsString('My manual lyrics');
        await app.importLyricsFile(track, original);
        final before = hits;
        expect(await app.loadLyrics(track), 'My manual lyrics');
        expect(hits, before);
        expect(await original.readAsString(), 'My manual lyrics');
      },
    );
    test(
      'legacy text is preserved as the offline fallback when refresh fails',
      () async {
        await legacy().parent.create(recursive: true);
        await legacy().writeAsString('Legacy offline text');
        status = 403;
        expect(await app.loadLyrics(track), 'Legacy offline text');
        expect(await legacy().readAsString(), 'Legacy offline text');
      },
    );
    test(
      'plain fallback is rechecked when timed subtitles later become available',
      () async {
        plainOnly = true;
        expect(await app.loadLyrics(track), 'Plain server text');
        plainOnly = false;
        expect(
          parseLrc((await app.loadLyrics(track, forceRefresh: true))!)
              .first
              .at
              .inMilliseconds,
          1250,
        );
      },
    );
    test(
      'legacy timed LRC remains available without a network request',
      () async {
        await legacy().parent.create(recursive: true);
        await legacy().writeAsString('[00:02.00]Existing timeline');
        expect(await app.loadLyrics(track), '[00:02.00]Existing timeline');
        expect(hits, 0);
      },
    );
  }, skip: !available ? 'Build Windows debug or set SYLPHY_MPV_LIBRARY' : false);
}
