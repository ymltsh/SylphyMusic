import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sylphy_music/core/app_controller.dart';
import 'package:sylphy_music/ui/app_shell.dart';
import 'package:sylphy_music/ui/quick_start_wizard.dart';

import '../test/live_emby_test.dart' show MemoryVault;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final skipApi in [false, true]) {
    testWidgets(
      'welcome ${skipApi ? 'skips' : 'saves'} API config without awaiting first source sync',
      (tester) async {
        MediaKit.ensureInitialized();
        final root = await Directory.systemTemp.createTemp('welcome-sync-');
        final app = await SylphyApp.bootstrap(
          dataRoot: root,
          credentialVault: MemoryVault(),
          resumeBackground: false,
          platformIntegration: false,
        );
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final scanning = Completer<void>(), releaseScan = Completer<void>();
        var listings = 0;
        server.listen((request) async {
          try {
            if (request.method == 'PROPFIND') {
              listings++;
              if (listings > 1) {
                if (!scanning.isCompleted) scanning.complete();
                await releaseScan.future;
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
          } catch (_) {
            // A failed assertion may cancel the outstanding test request.
          }
        });
        Future<void> waitUntil(bool Function() ready) async {
          for (var i = 0; i < 100; i++) {
            await tester.pump(const Duration(milliseconds: 50));
            if (ready()) return;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          fail('Welcome transition did not complete');
        }

        Future<void> enter(String key, String value) async {
          final field = find.byKey(ValueKey(key));
          await tester.scrollUntilVisible(
            field,
            120,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.enterText(field, value);
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
        }

        try {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(360, 800);
          await tester.pumpWidget(MaterialApp(home: SylphyShell(app: app)));
          await waitUntil(() => find.byTooltip('开始使用').evaluate().isNotEmpty);
          await tester.tap(find.byTooltip('开始使用'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('WebDAV'));
          await tester.pumpAndSettle();
          await enter('source-name', 'Synthetic welcome fixture');
          await enter('source-host', 'http://127.0.0.1:${server.port}/dav/');
          await enter('source-user', 'fixture');
          await enter('source-password', 'fixture');
          await tester.tap(find.text('连接并同步'));
          await waitUntil(() => scanning.isCompleted);
          await tester.pump(const Duration(milliseconds: 400));
          expect(app.busy, true);
          expect(app.sources.length, 1);
          expect(find.text('音乐库正在后台处理，可继续下一步。'), findsOneWidget);
          expect(
            tester
                .widget<ListTile>(find.widgetWithText(ListTile, 'WebDAV'))
                .enabled,
            false,
          );
          await tester.tap(find.text('下一步：API 配置'));
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('API 配置'), findsOneWidget);
          if (!skipApi) {
            await tester.enterText(
              find.widgetWithText(TextFormField, 'GitHub 加速 API'),
              'https://mirror.example.invalid/',
            );
          }
          await tester.tap(find.text(skipApi ? '跳过 API 配置' : '完成设置'));
          await waitUntil(
            () => find.byType(NavigationBar).evaluate().isNotEmpty,
          );
          expect(find.byType(QuickStartWizard), findsNothing);
          expect(await app.db.setting('ui_onboarded'), 'true');
          expect(app.busy, true);
          expect(releaseScan.isCompleted, false);
          if (!skipApi) {
            expect(
              app.apiSettings.githubMirror,
              'https://mirror.example.invalid/',
            );
          }
          // Leaving / disposing the wizard must not cancel or await this scan.
          releaseScan.complete();
          await waitUntil(() => !app.busy);
          expect(app.index.progress[app.sources.single.id]?.state, 'completed');
          expect(tester.takeException(), isNull);
        } finally {
          if (!releaseScan.isCompleted) releaseScan.complete();
          await tester.pumpWidget(const SizedBox());
          await app.disposeAsync();
          await server.close(force: true);
          await root.delete(recursive: true);
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
      },
    );
  }
}
