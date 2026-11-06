import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/services/notification_clock.dart';

void main() {
  test('loading is frozen even if libmpv says playing', () {
    var now = Duration.zero;
    final clock = MediaNotificationClock(elapsed: () => now);
    clock.observe(Duration.zero, nativePlaying: true);
    now += const Duration(milliseconds: 500);
    clock.observe(const Duration(milliseconds: 500), nativePlaying: true);
    expect(
      clock.isAdvancing(
        playRequested: true,
        nativePlaying: true,
        opening: true,
        finishingTrack: false,
        buffering: false,
      ),
      isFalse,
    );
    expect(
      clock.isAdvancing(
        playRequested: true,
        nativePlaying: true,
        opening: false,
        finishingTrack: false,
        buffering: false,
      ),
      isTrue,
    );
  });

  test('sparse background callbacks do not toggle a confirmed clock', () {
    var now = Duration.zero;
    final clock = MediaNotificationClock(elapsed: () => now);
    bool advancing({bool buffering = false}) => clock.isAdvancing(
      playRequested: true,
      nativePlaying: true,
      opening: false,
      finishingTrack: false,
      buffering: buffering,
    );
    clock.observe(Duration.zero, nativePlaying: true);
    expect(advancing(), isFalse);
    now = const Duration(seconds: 1);
    clock.observe(const Duration(seconds: 1), nativePlaying: true);
    expect(advancing(), isTrue);
    now = const Duration(seconds: 4);
    expect(advancing(), isTrue); // Last callback 3s ago, audio not failed.
    clock.observe(const Duration(seconds: 4), nativePlaying: true);
    now = const Duration(seconds: 6);
    expect(advancing(), isTrue);
    expect(advancing(buffering: true), isFalse);
    now = const Duration(seconds: 11);
    expect(advancing(), isFalse); // 7s without confirmed progress.
    clock.reset();
    expect(advancing(), isFalse); // Old track/seek evidence never leaks.
  });

  test('paused or interrupted playback never advances', () {
    var now = Duration.zero;
    final clock = MediaNotificationClock(elapsed: () => now);
    clock.observe(Duration.zero, nativePlaying: true);
    now = const Duration(milliseconds: 500);
    clock.observe(const Duration(milliseconds: 500), nativePlaying: true);
    expect(
      clock.isAdvancing(
        playRequested: false,
        nativePlaying: true,
        opening: false,
        finishingTrack: false,
        buffering: false,
      ),
      isFalse,
    );
  });

  test('MediaSession gets stable anchors instead of each position tick', () {
    var now = Duration.zero;
    final gate = MediaSessionPublishGate(elapsed: () => now);
    bool emit(int positionMs, {double rate = 1, bool force = false}) =>
        gate.shouldPublish(
          mediaId: 'a',
          phase: 'ready',
          playRequested: true,
          position: Duration(milliseconds: positionMs),
          rate: rate,
          force: force,
        );
    expect(emit(0, rate: 0), isTrue); // Loading anchor.
    expect(emit(0, rate: 0), isFalse);
    now = const Duration(milliseconds: 600);
    expect(emit(600), isTrue); // First confirmed advancing anchor.
    now = const Duration(seconds: 3);
    expect(emit(3000), isFalse); // Native clock can extrapolate correctly.
    now = const Duration(seconds: 6);
    expect(emit(6000), isFalse);
    expect(emit(6000, rate: 0), isTrue); // Buffering/pausing freezes it.
    expect(emit(6000, rate: 0), isFalse);
    expect(emit(6100, rate: 0, force: true), isTrue); // Small seek.
  });

  test('clock drift and heartbeat re-anchor without flooding', () {
    var now = Duration.zero;
    final gate = MediaSessionPublishGate(elapsed: () => now);
    bool emit(int ms) => gate.shouldPublish(
      mediaId: 'a',
      phase: 'ready',
      playRequested: true,
      position: Duration(milliseconds: ms),
      rate: 1,
    );
    expect(emit(0), isTrue);
    now = const Duration(seconds: 1);
    expect(emit(3000), isTrue); // Large discontinuity.
    now = const Duration(seconds: 10);
    expect(emit(12000), isFalse);
    now = const Duration(seconds: 22);
    expect(emit(24000), isTrue); // Periodic drift correction.
  });
}
