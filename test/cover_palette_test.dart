import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/ui/cover_palette.dart';

void main() {
  testWidgets('cover palette follows the requested light and dark brightness', (
    tester,
  ) async {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      final scheme = await tester.runAsync(
        () => coverColorScheme(
          File('test/fixtures/cover.png'),
          brightness: brightness,
        ),
      );
      expect(scheme, isNotNull);
      expect(scheme!.brightness, brightness);
      final fallback = ColorScheme.fromSeed(
        seedColor: const Color(0xff5094b2),
        brightness: brightness,
      );
      expect(scheme.primary, isNot(fallback.primary));
    }
  });
  testWidgets('missing cover keeps the caller fallback', (tester) async {
    final scheme = await tester.runAsync(
      () => coverColorScheme(File('test/fixtures/missing-cover.png')),
    );
    expect(scheme, isNull);
  });
}
