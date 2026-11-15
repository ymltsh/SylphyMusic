import 'dart:async';
import 'dart:math';

import '../core/models.dart';
import '../core/recommendation_models.dart';
import '../data/recommendation_repository.dart';
import 'listening_events.dart';
import 'playback.dart';

class _ActiveListen {
  _ActiveListen(this.ref, DateTime now, int nonce)
    : id = '${now.microsecondsSinceEpoch}-$nonce',
      startedAt = now.millisecondsSinceEpoch,
      localHour = now.hour,
      localWeekday = now.weekday,
      day = localDay(now);

  final TrackRef ref;
  final String id;
  final int startedAt, localHour, localWeekday;
  final String day;
  int listenedMs = 0;
  int lastPositionMs = -1;
  int lastClockMs = -1;
  int lastCheckpointMs = 0;
}

/// Listens to real playback progress, never to queue preparation or history UI.
/// All database writes are serialized, but no database call blocks native audio.
class ListeningAnalytics {
  ListeningAnalytics(this.playback, this.repository);
  final PlaybackCoordinator playback;
  final RecommendationRepository repository;
  final Stopwatch _clock = Stopwatch()..start();
  StreamSubscription<ListeningBoundary>? _boundaries;
  Future<void> _writes = Future<void>.value();
  _ActiveListen? _active;
  int _nonce = 0;
  bool _shuttingDown = false;
  bool _enabled = true;
  bool get enabled => _enabled;

  Future<void> initialize() async {
    _enabled =
        await repository.database.setting(
          'recommendation_personalization_enabled',
        ) !=
        'false';
    playback.addListener(_observe);
    _boundaries = playback.listeningBoundaries.listen(_boundary);
  }

  void _queue(
    _ActiveListen session, {
    bool completed = false,
    bool skipped = false,
  }) {
    final duration = playback.duration.inMilliseconds;
    final threshold = duration > 0
        ? min(30000, max(2000, duration ~/ 2))
        : 30000;
    final qualified = session.listenedMs >= threshold;
    final at = DateTime.now().millisecondsSinceEpoch;
    final listened = session.listenedMs;
    _writes = _writes
        .then(
          (_) => repository.checkpoint(
            sessionId: session.id,
            track: session.ref,
            startedAt: session.startedAt,
            updatedAt: at,
            hour: session.localHour,
            weekday: session.localWeekday,
            day: session.day,
            listenedMs: listened,
            qualified: qualified,
            completed: completed && duration > 0 && listened >= duration * 0.6,
            skipped:
                skipped &&
                listened >= 2000 &&
                listened < min(30000, duration > 0 ? duration * .3 : 30000),
          ),
        )
        .catchError((Object _) {
          // Statistics must not interrupt music or escape into native callbacks.
        });
    session.lastCheckpointMs = listened;
  }

  void _finish({bool completed = false, bool skipped = false}) {
    final session = _active;
    _active = null;
    if (session == null || session.listenedMs == 0) return;
    _queue(session, completed: completed, skipped: skipped);
  }

  void _boundary(ListeningBoundary boundary) {
    if (!_enabled) return;
    final active = _active;
    if (active == null || active.ref != boundary.track) return;
    _finish(
      completed:
          boundary.kind == ListeningBoundaryKind.completed ||
          boundary.kind == ListeningBoundaryKind.repeatOne,
      skipped: boundary.kind == ListeningBoundaryKind.manualSkip,
    );
  }

  void _observe() {
    if (_shuttingDown || !_enabled) return;
    final ref = playback.currentRef;
    if (_active != null && _active!.ref != ref) _finish();
    if (ref == null ||
        playback.error != null ||
        !playback.playing ||
        playback.buffering) {
      final active = _active;
      if (active != null) active.lastPositionMs = -1;
      return;
    }
    final position = playback.position.inMilliseconds;
    if (position < 0) return;
    var active = _active;
    if (active == null) {
      active = _ActiveListen(ref, DateTime.now(), ++_nonce);
      _active = active;
    }
    final nowMs = _clock.elapsedMilliseconds;
    final previous = active.lastPositionMs;
    final elapsed = active.lastClockMs < 0 ? 0 : nowMs - active.lastClockMs;
    final moved = previous < 0 ? 0 : position - previous;
    if (previous >= 0 && position + 1000 < previous) {
      // Backup for native repeat-one seeking to zero without changing TrackRef.
      _finish(
        completed:
            playback.duration.inMilliseconds > 0 &&
            previous >= playback.duration.inMilliseconds - 2500,
      );
      active = _ActiveListen(ref, DateTime.now(), ++_nonce);
      _active = active;
    } else if (moved > 0 &&
        elapsed > 0 &&
        elapsed <= 10000 &&
        moved <= elapsed * 2.5 + 750) {
      // Count wall time, not media position jumps, paused time or seek distance.
      active.listenedMs += min(moved, elapsed);
      if (active.listenedMs - active.lastCheckpointMs >= 15000) {
        _queue(active);
      }
    }
    active.lastPositionMs = position;
    active.lastClockMs = nowMs;
  }

  Future<void> setEnabled(bool value) async {
    if (!value) {
      _enabled = false;
      _finish();
    }
    await _writes;
    await repository.database.setSetting(
      'recommendation_personalization_enabled',
      value ? 'true' : 'false',
    );
    _enabled = value;
  }

  Future<void> forgetSource(String sourceId) async {
    if (_active?.ref.sourceId == sourceId) _finish();
    await _writes;
  }

  Future<void> clearStats() async {
    _finish();
    await _writes;
    await repository.clearAnalytics();
  }

  Future<void> shutdown() async {
    if (_shuttingDown) return;
    _shuttingDown = true;
    playback.removeListener(_observe);
    await _boundaries?.cancel();
    _finish();
    await _writes;
    _clock.stop();
  }
}
