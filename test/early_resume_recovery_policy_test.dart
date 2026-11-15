import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/services/early_resume_recovery_policy.dart';

void main() {
  bool sample({
    bool nativePlaying = true,
    bool buffering = false,
    bool busy = false,
    bool progressConfirmed = false,
    int baselinePositionMs = 26597,
    int positionMs = 26581,
    int progressGapMs = 2059,
    int minProgressGapMs = 1800,
  }) => isEarlyResumeStalledSample(
    nativePlaying: nativePlaying,
    buffering: buffering,
    busy: busy,
    progressConfirmed: progressConfirmed,
    baselinePositionMs: baselinePositionMs,
    positionMs: positionMs,
    progressGapMs: progressGapMs,
    minProgressGapMs: minProgressGapMs,
  );

  bool decision({
    bool isAndroid = true,
    bool reusedLocalOutput = true,
    bool currentIntent = true,
    bool firstProbeStalled = true,
    bool secondProbeStalled = true,
    bool recoveryIdle = true,
    bool reloadNotTried = true,
  }) => shouldAttemptEarlyAudioReload(
    isAndroid: isAndroid,
    reusedLocalOutput: reusedLocalOutput,
    currentIntent: currentIntent,
    firstProbeStalled: firstProbeStalled,
    secondProbeStalled: secondProbeStalled,
    recoveryIdle: recoveryIdle,
    reloadNotTried: reloadNotTried,
  );

  test('small backward jitter and no progress count as stalled', () {
    expect(sample(), isTrue);
    expect(sample(progressGapMs: 3059, minProgressGapMs: 2500), isTrue);
    expect(decision(), isTrue);
  });

  test('progress over tolerance prevents recovery', () {
    expect(sample(positionMs: 26900), isFalse);
    expect(sample(positionMs: 26000), isFalse);
    expect(decision(firstProbeStalled: false), isFalse);
    expect(decision(secondProbeStalled: false), isFalse);
  });

  test('confirmed progress, buffering, pauses, seek or loading block', () {
    expect(sample(progressConfirmed: true), isFalse);
    expect(sample(buffering: true), isFalse);
    expect(sample(nativePlaying: false), isFalse);
    expect(sample(busy: true), isFalse);
    expect(sample(progressGapMs: 700), isFalse);
    expect(sample(progressGapMs: 2400, minProgressGapMs: 2500), isFalse);
  });

  test('only Android reused local/cache output is eligible', () {
    expect(decision(isAndroid: false), isFalse);
    expect(decision(reusedLocalOutput: false), isFalse);
    expect(decision(currentIntent: false), isFalse);
  });

  test('stale or competing attempts never trigger another reload', () {
    expect(decision(recoveryIdle: false), isFalse);
    expect(decision(reloadNotTried: false), isFalse);
  });
}
