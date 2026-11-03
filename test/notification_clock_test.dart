import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/services/notification_clock.dart';

void main() {
  bool running({
    bool playRequested = true,
    bool nativePlaying = true,
    bool opening = false,
    bool finishingTrack = false,
    bool progressObserved = true,
    Duration sinceProgress = Duration.zero,
  }) => notificationClockRunning(
    playRequested: playRequested,
    nativePlaying: nativePlaying,
    opening: opening,
    finishingTrack: finishingTrack,
    progressObserved: progressObserved,
    sinceProgress: sinceProgress,
  );

  test('keeps the notification clock stopped until real progress exists', () {
    expect(running(progressObserved: false), isFalse);
    expect(running(opening: true), isFalse);
    expect(running(nativePlaying: false), isFalse);
    expect(running(playRequested: false), isFalse);
    expect(running(finishingTrack: true), isFalse);
  });

  test('advances only while progress evidence is fresh', () {
    expect(running(), isTrue);
    expect(running(sinceProgress: const Duration(milliseconds: 1499)), isTrue);
    expect(running(sinceProgress: notificationProgressFreshness), isFalse);
    expect(running(sinceProgress: const Duration(seconds: 4)), isFalse);
  });

  test('seek invalidates old progress until audio advances again', () {
    // seek() clears progressObserved before awaiting the native seek.
    expect(running(progressObserved: false), isFalse);
    // The first confirmed post-seek advancement makes the clock live again.
    expect(running(progressObserved: true), isTrue);
  });

  test('buffering stalls freeze the clock without losing play intent', () {
    expect(
      running(
        playRequested: true,
        nativePlaying: true,
        sinceProgress: const Duration(seconds: 2),
      ),
      isFalse,
    );
  });
}
