import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/ui/wide_card_ratio.dart';

void main() {
  testWidgets('wide card ratio requires opt-in and horizontal viewport', (
    tester,
  ) async {
    bool? active;
    Future<void> check(Size size, bool enabled, bool expected) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: size),
          child: Builder(
            builder: (context) {
              active = useWideCardRatio(context, enabled);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(active, expected);
    }

    await check(const Size(1080, 600), false, false);
    await check(const Size(1080, 600), true, true);
    await check(const Size(600, 1080), true, false);
    await check(const Size(640, 360), true, false);
    await check(const Size(800, 800), true, false);
  });
}
