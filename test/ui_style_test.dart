import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/appearance.dart';
import 'package:sylphy_music/data/app_db.dart';
import 'package:sylphy_music/ui/design_system/ui_style_availability.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppDb db;
  late Appearance appearance;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sylphy-ui-style-');
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

  test('defaults to Material 3; persists the selected preference', () async {
    expect(appearance.uiStyle, UiStyle.material3);
    await appearance.setUiStyle(UiStyle.miuix);
    expect(await db.setting('ui_style'), 'miuix');
    final reloaded = Appearance(db);
    await reloaded.initialize();
    expect(reloaded.uiStyle, UiStyle.miuix);
    reloaded.dispose();
  });

  test('unknown stored value safely falls back to Material 3', () async {
    await db.setSetting('ui_style', 'some-future-style');
    final reloaded = Appearance(db);
    await reloaded.initialize();
    expect(reloaded.uiStyle, UiStyle.material3);
    reloaded.dispose();
  });

  test('rapid changes serialize writes and preserve the last choice', () async {
    await Future.wait([
      appearance.setUiStyle(UiStyle.miuix),
      appearance.setUiStyle(UiStyle.material3),
      appearance.setUiStyle(UiStyle.miuix),
    ]);
    expect(appearance.uiStyle, UiStyle.miuix);
    expect(await db.setting('ui_style'), 'miuix');
  });

  test('effective style is gated by platform and experiment flag', () {
    expect(
      UiStyleAvailability.effective(
        UiStyle.material3,
        experimentalEnabled: true,
        web: false,
        platform: TargetPlatform.android,
      ),
      UiStyle.material3,
    );
    expect(
      UiStyleAvailability.effective(
        UiStyle.miuix,
        experimentalEnabled: true,
        web: false,
        platform: TargetPlatform.android,
      ),
      UiStyle.miuix,
    );
    expect(
      UiStyleAvailability.effective(
        UiStyle.miuix,
        experimentalEnabled: false,
        web: false,
        platform: TargetPlatform.android,
      ),
      UiStyle.material3,
    );
    expect(
      UiStyleAvailability.effective(
        UiStyle.miuix,
        experimentalEnabled: true,
        web: false,
        platform: TargetPlatform.windows,
      ),
      UiStyle.material3,
    );
    expect(
      UiStyleAvailability.effective(
        UiStyle.miuix,
        experimentalEnabled: true,
        web: true,
        platform: TargetPlatform.android,
      ),
      UiStyle.material3,
    );
  });
}
