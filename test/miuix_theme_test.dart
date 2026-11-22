import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:sylphy_music/core/appearance.dart';
import 'package:sylphy_music/data/app_db.dart';
import 'package:sylphy_music/ui/design_system/miuix_theme_scope.dart';
import 'package:sylphy_music/ui/design_system/ui_style_availability.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ThemeMode maps to corresponding Miuix Monet modes', () {
    expect(
      MiuixThemeScope.schemeMode(ThemeMode.system),
      MiuixColorSchemeMode.monetSystem,
    );
    expect(
      MiuixThemeScope.schemeMode(ThemeMode.light),
      MiuixColorSchemeMode.monetLight,
    );
    expect(
      MiuixThemeScope.schemeMode(ThemeMode.dark),
      MiuixColorSchemeMode.monetDark,
    );
  });

  group('Theme scope', () {
    late Directory root;
    late AppDb db;
    late Appearance appearance;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('sylphy-ui-theme-');
      db = AppDb(root);
      await db.open();
      appearance = Appearance(db);
      await appearance.initialize();
    });

    tearDown(() async {
      await appearance.shutdown();
      await db.close();
      await root.delete(recursive: true);
    });

    testWidgets('style gate preserves the navigator and open route', (
      tester,
    ) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      Widget buildApp() => MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) =>
            MiuixThemeScope(appearance: appearance, child: child!),
        home: const Scaffold(body: Text('home')),
      );

      await tester.pumpWidget(buildApp());
      final original = navigatorKey.currentState!;
      original.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('open route')),
        ),
      );
      await tester.pumpAndSettle();

      for (final style in [UiStyle.miuix, UiStyle.material3]) {
        await tester.runAsync(() => appearance.setUiStyle(style));
        await tester.pumpWidget(buildApp());
        expect(navigatorKey.currentState, same(original));
        expect(find.text('open route'), findsOneWidget);
        expect(UiStyleAvailability.effective(appearance.uiStyle), style);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}
