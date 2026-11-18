import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/desktop_preferences.dart';
import 'package:sylphy_music/data/app_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('wide card ratio stays opt-in and survives restart', () async {
    final root = await Directory.systemTemp.createTemp('sylphy-wide-card-');
    final db = AppDb(root);
    await db.open();
    final original = DesktopPreferences(db);
    await original.initialize();
    expect(original.compactPageCards, isFalse);
    await original.update(compactCards: true);
    expect(original.compactPageCards, isTrue);
    expect(await db.setting('desktop_compact_page_cards'), 'true');
    await original.shutdown();
    final restored = DesktopPreferences(db);
    await restored.initialize();
    expect(restored.compactPageCards, isTrue);
    await restored.update(compactCards: false);
    expect(restored.compactPageCards, isFalse);
    await restored.shutdown();
    await db.close();
    await root.delete(recursive: true);
  });
}
