import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sylphy_music/core/app_controller.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/ui/cover_art.dart';
import 'package:sylphy_music/services/lyrics.dart';

import '../test/live_emby_test.dart' show MemoryVault;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'WebDAV embedded artwork and lyrics load before READY and survive offline restart',
    (tester) async {
      MediaKit.ensureInitialized();
      const overrideRoot = String.fromEnvironment('SYLPHY_ASSET_TEST_ROOT');
      final testBase = await Directory(
        overrideRoot.isNotEmpty
            ? overrideRoot
            : p.join(
                (await getApplicationSupportDirectory()).path,
                'sylphy-asset-tests',
              ),
      ).create(recursive: true);
      final root = await testBase.createTemp('case-');
      if (!p.isWithin(testBase.absolute.path, root.absolute.path)) {
        throw StateError('Invalid test root');
      }
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.teal, BlendMode.src);
      final picture = recorder.endRecording();
      final fixtureImage = await picture.toImage(16, 16);
      picture.dispose();
      final data = await fixtureImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      fixtureImage.dispose();
      final png = data!.buffer.asUint8List();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      List<int> num(int n, int width, {bool sync = false}) => [
        for (var i = width - 1; i >= 0; i--)
          (n >> (i * (sync ? 7 : 8))) & (sync ? 127 : 255),
      ];
      List<int> frame(String id, List<int> data) => [
        ...ascii.encode(id),
        ...num(data.length, 4),
        0,
        0,
        ...data,
      ];
      final payload = [
        ...frame('TIT2', [3, ...utf8.encode('Embedded title')]),
        ...frame('TPE1', [3, ...utf8.encode('Embedded artist')]),
        ...frame('TALB', [3, ...utf8.encode('Embedded album')]),
        ...frame('USLT', [
          3,
          ...ascii.encode('eng'),
          0,
          ...utf8.encode('[00:01.00]Native cached lyrics'),
        ]),
        ...frame('APIC', [0, ...ascii.encode('image/png'), 0, 3, 0, ...png]),
      ];
      final bytes = [
        73,
        68,
        51,
        3,
        0,
        0,
        ...num(payload.length, 4, sync: true),
        ...payload,
      ];
      server.listen((r) async {
        requests++;
        expect(
          r.headers.value('Authorization'),
          'Basic ${base64Encode(utf8.encode('fixture:fixture'))}',
        );
        final range = RegExp(r'bytes=(\d+)-(\d+)')
            .firstMatch(r.headers.value('Range')!)!;
        final start = int.parse(range[1]!), end = int.parse(range[2]!);
        expect(end, lessThan(bytes.length));
        r.response.statusCode = 206;
        r.response.headers.set('Content-Range', 'bytes $start-$end/52428800');
        r.response.headers.set('ETag', '"fixture-v1"');
        r.response.add(bytes.sublist(start, end + 1));
        await r.response.close();
      });
      SylphyApp? app;
      try {
        app = await SylphyApp.bootstrap(
          dataRoot: root,
          credentialVault: MemoryVault(),
          resumeBackground: false,
          platformIntegration: false,
        );
        final source = SourceProfile(
          id: 'dav',
          kind: SourceKind.webdav,
          name: 'Synthetic fixture',
          url: 'http://127.0.0.1:${server.port}/dav',
          username: 'fixture',
        );
        await app.db.putSource(source);
        await app.vault.write(source.id, 'password', 'fixture');
        final track = Track(
          ref: TrackRef(source.id, 'fixture.mp3'),
          title: 'Synthetic',
          artist: '',
          album: '',
          remote: {'format': 'MP3', 'size': 52428800, 'etag': '"fixture-v1"'},
        );
        await app.db.replaceSourceTracks(source.id, [track]);
        final cover = await app.artwork.load(track),
            lyrics = await app.loadLyrics(track);
        expect(cover, isNotNull);
        expect(parseLrc(lyrics!).first.at.inMilliseconds, 1000);
        expect(lyrics, contains('Native cached lyrics'));
        expect(await app.cache.find(track.ref), isNull);
        final enriched = await app.db.track(track.ref);
        expect(enriched!.title, 'Embedded title');
        expect(enriched.artist, 'Embedded artist');
        expect(enriched.album, 'Embedded album');
        final before = requests;
        await app.disposeAsync();
        app = null;
        await server.close(force: true);
        // A fresh vault proves that no online authenticated read is needed.
        app = await SylphyApp.bootstrap(
          dataRoot: root,
          credentialVault: MemoryVault(),
          resumeBackground: false,
          platformIntegration: false,
        );
        final restored = Track.fromRow(
          (await app.db.db.query('tracks')).single,
        );
        expect(restored.artist, 'Embedded artist');
        expect(restored.album, 'Embedded album');
        expect((await app.artwork.load(restored))!.path, cover!.path);
        expect(await app.loadLyrics(restored), lyrics);
        expect(requests, before);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CoverArt(app: app, track: restored, size: 96),
            ),
          ),
        );
        for (var i = 0; i < 50 && find.byType(Image).evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.byType(Image), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await app.assets.waitForIdle();
      } finally {
        await app?.disposeAsync();
        await server.close(force: true);
        await root.delete(recursive: true);
      }
    },
  );
}
