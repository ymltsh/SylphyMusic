/// Single authority for a transient-focus resume entitlement and its temporary
/// Android foreground-service hold. This class deliberately does NOT own a
/// player, timer, service, or audio focus request; those are platform effects.
///
/// A media session can need to remain foreground even while the native engine
/// is physically paused. The UI's desire to play is not changed by a temporary
/// interruption. Permanent loss, a user pause or an expired hold revokes the
/// entitlement. A matching regain does not release the foreground hold until
/// real media progress is confirmed.
class TransientFocusPolicy<T> {
  T? _resumeTrack;
  bool _blocked = false;
  bool _armed = false;
  bool _foregroundHeld = false;

  bool get blocked => _blocked;
  bool get armed => _armed;
  bool get foregroundHeld => _foregroundHeld;

  /// Repeated transient losses during the same interruption must not disarm an
  /// already-valid resume just because the engine has since been paused.
  void transientLoss({required bool wasPlayRequested, required T? track}) {
    _blocked = true;
    if (_foregroundHeld && _resumeTrack != null) {
      _armed = true;
    } else if (wasPlayRequested && track != null) {
      _resumeTrack = track;
      _armed = true;
      _foregroundHeld = true;
    }
  }

  /// Consumes the automatic transport request, not the foreground hold.
  /// The latter survives the pause -> native play -> first progress gap.
  T? regained() {
    _blocked = false;
    if (!_armed) return null;
    _armed = false;
    return _resumeTrack;
  }

  /// Explicit play is still subject to AudioSession.setActive(true). Only its
  /// successful result can clear a previously-observed focus block.
  void focusGranted() {
    _blocked = false;
  }

  void permanentLoss() {
    _blocked = true;
    cancel();
  }

  /// A user command, failed recovery or hold expiration revokes both rights.
  /// This intentionally does not forge a focus-GAIN event.
  void cancel() {
    _armed = false;
    _foregroundHeld = false;
    _resumeTrack = null;
  }

  void progressConfirmed() => cancel();
}
