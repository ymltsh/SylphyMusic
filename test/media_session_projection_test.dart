import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/services/media_session_projection.dart';

void main() {
  MediaSessionProjection project({
    bool hasTrack = true,
    bool playWhenReady = true,
    bool transientFocusHold = false,
    bool progressAdvancing = false,
    bool opening = false,
    bool buffering = false,
    bool recoveryInProgress = false,
    bool terminalError = false,
    double playbackSpeed = 1.0,
  }) => MediaSessionProjection.fromRuntime(
    hasTrack: hasTrack,
    playWhenReady: playWhenReady,
    transientFocusHold: transientFocusHold,
    progressAdvancing: progressAdvancing,
    opening: opening,
    buffering: buffering,
    recoveryInProgress: recoveryInProgress,
    terminalError: terminalError,
    playbackSpeed: playbackSpeed,
  );

  test('idle session never claims foreground or progress', () {
    final result = project(hasTrack: false);
    expect(result.phase, MediaSessionPhase.idle);
    expect(result.processingState, AudioProcessingState.idle);
    expect(result.sessionPlaying, false);
    expect(result.progressRate, 0);
  });

  test('confirmed native progress advances only during actual playback', () {
    final result = project(progressAdvancing: true, playbackSpeed: 1.25);
    expect(result.phase, MediaSessionPhase.advancing);
    expect(result.processingState, AudioProcessingState.ready);
    expect(result.showPause, true);
    expect(result.progressRate, 1.25);
  });

  test('play command without progress stays buffering and frozen', () {
    final result = project();
    expect(result.phase, MediaSessionPhase.buffering);
    expect(result.processingState, AudioProcessingState.buffering);
    expect(result.sessionPlaying, true);
    expect(result.progressRate, 0);
  });

  test('loading next track preserves service but not false progress', () {
    final result = project(opening: true);
    expect(result.phase, MediaSessionPhase.preparing);
    expect(result.processingState, AudioProcessingState.buffering);
    expect(result.sessionPlaying, true);
    expect(result.progressRate, 0);
  });

  test('recovery owns phase even if stale progress sample exists', () {
    final result = project(recoveryInProgress: true, progressAdvancing: true);
    expect(result.phase, MediaSessionPhase.recovering);
    expect(result.progressRate, 0);
    expect(result.sessionPlaying, true);
  });

  test('pause during buffering is PAUSED and releases service', () {
    final result = project(
      playWhenReady: false,
      buffering: true,
      opening: true,
    );
    expect(result.phase, MediaSessionPhase.paused);
    expect(result.processingState, AudioProcessingState.ready);
    expect(result.showPause, false);
    expect(result.sessionPlaying, false);
  });

  test('bounded transient focus hold preserves FGS but freezes clock', () {
    final result = project(playWhenReady: false, transientFocusHold: true);
    expect(result.phase, MediaSessionPhase.focusHold);
    expect(result.processingState, AudioProcessingState.ready);
    expect(result.showPause, true);
    expect(result.sessionPlaying, true);
    expect(result.progressRate, 0);
  });

  test('terminal failure is actionable Play, not eternal buffering', () {
    final result = project(playWhenReady: false, terminalError: true);
    expect(result.phase, MediaSessionPhase.failed);
    expect(result.processingState, AudioProcessingState.error);
    expect(result.sessionPlaying, false);
    expect(result.showPause, false);
    expect(result.progressRate, 0);
  });

  test('ordinary pause dominates lingering transient native buffering', () {
    final result = project(
      playWhenReady: false,
      buffering: true,
      terminalError: false,
    );
    expect(result.phase, MediaSessionPhase.paused);
    expect(result.sessionPlaying, false);
  });

  test('nonpositive speed cannot make a running media clock', () {
    final result = project(progressAdvancing: true, playbackSpeed: 0);
    expect(result.progressRate, 0);
  });
}
