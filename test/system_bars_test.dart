import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/ui/system_bars.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => calls.add(call),
    );
    calls.clear();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  testWidgets(
    'resume restores edge-to-edge and the saved native style each time',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AppSystemBars(child: SizedBox.expand())),
      );
      for (var i = 0; i < 2; i++) {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        calls.clear();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        final restoration = calls.where(
          (call) => call.method != 'SystemChrome.setSystemUIOverlayStyle',
        );
        expect(restoration.map((call) => call.method), [
          'SystemChrome.setEnabledSystemUIMode',
          'SystemChrome.restoreSystemUIOverlays',
        ]);
        expect(restoration.first.arguments, 'SystemUiMode.edgeToEdge');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      calls.clear();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final brightness in Brightness.values) {
    for (final gestureInset in [0.0, 24.0]) {
      testWidgets(
        'style follows $brightness with gesture inset $gestureInset',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: MediaQuery(
                data: MediaQueryData(
                  systemGestureInsets: EdgeInsets.only(bottom: gestureInset),
                ),
                child: const AppSystemBars(child: SizedBox.expand()),
              ),
            ),
          );
          final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.descendant(
              of: find.byType(AppSystemBars),
              matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
            ),
          );
          expect(region.value.systemNavigationBarColor, Colors.transparent);
          expect(
            region.value.systemNavigationBarContrastEnforced,
            gestureInset == 0,
          );
          expect(
            region.value.systemNavigationBarIconBrightness,
            brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          );
        },
      );
    }
  }

  test('desktop does not issue Android system bar commands', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await configureSystemBars();
    expect(calls, isEmpty);
  });
}
