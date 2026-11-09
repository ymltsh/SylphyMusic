import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/services/transient_focus_policy.dart';

void main() {
  test(
    'temporary loss preserves one resume across repeated loss callbacks',
    () {
      final focus = TransientFocusPolicy<String>();
      focus.transientLoss(wasPlayRequested: true, track: 'song-1');
      focus.transientLoss(wasPlayRequested: false, track: 'song-1');
      expect(focus.blocked, isTrue);
      expect(focus.armed, isTrue);
      expect(focus.foregroundHeld, isTrue);
      expect(focus.regained(), 'song-1');
      expect(focus.blocked, isFalse);
      expect(focus.armed, isFalse);
      expect(focus.foregroundHeld, isTrue);
      focus.progressConfirmed();
      expect(focus.foregroundHeld, isFalse);
    },
  );

  test('regain before any interruption never starts paused music', () {
    final focus = TransientFocusPolicy<String>();
    focus.transientLoss(wasPlayRequested: false, track: 'song-1');
    expect(focus.regained(), isNull);
    expect(focus.foregroundHeld, isFalse);
  });

  test('loss while the resume is pending re-arms the same track', () {
    final focus = TransientFocusPolicy<String>();
    focus.transientLoss(wasPlayRequested: true, track: 'song-1');
    expect(focus.regained(), 'song-1');
    focus.transientLoss(wasPlayRequested: false, track: 'song-1');
    expect(focus.regained(), 'song-1');
    focus.progressConfirmed();
    expect(focus.regained(), isNull);
  });

  test('user pause prevents all late auto-resume and demotes service', () {
    final focus = TransientFocusPolicy<String>();
    focus.transientLoss(wasPlayRequested: true, track: 'song-1');
    focus.cancel();
    expect(focus.regained(), isNull);
    expect(focus.foregroundHeld, isFalse);
  });

  test('permanent loss cancels an already armed transient resume', () {
    final focus = TransientFocusPolicy<String>();
    focus.transientLoss(wasPlayRequested: true, track: 'song-1');
    focus.permanentLoss();
    expect(focus.blocked, isTrue);
    expect(focus.regained(), isNull);
    expect(focus.foregroundHeld, isFalse);
  });

  test('expired hold cannot automatically resume after a late gain', () {
    final focus = TransientFocusPolicy<String>();
    focus.transientLoss(wasPlayRequested: true, track: 'song-1');
    focus.cancel(); // The coordinator's bounded timeout.
    expect(focus.regained(), isNull);
    expect(focus.foregroundHeld, isFalse);
  });

  test('foreground hold is independent of whether engine has progress', () {
    final focus = TransientFocusPolicy<String>();
    focus.transientLoss(wasPlayRequested: true, track: 'song-1');
    focus.regained();
    expect(focus.foregroundHeld, isTrue); // Still awaiting real mpv progress.
    focus.progressConfirmed();
    expect(focus.foregroundHeld, isFalse);
  });

  test('manual play cannot forge focus until it is actually granted', () {
    final focus = TransientFocusPolicy<String>();
    focus.permanentLoss();
    focus.cancel();
    expect(focus.blocked, isTrue);
    focus.focusGranted();
    expect(focus.blocked, isFalse);
  });
}
