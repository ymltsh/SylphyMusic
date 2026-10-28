import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:path_provider/path_provider.dart';
import 'package:sylphy_music/core/app_controller.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/services/native_lifecycle.dart';
import 'package:sylphy_music/services/local_library.dart';

import '../test/live_emby_test.dart' show MemoryVault;
import '../test/playback_native_test.dart' show wav;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android sync foreground service, background timeout, resume and audio engine',
    (tester) async {
      if (!Platform.isAndroid) return;
      await recordDartStartup();
      MediaKit.ensureInitialized();
      final base = await getApplicationSupportDirectory();
      final testBase = await Directory('${base.path}/fgs-fixture')
          .create(recursive: true);
      final root = await testBase.createTemp('case-');
      final app = await SylphyApp.bootstrap(
        dataRoot: root,
        credentialVault: MemoryVault(),
        resumeBackground: false,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      List<int> number(int n, int width) => [
        for (var i = width - 1; i >= 0; i--) (n >> (i * 8)) & 255,
      ];
      List<int> frame(String key, String value) {
        final body = [3, ...utf8.encode(value)];
        return [...ascii.encode(key), ...number(body.length, 4), 0, 0, ...body];
      }

      final payload = [
        ...frame('TIT2', 'FGS fixture'),
        ...frame('TPE1', 'FGS artist'),
        ...frame('TALB', 'FGS album'),
      ];
      final bytes = [
        73,
        68,
        51,
        3,
        0,
        0,
        0,
        0,
        (payload.length >> 7) & 127,
        payload.length & 127,
        ...payload,
      ];
      final hits = <String, int>{};
      server.listen((request) async {
        if (request.uri.path.endsWith('cache.bin')) {
          request.response.contentLength = 1048576;
          request.response.headers.set('ETag', '"v1"');
          try {
            for (var i = 0; i < 256; i++) {
              request.response.add(List<int>.filled(4096, 0));
              await request.response.flush();
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            await request.response.close();
          } catch (_) {
            /* paused download */
          }
          return;
        }
        final range = RegExp(r'bytes=(\d+)-(\d+)')
            .firstMatch(request.headers.value('range')!)!;
        final start = int.parse(range[1]!), end = int.parse(range[2]!);
        hits.update(request.uri.path, (n) => n + 1, ifAbsent: () => 1);
        request.response.statusCode = 206;
        request.response.headers.set(
          'Content-Range',
          'bytes $start-$end/1048576',
        );
        request.response.headers.set('ETag', '"v1"');
        request.response.add(bytes.sublist(start, end + 1));
        try {
          await request.response.close();
        } catch (_) {
          /* cancellation */
        }
      });
      const channel = MethodChannel('music.sylphy/sync_lifecycle');
      const cacheChannel = MethodChannel('music.sylphy/cache_lifecycle');
      Future<Map<Object?, Object?>> diagnostics() async =>
          (await channel.invokeMapMethod<Object?, Object?>('diagnostics'))!;
      Future<void> waitFor(bool Function(Map<Object?, Object?>) check) async {
        for (var i = 0; i < 100; i++) {
          if (check(await diagnostics())) return;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        fail('Lifecycle state did not settle: ${await diagnostics()}');
      }

      try {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('FGS fixture'))),
        );
        final source = SourceProfile(
          id: 'fgs',
          name: 'Synthetic fixture',
          kind: SourceKind.webdav,
          url: 'http://127.0.0.1:${server.port}/dav',
          username: 'fixture',
        );
        await app.db.putSource(source);
        await app.vault.write(source.id, 'password', 'fixture');
        final tracks = [
          for (var i = 0; i < 40; i++)
            Track(
              ref: TrackRef(
                source.id,
                'track-${i.toString().padLeft(2, '0')}.mp3',
              ),
              title: 'fixture',
              artist: '',
              album: '',
              remote: {'size': 1048576, 'etag': '"v1"', 'format': 'MP3'},
            ),
        ];
        await app.db.replaceSourceTracks(source.id, tracks);
        debugPrint('FGS_PERMISSION_READY');
        await Future<void>.delayed(const Duration(seconds: 2));
        var completed = false;
        final work = app.enrichSourceForeground(source).then((_) {
          completed = true;
        });
        for (var i = 0; i < 100; i++) {
          if (await channel.invokeMethod<bool>('status') == true) break;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(await channel.invokeMethod<bool>('status'), isTrue);
        expect(app.busy, isTrue);
        if (const bool.fromEnvironment('SYLPHY_FGS_OVERLAP_TEST')) {
          final initial = await diagnostics();
          expect(initial['dartStarts'], 1);
          const local = SourceProfile(
            id: 'local',
            name: 'fixture',
            kind: SourceKind.local,
            url: 'file:///',
            username: '',
          );
          await app.db.putSource(local);
          final audio = await LocalLibrary(root)
              .read(await wav(root, 'fgs-audio'), local.id);
          await app.db.replaceSourceTracks(local.id, [audio]);
          await app.playback.setVolume(0);
          await app.playback.setQueue([audio.ref]);
          if (!app.playback.player.state.playing) {
            await app.playback.player.stream.playing
                .firstWhere((playing) => playing)
                .timeout(const Duration(seconds: 5));
          }
          await app.playback.pause();
          final cacheTrack = Track(
            ref: TrackRef(source.id, 'cache.bin'),
            title: 'cache fixture',
            artist: '',
            album: '',
            remote: {'size': 1048576, 'etag': '"v1"'},
          );
          // Append without re-indexing or touching the active metadata cursor.
          await app.db.db.insert('tracks', cacheTrack.toRow());
          await app.jobs.schedule('Synthetic cache', [cacheTrack.ref]);
          await waitFor((state) => state['leaseCount'] == 2);
          final before = (await app.db.db.query('webdav_track_tags')).length;
          debugPrint('FGS_OVERLAP_BACKGROUND');
          await Future<void>.delayed(const Duration(seconds: 4));
          var state = await diagnostics();
          expect(state['engineId'], initial['engineId']);
          expect(state['engineCached'], true);
          expect(state['audioBound'], true);
          expect(state['leaseCount'], 2);
          expect(state['dartStarts'], 1);
          expect(state['syncHeartbeats'] as int, greaterThan(0));
          expect(state['cacheHeartbeats'] as int, greaterThan(0));
          expect(state['syncDartAgeMs'] as int, lessThan(3500));
          await app.playback.play();
          await app.playback.pause();
          expect(
            (await app.db.db.query('webdav_track_tags')).length,
            greaterThan(before),
          );
          await channel.invokeMethod<void>('pause');
          await work;
          await waitFor(
            (state) => state['sync'] == false && state['cache'] == true,
          );
          final saved = (await app.db.db.query('webdav_track_tags')).length;
          await Future<void>.delayed(const Duration(milliseconds: 400));
          expect((await app.db.db.query('webdav_track_tags')).length, saved);
          state = await diagnostics();
          expect(state['engineId'], initial['engineId']);
          expect(state['audioBound'], true);
          debugPrint('FGS_OVERLAP_RESTORE');
          await Future<void>.delayed(const Duration(seconds: 3));
          // Reverse order: release cache while resumed sync still owns a lease.
          final resumed = app.enrichSourceForeground(source);
          await waitFor((state) => state['leaseCount'] == 2);
          await cacheChannel.invokeMethod<void>('pause');
          await waitFor(
            (state) => state['cache'] == false && state['sync'] == true,
          );
          expect(app.jobs.paused, true);
          expect(
            (await app.db.db.query('cache_job_items')).single['state'],
            'pending',
          );
          state = await diagnostics();
          expect(state['engineId'], initial['engineId']);
          expect(state['engineCached'], true);
          await resumed;
          await waitFor((state) => state['leaseCount'] == 0);
          state = await diagnostics();
          expect(state['engineId'], initial['engineId']);
          expect(state['dartStarts'], 1);
          expect(state['engineCached'], true);
          debugPrint('FGS_OVERLAP_VERIFIED');
        } else if (const bool.fromEnvironment('SYLPHY_FGS_TIMEOUT_TEST')) {
          debugPrint('FGS_READY_BACKGROUND');
          for (var i = 0; i < 200 && !completed; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(completed, isTrue);
          await work;
          final done = (await app.db.db.query('webdav_track_tags')).length;
          expect(done, greaterThan(0));
          expect(done, lessThan(tracks.length));
          expect(await channel.invokeMethod<bool>('status'), isFalse);
          final saved = await app.db.db.query('webdav_track_tags');
          final savedHits = {
            for (final row in saved)
              '/dav/${row['track_id']}': hits['/dav/${row['track_id']}']!,
          };
          debugPrint('FGS_TIMEOUT_OBSERVED');
          await Future<void>.delayed(const Duration(seconds: 3));
          await app.enrichSourceForeground(source);
          for (final entry in savedHits.entries) {
            expect(hits[entry.key], entry.value);
          }
        } else {
          await work;
        }
        expect(
          (await app.db.db.query('webdav_track_tags')).length,
          tracks.length,
        );
        expect(await channel.invokeMethod<bool>('status'), isFalse);
        expect(app.busy, isFalse);
        expect(app.playback.handler, isNotNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await app.disposeAsync();
        await server.close(force: true);
        await root.delete(recursive: true);
      }
    },
  );
}
