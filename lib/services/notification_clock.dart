/// A single source of truth for the system media clock.  MediaSession should
/// receive position *anchors*, not a fresh PlaybackState on every mpv tick.
///
/// Time here is monotonic. Only the Android bridge converts an emitted anchor
/// to the platform's elapsedRealtime timebase.
class MediaNotificationClock {
  MediaNotificationClock({Duration Function()? elapsed}) : _elapsed = elapsed;

  static const noProgressTimeout = Duration(seconds: 6);
  static const bufferingGrace = Duration(seconds: 2);
  static const minAdvance = Duration(milliseconds: 80);
  static const maxContinuousAdvance = Duration(seconds: 4);

  final Stopwatch _stopwatch = Stopwatch()..start();
  final Duration Function()? _elapsed;
  Duration get _now => _elapsed?.call() ?? _stopwatch.elapsed;

  int? _previousPositionMs;
  Duration? _lastAdvancement;

  /// Drop evidence from the previous media, an old seek, or a paused decoder.
  /// A new period of real mpv position advancement must re-arm the clock.
  void reset() {
    _previousPositionMs = null;
    _lastAdvancement = null;
  }

  /// Called on *every* native position sample, independent of UI refresh rate.
  /// A discontinuity is not proof of playback. The caller resets on seek.
  void observe(Duration position, {required bool nativePlaying}) {
    final next = position.inMilliseconds;
    final previous = _previousPositionMs;
    _previousPositionMs = next;
    if (!nativePlaying || previous == null) return;
    final delta = Duration(milliseconds: next - previous);
    if (delta >= minAdvance && delta <= maxContinuousAdvance) {
      _lastAdvancement = _now;
    }
  }

  bool isAdvancing({
    required bool playRequested,
    required bool nativePlaying,
    required bool opening,
    required bool finishingTrack,
    required bool buffering,
  }) {
    if (!playRequested || !nativePlaying || opening || finishingTrack) {
      return false;
    }
    final last = _lastAdvancement;
    if (last == null) return false;
    final age = _now - last;
    if (age.isNegative) return false;
    // A buffering flag may lag behind real audio output. Actual progress is
    // authoritative, but a genuinely stalled buffer freezes quickly.
    return age < (buffering ? bufferingGrace : noProgressTimeout);
  }
}

/// Coalesces native MediaSession messages. Android extrapolates the position
/// using the last anchor and speed; ordinary mpv position ticks must NOT reset
/// that anchor or churn the notification's playback state.
class MediaSessionPublishGate {
  MediaSessionPublishGate({Duration Function()? elapsed}) : _elapsed = elapsed;

  static const driftTolerance = Duration(milliseconds: 1200);
  static const maxAnchorAge = Duration(seconds: 20);

  final Stopwatch _stopwatch = Stopwatch()..start();
  final Duration Function()? _elapsed;
  Duration get _now => _elapsed?.call() ?? _stopwatch.elapsed;

  bool _hasAnchor = false;
  String? _mediaId;
  String? _phase;
  bool _playRequested = false;
  double _rate = 0;
  int _positionMs = 0;
  Duration _at = Duration.zero;

  bool shouldPublish({
    required String? mediaId,
    required String phase,
    required bool playRequested,
    required Duration position,
    required double rate,
    bool force = false,
  }) {
    final now = _now;
    final elapsed = now - _at;
    final projected =
        _positionMs + (elapsed.inMicroseconds / 1000 * _rate).round();
    final drift = (position.inMilliseconds - projected).abs();
    final changed =
        !_hasAnchor ||
        _mediaId != mediaId ||
        _phase != phase ||
        _playRequested != playRequested ||
        _rate != rate;
    final needsCorrection =
        drift > driftTolerance.inMilliseconds ||
        (rate > 0 && elapsed >= maxAnchorAge);
    if (!force && !changed && !needsCorrection) return false;
    _hasAnchor = true;
    _mediaId = mediaId;
    _phase = phase;
    _playRequested = playRequested;
    _rate = rate;
    _positionMs = position.inMilliseconds;
    _at = now;
    return true;
  }
}
