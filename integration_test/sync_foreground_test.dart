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

import '../test/live_emby_test.dart' show MemoryVault;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android sync foreground service, background timeout, resume and audio engine',
    (tester) async {
      if (!Platform.isAndroid) return;
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
        if (const bool.fromEnvironment('SYLPHY_FGS_TIMEOUT_TEST')) {
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
