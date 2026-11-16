import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/ui/rotating_cover.dart';

void main() {
  Widget view({
    bool playing = true,
    bool enabled = true,
    bool visible = true,
    bool reduced = false,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: TickerMode(
        enabled: visible,
        child: RotatingCover(
          enabled: enabled,
          playing: playing,
          child: const SizedBox.square(dimension: 100),
        ),
      ),
    ),
  );
  double angle(WidgetTester tester) => tester
      .widget<RotationTransition>(find.byType(RotationTransition))
      .turns
      .value;
  testWidgets(
    'disc rotates while playing, freezes when paused and resumes from its angle',
    (tester) async {
      await tester.pumpWidget(view());
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      final first = angle(tester);
      expect(first, greaterThan(0));
      await tester.pumpWidget(view(playing: false));
      await tester.pump(const Duration(seconds: 3));
      expect(angle(tester), first);
      await tester.pumpWidget(view());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(angle(tester), greaterThan(first));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('hidden and user-disabled covers do not spin', (tester) async {
    await tester.pumpWidget(view(visible: false));
    await tester.pump(const Duration(seconds: 2));
    expect(angle(tester), 0);
    await tester.pumpWidget(view());
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(angle(tester), greaterThan(0));
    final visibleAngle = angle(tester);
    await tester.pumpWidget(view(visible: false));
    await tester.pump(const Duration(seconds: 2));
    expect(angle(tester), visibleAngle);
    await tester.pumpWidget(view());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(angle(tester), closeTo(visibleAngle + .05, .001));
    await tester.pumpWidget(view(enabled: false));
    await tester.pump(const Duration(seconds: 2));
    expect(angle(tester), 0);
  });
  testWidgets('system-disabled animations preserve the 20-second rotation', (
    tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    await tester.pumpWidget(view(reduced: true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(angle(tester), closeTo(.25, .001));
    await tester.pump(const Duration(seconds: 5));
    expect(angle(tester), closeTo(.5, .001));
    final paused = angle(tester);
    await tester.pumpWidget(view(reduced: true, playing: false));
    await tester.pump(const Duration(seconds: 2));
    expect(angle(tester), paused);
    await tester.pumpWidget(view(reduced: true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(angle(tester), closeTo(paused + .05, .001));
    await tester.pumpWidget(view(reduced: true, enabled: false));
    await tester.pump(const Duration(seconds: 2));
    expect(angle(tester), 0);
  });
}
