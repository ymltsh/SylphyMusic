import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:sylphy_music/core/app_controller.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/services/local_library.dart';
import 'package:sylphy_music/services/sources.dart';
import 'package:sylphy_music/ui/app_shell.dart';

import '../test/playback_native_test.dart' show wav;
import '../test/live_emby_test.dart' show MemoryVault;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Native startup, platform media controls and local/loopback playback',
    (tester) async {
      MediaKit.ensureInitialized();
      final root = await Directory.systemTemp.createTemp(
        'sylphy-desktop-integration-',
      );
      final app = await SylphyApp.bootstrap(
        dataRoot: root,
        credentialVault: MemoryVault(),
        resumeBackground: false,
      );
      HttpServer? server;
      try {
        if (Platform.isWindows) {
          final caps = await const MethodChannel('music.sylphy/desktop')
              .invokeMapMethod<String, dynamic>('capabilities');
          expect(caps?['mediaControls'], true);
          expect(caps?['tray'], true);
        }
        await app.playback.setVolume(0);
        if (const bool.fromEnvironment('SYLPHY_NATIVE_AUDIT')) {
          final native = app.playback.player.platform;
          if (native is NativePlayer) {
            final audit = <String, String>{};
            for (final property in [
              'mpv-version',
              'ffmpeg-version',
              'mpv-configuration',
            ]) {
              try {
                audit[property] = await native.getProperty(property);
              } catch (_) {
                audit[property] = 'unavailable';
              }
            }
            debugPrint('SYLPHY_NATIVE_AUDIT ${jsonEncode(audit)}');
          }
        }
        if (const bool.fromEnvironment('SYLPHY_HEADLESS_AUDIO')) {
          final native = app.playback.player.platform;
          if (native is NativePlayer) {
            await native.setProperty('options/ao', 'null');
          }
        }
        await app.db.putSource(
          const SourceProfile(
            id: 'local',
            name: 'Local',
            kind: SourceKind.local,
            url: 'file:///',
            username: '',
          ),
        );
        final track = await LocalLibrary(root)
            .read(await wav(root, 'integration'), 'local');
        await app.db.replaceSourceTracks('local', [track]);
        await app.reload();
        await tester.pumpWidget(MaterialApp(home: SylphyShell(app: app)));
        await tester.pumpAndSettle();
        expect(find.text('integration'), findsOneWidget);
        await app.db.replaceSourceTracks('local', [
          track,
          ...List.generate(
            205,
            (i) => Track(
              ref: TrackRef('local', 'paged-$i'),
              title: 'Paged ${i.toString().padLeft(3, '0')}',
              artist: 'Paged Artist',
              album: 'Paged Album',
            ),
          ),
        ]);
        await app.reload();
        await tester.pumpAndSettle();
        expect(find.text('1–100 / 206'), findsOneWidget);
        await tester.tap(find.byTooltip('下一页'));
        await tester.pumpAndSettle();
        expect(find.text('101–200 / 206'), findsOneWidget);
        await tester.tap(find.byTooltip('下一页'));
        await tester.pumpAndSettle();
        expect(find.text('201–206 / 206'), findsOneWidget);
        await tester.tap(find.text('艺术家').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paged Artist').first);
        await tester.pumpAndSettle();
        expect(find.text('播放全部 · 205 首'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('歌曲').first);
        await tester.pumpAndSettle();
        await app.playback.setQueue([track.ref]);
        await tester.pump(const Duration(seconds: 1));
        expect(app.playback.error, isNull);
        await app.playback.pause();
        expect(app.playback.currentRef, track.ref);
        expect(app.playback.duration, greaterThan(Duration.zero));
        final bytes = await (await wav(root, 'remote')).readAsBytes();
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          final range = request.headers.value('range');
          final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range ?? '');
          final start = match == null ? 0 : int.parse(match.group(1)!);
          final end = match == null || match.group(2)!.isEmpty
              ? bytes.length - 1
              : int.parse(match.group(2)!).clamp(start, bytes.length - 1);
          request.response.headers.set('etag', '"test-audio-v1"');
          request.response.headers.contentType = ContentType('audio', 'wav');
          request.response.contentLength = end - start + 1;
          if (range != null) {
            request.response.statusCode = 206;
            request.response.headers.set(
              'content-range',
              'bytes $start-$end/${bytes.length}',
            );
          }
          if (request.uri.path.contains('/job/')) {
            await Future<void>.delayed(const Duration(seconds: 2));
          }
          if (request.method != 'HEAD') {
            request.response.add(bytes.sublist(start, end + 1));
          }
          await request.response.close();
        });
        final source = SourceProfile(
          id: 'remote',
          name: 'Loopback',
          kind: SourceKind.emby,
          url: 'http://127.0.0.1:${server.port}',
          username: 'test',
        );
        final remote = Track(
          ref: const TrackRef('remote', 'one'),
          title: 'Loopback',
          artist: 'Synthetic',
          album: 'Test',
        );
        await app.db.putSource(source);
        await app.db.replaceSourceTracks(source.id, [remote]);
        await app.cache.prefetchNext(remote, source, bytesLimit: 1024);
        expect(app.cache.preview(remote.ref)?.bytes.length, 1024);
        await app.playback.setQueue([remote.ref]);
        await tester.pump(const Duration(seconds: 1));
        await app.playback.pause();
        expect(app.playback.error, isNull);
        for (var i = 0; i < 100 && !await app.cache.contains(remote.ref); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(await app.cache.contains(remote.ref), true);
        expect(
          await (await app.cache.find(remote.ref))!.file.readAsBytes(),
          bytes,
        );
        await app.playback.seek(const Duration(seconds: 2));
        await app.playback.pause();
        final jobTrack = Track(
          ref: const TrackRef('remote', 'job'),
          title: 'Cache Job',
          artist: 'Synthetic',
          album: 'Test',
        );
        await app.db.replaceSourceTracks(source.id, [remote, jobTrack]);
        final jobId = await app.jobs.schedule('Integration cache', [
          jobTrack.ref,
        ]);
        if (Platform.isAndroid) {
          var running = false;
          for (var i = 0; i < 50 && !running; i++) {
            running =
                await const MethodChannel('music.sylphy/cache_lifecycle')
                    .invokeMethod<bool>('status') ??
                false;
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          expect(running, true);
        }
        String state = 'pending';
        for (var i = 0; i < 200 && state != 'completed'; i++) {
          state =
              (await app.db.db.query(
                    'cache_jobs',
                    where: 'id=?',
                    whereArgs: [jobId],
                  )).single['state']
                  as String;
          if (state == 'failed') break;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(state, 'completed');
        expect(await app.cache.contains(jobTrack.ref), true);
        final current = app.playback.currentRef;
        await app.toggleSource(source);
        expect((await app.db.source(source.id))!.enabled, false);
        expect(app.playback.playing, false);
        expect(app.playback.currentRef, current);
        expect(await app.cache.contains(remote.ref), true);
        expect(await app.cache.contains(jobTrack.ref), true);
        const privateFixtureUrl = String.fromEnvironment(
          'SYLPHY_PRIVATE_TEST_URL',
        );
        if (privateFixtureUrl.isNotEmpty) {
          final client = HttpClient();
          EmbyAdapter? adapter;
          try {
            final response = await (await client.getUrl(
              Uri.parse(privateFixtureUrl),
            )).close();
            final values = (await utf8.decoder.bind(response).join())
                .split(RegExp(r'\r?\n'))
                .where((line) => line.trim().isNotEmpty)
                .toList();
            if (values.length != 3) throw StateError('Invalid private fixture');
            final source = SourceProfile(
              id: 'live-emby',
              name: 'Live Emby',
              kind: SourceKind.emby,
              url: values[0].trim(),
              username: values[1].trim(),
            );
            adapter = EmbyAdapter(source, app.vault);
            await adapter.login(values[2]);
            await app.db.putSource(source);
            await app.syncSource(source);
            final rows = await app.db.db.query(
              'tracks',
              where: 'source_id=? AND missing=0',
              whereArgs: [source.id],
              limit: 1,
            );
            if (rows.isEmpty) throw StateError('Empty test library');
            final first = Track.fromRow(rows.single);
            await app.playback.setQueue([first.ref]);
            if (app.playback.player.state.duration <= Duration.zero) {
              await app.playback.player.stream.duration
                  .firstWhere((value) => value > Duration.zero)
                  .timeout(const Duration(seconds: 20));
            }
            await Future<void>.delayed(const Duration(seconds: 2));
            if (app.playback.error != null || !app.playback.playing) {
              throw StateError('Native Emby playback failed');
            }
            await app.playback.seek(const Duration(seconds: 3));
            await app.playback.pause();
            expect(app.playback.currentRef == first.ref, true);
            await app.toggleSource(source);
            expect((await app.db.source(source.id))!.enabled, false);
            await app.toggleSource(source);
            expect((await app.db.source(source.id))!.enabled, true);
            expect(app.playback.playing, false);
            await app.playback.play();
            await Future<void>.delayed(const Duration(seconds: 1));
            expect(app.playback.error, isNull);
            expect(app.playback.currentRef == first.ref, true);
            await app.playback.pause();
          } catch (error) {
            fail(
              'Private Emby device playback failed (${error.runtimeType}); connection and media metadata withheld',
            );
          } finally {
            adapter?.close();
            client.close(force: true);
          }
        }
        await tester.pumpWidget(const SizedBox());
      } finally {
        await app.disposeAsync();
        await server?.close(force: true);
        await root.delete(recursive: true);
      }
    },
  );
}
