import 'package:audio_service/audio_service.dart';

/// Platform-visible phases. These are intentionally independent of libmpv's
/// transient `playing` and `buffering` notifications.
enum MediaSessionPhase {
  idle,
  paused,
  focusHold,
  preparing,
  buffering,
  recovering,
  advancing,
  failed,
}

/// Immutable translation from one playback-runtime snapshot to MediaSession.
///
/// This does not own a Player, start a foreground service, or retry a source.
/// `sessionPlaying` communicates foreground-service continuity, while
/// `progressRate` communicates confirmed media-clock advancement. They must
/// never be conflated.
class MediaSessionProjection {
  const MediaSessionProjection._({
    required this.phase,
    required this.processingState,
    required this.sessionPlaying,
    required this.progressRate,
  });

  final MediaSessionPhase phase;
  final AudioProcessingState processingState;
  final bool sessionPlaying;
  final double progressRate;

  /// The visible play/pause button and the hardware toggle agree with the
  /// session's advertised activity, including a bounded transient focus hold.
  bool get showPause => sessionPlaying;

  static MediaSessionProjection fromRuntime({
    required bool hasTrack,
    required bool playWhenReady,
    required bool transientFocusHold,
    required bool progressAdvancing,
    required bool opening,
    required bool buffering,
    required bool recoveryInProgress,
    required bool terminalError,
    required double playbackSpeed,
  }) {
    if (!hasTrack) {
      return const MediaSessionProjection._(
        phase: MediaSessionPhase.idle,
        processingState: AudioProcessingState.idle,
        sessionPlaying: false,
        progressRate: 0,
      );
    }

    // Explicit playback intent wins over native loading/buffering flags. This
    // prevents a Pause pressed mid-buffer from leaving a spinning media card
    // or an unnecessary foreground service (Linthra #751).
    if (!playWhenReady) {
      if (transientFocusHold) {
        return const MediaSessionProjection._(
          phase: MediaSessionPhase.focusHold,
          processingState: AudioProcessingState.ready,
          sessionPlaying: true,
          progressRate: 0,
        );
      }
      if (terminalError) {
        return const MediaSessionProjection._(
          phase: MediaSessionPhase.failed,
          processingState: AudioProcessingState.error,
          sessionPlaying: false,
          progressRate: 0,
        );
      }
      return const MediaSessionProjection._(
        phase: MediaSessionPhase.paused,
        processingState: AudioProcessingState.ready,
        sessionPlaying: false,
        progressRate: 0,
      );
    }

    // Neither native.play() success nor AudioTrack PLAYSTATE_PLAYING is proof
    // of PCM progress. While the runtime is preparing/recovering or waiting
    // for a confirmed clock sample, retain FGS but freeze the system timeline.
    if (recoveryInProgress || opening || buffering || !progressAdvancing) {
      return MediaSessionProjection._(
        phase: recoveryInProgress
            ? MediaSessionPhase.recovering
            : opening
            ? MediaSessionPhase.preparing
            : MediaSessionPhase.buffering,
        processingState: AudioProcessingState.buffering,
        sessionPlaying: true,
        progressRate: 0,
      );
    }

    return MediaSessionProjection._(
      phase: MediaSessionPhase.advancing,
      processingState: AudioProcessingState.ready,
      sessionPlaying: true,
      progressRate: playbackSpeed > 0 ? playbackSpeed : 0,
    );
  }
}
