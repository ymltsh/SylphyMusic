/// One bounded same-track recovery episode. Detection timers may differ, but
/// every trigger must arrive at the same executor and follow the same budget.
/// No action here advances the queue, starts an FGS, or creates another Player.
enum AudioRecoveryAction { reloadAudioOutput, reopenSameTrack, failClosed }

AudioRecoveryAction nextAudioRecoveryAction({
  required bool isAndroid,
  required bool sourceIsLocal,
  required bool audioOutputReloadTried,
  required bool sameTrackReopenTried,
}) {
  if (sameTrackReopenTried) return AudioRecoveryAction.failClosed;
  if (isAndroid && sourceIsLocal && !audioOutputReloadTried) {
    return AudioRecoveryAction.reloadAudioOutput;
  }
  return AudioRecoveryAction.reopenSameTrack;
}
