import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:sylphy_music/core/app_controller.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/ui/app_shell.dart';
import 'package:sylphy_music/ui/now_playing.dart';
import 'package:sylphy_music/ui/system_bars.dart';
import 'package:sylphy_music/ui/app_theme.dart';
import 'package:sylphy_music/ui/app_background.dart';
import 'package:sylphy_music/core/appearance.dart';

import '../test/live_emby_test.dart' show MemoryVault;
import '../test/playback_native_test.dart' show wav;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android transparent system bars preserve insets across themes, routes and IME',
    (tester) async {
      await configureSystemBars();
      MediaKit.ensureInitialized();
      final root = await Directory.systemTemp.createTemp('sylphy-system-bars-');
      final app = await SylphyApp.bootstrap(
        dataRoot: root,
        credentialVault: MemoryVault(),
        resumeBackground: false,
        platformIntegration: false,
      );
      Future<void> checkpoint(String label) async {
        await tester.pump();
        expect(tester.takeException(), isNull);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        debugPrint('SYLPHY_EDGE_FRAME_$label');
        // The host captures the real Android compositor, including system bars.
        await Future<void>.delayed(const Duration(seconds: 3));
      }

      try {
        await app.db.putSource(
          const SourceProfile(
            id: 'local',
            name: '测试音乐库',
            kind: SourceKind.local,
            url: 'file:///',
            username: '',
          ),
        );
        final file = await wav(root, 'fixture');
        final track = Track(
          ref: const TrackRef('local', 'fixture'),
          title: '风穿过森林',
          artist: 'Sylphy Studio',
          album: '绿野来信',
          remote: {'path': file.path},
        );
        await app.db.replaceSourceTracks('local', [track]);
        await app.reload();
        await app.playback.setVolume(0);
        await app.appearance.update(theme: ThemeMode.light);
        await tester.pumpWidget(
          ListenableBuilder(
            listenable: app.appearance,
            builder: (context, _) => MaterialApp(
              debugShowCheckedModeBanner: false,
              themeMode: app.appearance.mode,
              theme: sylphyTheme(app.appearance, Brightness.light),
              darkTheme: sylphyTheme(app.appearance, Brightness.dark),
              builder: (context, child) => AppSystemBars(child: child!),
              home: SylphyShell(app: app),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final view = tester.view;
        final height = view.physicalSize.height / view.devicePixelRatio;
        final inset = view.viewPadding.bottom / view.devicePixelRatio;
        expect(inset, greaterThan(0));
        expect(
          tester.getSize(find.byType(NavigationBar)).height,
          closeTo(54 + inset, .5),
        );
        expect(
          tester.getBottomLeft(find.text('首页')).dy,
          lessThan(height - inset),
        );
        await checkpoint('home_light');
        await tester.tap(find.byTooltip('设置'));
        await tester.pumpAndSettle();
        expect(find.byType(AppBackground), findsNothing);
        expect(app.appearance.seedHex, '#5094B2');
        await tester.tap(find.text('主题颜色'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, '自定义颜色'),
          '#A45C7A',
        );
        await tester.tap(find.text('应用'));
        await tester.pumpAndSettle();
        expect(app.appearance.seedHex, '#A45C7A');
        await tester.tap(find.text('主题颜色'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('恢复默认'));
        await tester.pumpAndSettle();
        expect(app.appearance.seed, Appearance.defaultSeed);
        await checkpoint('settings_light');
        await tester.pageBack();
        await tester.pumpAndSettle();
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        final paint = ui.Paint()
          ..shader = ui.Gradient.linear(
            const Offset(0, 0),
            const Offset(960, 540),
            [const Color(0xff163d70), const Color(0xffd0e8bd)],
          );
        canvas.drawRect(const Rect.fromLTWH(0, 0, 960, 540), paint);
        canvas.drawCircle(
          const Offset(730, 150),
          110,
          ui.Paint()..color = const Color(0xfffcdeaf),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(960, 540);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        final sourceImage = await File('${root.path}/test-background.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        await app.appearance.setBackground(sourceImage);
        await app.appearance.update(visibility: .4);
        await tester.pumpAndSettle();
        expect(find.byType(AppBackground), findsOneWidget);
        await checkpoint('background_light');
        await tester.tap(find.byTooltip('设置'));
        await tester.pumpAndSettle();
        expect(find.byType(AppBackground), findsNothing);
        await checkpoint('settings_background_excluded');
        final restored = Appearance(app.db);
        await restored.initialize();
        expect(
          restored.backgroundFile!.path,
          app.appearance.backgroundFile!.path,
        );
        restored.dispose();
        await tester.pageBack();
        await tester.pumpAndSettle();
        await app.appearance.update(theme: ThemeMode.dark);
        await tester.pumpAndSettle();
        await checkpoint('home_dark');
        expect(find.byType(AppBackground), findsOneWidget);
        await tester.tap(find.byTooltip('搜索'));
        await tester.pumpAndSettle();
        expect(find.byType(AppBackground), findsNothing);
        await tester.tap(find.byType(TextField));
        for (var i = 0; i < 30 && view.viewInsets.bottom == 0; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(view.viewInsets.bottom, greaterThan(0));
        await checkpoint('search_keyboard_dark');
        FocusManager.instance.primaryFocus?.unfocus();
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        await app.playback.setQueue([track.ref], autoplay: false);
        await tester.pumpAndSettle();
        Navigator.push(
          tester.element(find.byType(SylphyShell)),
          MaterialPageRoute(builder: (_) => NowPlayingPage(app: app)),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(
          tester.getBottomLeft(find.byType(Slider).last).dy,
          lessThanOrEqualTo(height - inset),
        );
        expect(find.byType(AppBackground), findsNothing);
        await checkpoint('player_dark');
        await tester.tap(find.byTooltip('播放队列').last);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await checkpoint('queue_dark');
        await tester.pumpWidget(const SizedBox());
      } finally {
        await app.disposeAsync();
        await root.delete(recursive: true);
      }
    },
  );
}
