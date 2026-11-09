import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/services/audio_output_recovery_policy.dart';

void main() {
  AudioRecoveryAction choose({
    bool android = true,
    bool local = true,
    bool audioTried = false,
    bool reopenTried = false,
  }) => nextAudioRecoveryAction(
    isAndroid: android,
    sourceIsLocal: local,
    audioOutputReloadTried: audioTried,
    sameTrackReopenTried: reopenTried,
  );

  test('cached output first attempts AO reload', () {
    expect(choose(), AudioRecoveryAction.reloadAudioOutput);
  });
  test('ordinary local file first attempts AO reload', () {
    expect(choose(local: true), AudioRecoveryAction.reloadAudioOutput);
  });
  test('failed AO validation reopens same song', () {
    expect(choose(audioTried: true), AudioRecoveryAction.reopenSameTrack);
  });
  test('repeated failed same-song open stops, never skips', () {
    expect(
      choose(audioTried: true, reopenTried: true),
      AudioRecoveryAction.failClosed,
    );
  });
  test('remote streaming never treats proxy failure as AO failure', () {
    expect(choose(local: false), AudioRecoveryAction.reopenSameTrack);
  });
  test('remote retry is bounded', () {
    expect(
      choose(local: false, reopenTried: true),
      AudioRecoveryAction.failClosed,
    );
  });
  test('non-Android does not issue mpv Android AO reload', () {
    expect(choose(android: false), AudioRecoveryAction.reopenSameTrack);
  });
  test('reopen budget dominates all other steps', () {
    expect(choose(reopenTried: true), AudioRecoveryAction.failClosed);
  });
}
