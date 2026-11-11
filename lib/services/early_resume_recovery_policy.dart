/// Pure, bounded evidence checks for an Android cached/local-output resume.
/// These checks do not prove audible PCM: they require media-clock evidence and
/// reuse the existing once-per-intent AO recovery executor.
const int earlyResumePositionToleranceMs = 250;

/// A single sample is not sufficient to trigger recovery. Two separated
/// samples must both satisfy this predicate (at ~2s and ~3s).
bool isEarlyResumeStalledSample({
  required bool nativePlaying,
  required bool buffering,
  required bool busy,
  required bool progressConfirmed,
  required int baselinePositionMs,
  required int positionMs,
  required int progressGapMs,
  required int minProgressGapMs,
}) {
  return nativePlaying &&
      !buffering &&
      !busy &&
      !progressConfirmed &&
      (positionMs - baselinePositionMs).abs() <=
          earlyResumePositionToleranceMs &&
      progressGapMs >= minProgressGapMs;
}

/// The device, source and command-generation guards are rechecked by the
/// caller and again inside the single bounded recovery executor.
bool shouldAttemptEarlyAudioReload({
  required bool isAndroid,
  required bool reusedLocalOutput,
  required bool currentIntent,
  required bool firstProbeStalled,
  required bool secondProbeStalled,
  required bool recoveryIdle,
  required bool reloadNotTried,
}) {
  return isAndroid &&
      reusedLocalOutput &&
      currentIntent &&
      firstProbeStalled &&
      secondProbeStalled &&
      recoveryIdle &&
      reloadNotTried;
}
