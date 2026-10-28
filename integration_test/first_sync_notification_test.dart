import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sylphy_music/core/app_controller.dart';
import 'package:sylphy_music/core/models.dart';

import '../test/live_emby_test.dart' show MemoryVault;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'first source scan waits for permission and posts its notification',
    (tester) async {
      if (!Platform.isAndroid) return;
      MediaKit.ensureInitialized();
      final base = await getApplicationSupportDirectory();
      final testBase = await Directory('${base.path}/first-sync-fixture')
          .create(recursive: true);
      final root = await testBase.createTemp('case-');
      final app = await SylphyApp.bootstrap(
        dataRoot: root,
        credentialVault: MemoryVault(),
        resumeBackground: false,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final scanned = Completer<void>(), finishScan = Completer<void>();
      var listings = 0;
      server.listen((request) async {
        if (request.method == 'PROPFIND') {
          listings++;
          if (listings > 1) {
            scanned.complete();
            await finishScan.future;
          }
          request.response.statusCode = 207;
          request.response.write(
            '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:"><d:response><d:href>/dav/</d:href>
<d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>''',
          );
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });
      const lifecycle = MethodChannel('music.sylphy/sync_lifecycle');
      Future<Map<Object?, Object?>> diagnostics() async =>
          (await lifecycle.invokeMapMethod<Object?, Object?>('diagnostics'))!;
      try {
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        // The dedicated AVD driver revokes permission here, before addSource.
        debugPrint('FIRST_SYNC_PERMISSION_RESET');
        await Future<void>.delayed(const Duration(seconds: 3));
        expect((await diagnostics())['notificationsEnabled'], false);
        final work = app.addSource(
          kind: SourceKind.webdav,
          name: 'Synthetic notification fixture',
          url: 'http://127.0.0.1:${server.port}/dav/',
          username: 'fixture',
          password: 'fixture',
        );
        // While the real permission dialog remains unanswered, login may finish
        // but the initial index / foreground service must not have started.
        for (var i = 0; i < 100 && listings == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        await Future<void>.delayed(const Duration(seconds: 1));
        expect(listings, 1);
        expect(await lifecycle.invokeMethod<bool>('status'), false);
        debugPrint('FIRST_SYNC_AWAITING_PERMISSION');
        await scanned.future.timeout(const Duration(seconds: 20));
        const denied = bool.fromEnvironment('SYLPHY_NOTIFICATION_DENY');
        final state = await diagnostics();
        expect(state['notificationsEnabled'], !denied);
        expect(state['notificationChannelEnabled'], true);
        if (!denied) {
          for (var i = 0; i < 40; i++) {
            if ((await diagnostics())['notificationPosted'] == true) break;
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          expect((await diagnostics())['notificationPosted'], true);
          debugPrint('FIRST_SYNC_NOTIFICATION_READY');
          // Host expands the shade and checks the actual visible title.
          await Future<void>.delayed(const Duration(seconds: 8));
        } else {
          expect(await lifecycle.invokeMethod<bool>('status'), true);
          debugPrint('FIRST_SYNC_DENIAL_CONTINUES');
        }
        finishScan.complete();
        await work;
        expect(app.busy, false);
        final saved = app.sources.single;
        expect(app.index.progress[saved.id]?.state, 'completed');
        for (var i = 0; i < 40; i++) {
          if ((await diagnostics())['notificationPosted'] == false) break;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect((await diagnostics())['notificationPosted'], false);
        expect(await lifecycle.invokeMethod<bool>('status'), false);
        debugPrint('FIRST_SYNC_COMPLETE');
      } finally {
        if (!finishScan.isCompleted) finishScan.complete();
        await tester.pumpWidget(const SizedBox());
        await app.disposeAsync();
        await server.close(force: true);
        await root.delete(recursive: true);
      }
    },
  );
}
