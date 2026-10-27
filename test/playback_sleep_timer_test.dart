import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/services/playback_sleep_timer.dart';

void main() {
  testWidgets(
    'deadline pauses once and replacing or cancelling cancels old timers',
    (tester) async {
      var now = DateTime(2026);
      var stops = 0;
      final timer = PlaybackSleepTimer(
        onStop: () async {
          stops++;
        },
        now: () => now,
      );
      timer.start(const Duration(minutes: 15));
      now = now.add(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5));
      timer.start(const Duration(minutes: 30));
      now = now.add(const Duration(minutes: 10));
      await tester.pump(const Duration(minutes: 10));
      expect(stops, 0);
      expect(timer.remaining, const Duration(minutes: 20));
      now = now.add(const Duration(minutes: 20));
      await tester.pump(const Duration(minutes: 20));
      expect(stops, 1);
      expect(timer.active, isFalse);
      await timer.checkDue();
      expect(stops, 1);
      timer.start(const Duration(minutes: 15));
      timer.cancel();
      now = now.add(const Duration(minutes: 15));
      await tester.pump(const Duration(minutes: 15));
      expect(stops, 1);
      await timer.shutdown();
    },
  );

  testWidgets(
    'resume reconciles an elapsed deadline and reports stop failures',
    (tester) async {
      var now = DateTime(2026);
      final timer = PlaybackSleepTimer(
        onStop: () async {
          throw StateError('stop failed');
        },
        now: () => now,
      );
      timer.start(const Duration(minutes: 15));
      now = now.add(const Duration(minutes: 16));
      await timer.checkDue();
      expect(timer.active, isFalse);
      expect(timer.error, isNotNull);
      timer.cancel();
      expect(timer.error, isNull);
      await timer.shutdown();
    },
  );

  testWidgets('clock changes rearm and shutdown cancels pending expiry', (
    tester,
  ) async {
    var now = DateTime(2026);
    var stops = 0;
    final timer = PlaybackSleepTimer(
      onStop: () async {
        stops++;
      },
      now: () => now,
    );
    timer.start(const Duration(minutes: 15));
    // A backward wall-clock change must not silently lose the timer.
    await tester.pump(const Duration(minutes: 15));
    expect(stops, 0);
    now = now.add(const Duration(minutes: 15));
    await tester.pump(const Duration(minutes: 15));
    expect(stops, 1);
    timer.start(const Duration(minutes: 15));
    await timer.shutdown();
    now = now.add(const Duration(minutes: 15));
    await tester.pump(const Duration(minutes: 15));
    expect(stops, 1);
  });
}
