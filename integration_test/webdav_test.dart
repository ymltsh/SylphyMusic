import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:sylphy_music/core/app_controller.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/ui/app_shell.dart';

import '../test/live_emby_test.dart' show MemoryVault;
import '../test/playback_native_test.dart' show wav;
import '../test/webdav_test.dart' show davXml, davRow;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'WebDAV source sync, native playback, seek, cache, lyrics and disable',
    (tester) async {
      MediaKit.ensureInitialized();
      final root = await Directory.systemTemp.createTemp('sylphy-dav-native-');
      final app = await SylphyApp.bootstrap(
        dataRoot: root,
        credentialVault: MemoryVault(),
        resumeBackground: false,
      );
      final bytes = await (await wav(root, 'fixture')).readAsBytes();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var authorized = false;
      server.listen((r) async {
        authorized =
            r.headers.value('Authorization') ==
            'Basic ${base64Encode(utf8.encode('fixture:secret'))}';
        if (!authorized) {
          r.response.statusCode = 401;
          await r.response.close();
          return;
        }
        if (r.method == 'PROPFIND') {
          await r.drain<void>();
          r.response.statusCode = 207;
          r.response.write(
            davXml([
              davRow('/dav/', directory: true),
              davRow('/dav/fixture.wav'),
              davRow('/dav/fixture.lrc'),
            ]),
          );
        } else if (r.uri.path.endsWith('.lrc')) {
          r.response.add(utf8.encode('[00:00.00]WebDAV fixture'));
        } else {
          var start = 0, end = bytes.length - 1;
          final range = r.headers.value('Range');
          if (range != null) {
            final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
            start = int.parse(m[1]!);
            end = m[2]!.isEmpty ? end : int.parse(m[2]!).clamp(start, end);
            r.response.statusCode = 206;
            r.response.headers.set(
              'Content-Range',
              'bytes $start-$end/${bytes.length}',
            );
          }
          r.response.headers.set('ETag', '"fixture-v1"');
          r.response.contentLength = end - start + 1;
          if (r.method != 'HEAD') r.response.add(bytes.sublist(start, end + 1));
        }
        await r.response.close();
      });
      try {
        await app.playback.setVolume(0);
        if (const bool.fromEnvironment('SYLPHY_HEADLESS_AUDIO')) {
          final player = app.playback.player.platform;
          if (player is NativePlayer) {
            await player.setProperty('options/ao', 'null');
          }
        }
        await app.addSource(
          kind: SourceKind.webdav,
          name: 'DAV fixture',
          url: 'http://127.0.0.1:${server.port}/dav',
          username: 'fixture',
          password: 'secret',
        );
        final source = app.sources.single;
        final rows = await app.db.db.query('tracks');
        expect(rows.length, 1);
        final track = Track.fromRow(rows.single);
        await tester.pumpWidget(MaterialApp(home: SylphyShell(app: app)));
        await tester.pumpAndSettle();
        expect(find.text('fixture'), findsOneWidget);
        expect(await app.loadLyrics(track), '[00:00.00]WebDAV fixture');
        await app.playback.setQueue([track.ref]);
        if (app.playback.player.state.duration <= Duration.zero) {
          await app.playback.player.stream.duration
              .firstWhere((d) => d > Duration.zero)
              .timeout(const Duration(seconds: 20));
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(app.playback.error, isNull);
        expect(authorized, true);
        await app.playback.seek(const Duration(seconds: 2));
        await app.playback.pause();
        for (var i = 0; i < 100 && !await app.cache.contains(track.ref); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(await app.cache.contains(track.ref), true);
        expect(
          await (await app.cache.find(track.ref))!.file.readAsBytes(),
          bytes,
        );
        await app.addPlaylist('DAV local');
        final playlist = app.playlists.firstWhere((p) => p.name == 'DAV local');
        await app.setPlaylistKeys(playlist, [track.ref.key]);
        expect(await app.db.playlistKeys(playlist.id), [track.ref.key]);
        await app.toggleSource(source);
        expect((await app.db.source(source.id))!.enabled, false);
        expect(await app.cache.contains(track.ref), true);
        await app.toggleSource(source);
        expect((await app.db.source(source.id))!.enabled, true);
        await tester.pumpWidget(const SizedBox());
      } finally {
        await app.disposeAsync();
        await server.close(force: true);
        await root.delete(recursive: true);
      }
    },
  );
}
