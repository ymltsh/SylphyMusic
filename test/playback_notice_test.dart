import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/ui/playback_notice.dart';

class PlaybackFixture extends ChangeNotifier {
  String? error;
  void report(String? value) {
    error = value;
    notifyListeners();
  }
}

void main() {
  late PlaybackFixture playback;
  final toast = find.byKey(const ValueKey('playback-error-toast'));
  setUp(() {
    playback = PlaybackFixture();
  });
  tearDown(() {
    playback.dispose();
  });
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlaybackNotice(
          playback: playback,
          readError: () => playback.error,
          child: const Scaffold(body: Text('player')),
        ),
      ),
    );
  }

  Future<void> report(WidgetTester tester, String? value) async {
    playback.report(value);
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'failure toast disappears after three seconds even if error persists',
    (tester) async {
      await mount(tester);
      await report(tester, 'fixture failure');
      expect(toast, findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(toast, findsNothing);
      expect(playback.error, isNotNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'recovery removes toast immediately and repeated player updates do not extend it',
    (tester) async {
      await mount(tester);
      await report(tester, 'first failure');
      await tester.pump(const Duration(seconds: 2));
      await report(tester, 'first failure');
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(toast, findsNothing);
      await report(tester, null);
      await report(tester, 'second failure');
      expect(toast, findsOneWidget);
      await report(tester, null);
      expect(toast, findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'rapid errors coalesce and raw engine details stay out of notification',
    (tester) async {
      await mount(tester);
      playback.report('fixture private diagnostics');
      playback.report('later diagnostics');
      await tester.pump();
      await tester.pump();
      expect(toast, findsOneWidget);
      expect(find.text('歌曲加载失败，请稍后重试'), findsOneWidget);
      expect(find.textContaining('diagnostics'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('toast is visible across routes and does not consume taps', (
    tester,
  ) async {
    await mount(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    var taps = 0;
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('route action'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await report(tester, 'fixture failure');
    expect(toast, findsOneWidget);
    await tester.tap(find.text('route action'));
    expect(taps, 1);
    nav.pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
