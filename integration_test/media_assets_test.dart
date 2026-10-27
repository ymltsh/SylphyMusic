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
    'persistent artwork and lyrics survive app service/database restart offline',
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
      final item = <String, Object?>{
        'Id': 'song',
        'Name': 'Synthetic fixture',
        'Type': 'Audio',
        'ImageTags': {'Primary': 'fixture-v1'},
        'MediaSources': [
          {
            'Id': 'media',
            'MediaStreams': [
              {'Index': 2, 'Type': 'Subtitle', 'Codec': 'text'},
            ],
          },
        ],
      };
      server.listen((r) async {
        requests++;
        await r.drain<void>();
        if (r.uri.path.endsWith('AuthenticateByName')) {
          r.response.write(
            jsonEncode({
              'AccessToken': 'fixture-token',
              'ServerId': 'fixture-server',
              'User': {'Id': 'u'},
            }),
          );
        } else if (r.uri.path.endsWith('/Images/Primary')) {
          r.response.headers.contentType = ContentType('image', 'png');
          r.response.headers.set('ETag', '"fixture-v1"');
          r.response.add(png);
        } else if (r.uri.path.endsWith('.srt')) {
          r.response.write(
            '1\n00:00:01,000 --> 00:00:03,000\nNative cached lyrics\n',
          );
        } else if (r.uri.path.endsWith('/Items/song')) {
          r.response.write(jsonEncode(item));
        } else {
          final audio = r.uri.queryParameters['IncludeItemTypes'] == 'Audio';
          r.response.write(
            jsonEncode({
              'Items': audio ? [item] : [],
              'TotalRecordCount': audio ? 1 : 0,
            }),
          );
        }
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
        await app.addSource(
          kind: SourceKind.emby,
          name: 'Synthetic fixture',
          url: 'http://127.0.0.1:${server.port}/emby',
          username: 'fixture',
          password: 'fixture',
        );
        final track = Track.fromRow((await app.db.db.query('tracks')).single);
        final cover = await app.artwork.load(track),
            lyrics = await app.loadLyrics(track);
        expect(cover, isNotNull);
        expect(parseLrc(lyrics!).first.at.inMilliseconds, 1000);
        expect(lyrics, contains('Native cached lyrics'));
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
