import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sylphy_music/ui/about_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final launched = <String>[];
  var canOpen = true;
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Sylphy Music',
      packageName: 'com.ymltsh.sylphymusic',
      version: '1.0.0',
      buildNumber: '12',
      buildSignature: '',
    );
    canOpen = true;
    launched.clear();
    messenger.setMockMethodCallHandler(launcher, (call) async {
      launched.add((call.arguments as Map)['url'] as String);
      return canOpen;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(launcher, null));

  Future<void> showAbout(
    WidgetTester tester, {
    Size size = const Size(360, 800),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const AboutPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unlock(WidgetTester tester) async {
    for (var i = 0; i < 7; i++) {
      await tester.tap(find.byKey(const ValueKey('about-logo-easter-egg')));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 7));
  }

  testWidgets('project links use the browser and failures show a message', (
    tester,
  ) async {
    await showAbout(tester);
    final targets = {
      '官方网站': 'https://sylphy.ymltsh.com',
      'GitHub 源码仓库': 'https://github.com/ymltsh/SylphyMusic',
      '版本发布与下载': 'https://github.com/ymltsh/SylphyMusic/releases/latest',
    };
    for (final entry in targets.entries) {
      await tester.scrollUntilVisible(find.text(entry.key), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(launched.last, entry.value);
    }
    canOpen = false;
    await tester.tap(find.text('版本发布与下载'));
    await tester.pumpAndSettle();
    expect(find.text('无法打开链接，请稍后重试'), findsOneWidget);
  });

  testWidgets('installed version and licenses are reachable', (tester) async {
    await showAbout(tester);
    await tester.scrollUntilVisible(find.text('1.0.0+12'), 200);
    expect(find.text('1.0.0+12'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('开源许可证'), 150);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开源许可证'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('about logo uses the dedicated transparent artwork', (
    tester,
  ) async {
    await showAbout(tester);
    final logo = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('about-logo-easter-egg')),
        matching: find.byType(Image),
      ),
    );
    expect((logo.image as AssetImage).assetName, 'assets/about.png');
  });

  testWidgets('seven taps unlock a constellation that can close and reopen', (
    tester,
  ) async {
    await showAbout(tester);
    for (var attempt = 0; attempt < 2; attempt++) {
      await unlock(tester);
      expect(find.text('天琴座'), findsOneWidget);
      expect(find.text('VERSION CONSTELLATION  ·  1.0'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('关闭星图'));
      await tester.pumpAndSettle();
      expect(find.text('天琴座'), findsNothing);
    }
  });

  testWidgets('two seconds between taps resets the unlock count', (
    tester,
  ) async {
    await showAbout(tester);
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const ValueKey('about-logo-easter-egg')));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.tap(find.byKey(const ValueKey('about-logo-easter-egg')));
    await tester.pump();
    expect(find.text('星图解锁 · 1 / 7'), findsOneWidget);
    expect(find.text('天琴座'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [const Size(320, 640), const Size(800, 320)]) {
    testWidgets('about and constellation fit $size with large text', (
      tester,
    ) async {
      await showAbout(tester, size: size, scale: 1.7);
      expect(tester.takeException(), isNull);
      await unlock(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('关闭星图'));
      await tester.pumpAndSettle();
      expect(find.text('天琴座'), findsNothing);
    });
  }
}
