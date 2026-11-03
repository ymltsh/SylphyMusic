/// Maximum age of confirmed media-position advancement before Android's
/// extrapolated notification position must be frozen.
const notificationProgressFreshness = Duration(milliseconds: 1500);

/// The play intent is deliberately distinct from the media clock: Android's
/// foreground service and pause button must survive opening/buffering, but
/// the notification must not count elapsed wall time until mpv progresses.
bool notificationClockRunning({
  required bool playRequested,
  required bool nativePlaying,
  required bool opening,
  required bool finishingTrack,
  required bool progressObserved,
  required Duration sinceProgress,
}) {
  return playRequested &&
      nativePlaying &&
      !opening &&
      !finishingTrack &&
      progressObserved &&
      sinceProgress < notificationProgressFreshness;
}
