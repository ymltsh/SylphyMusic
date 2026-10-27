import 'dart:async';

import 'package:flutter/foundation.dart';

/// One app-wide deadline, independent of player and lyrics routes.
class PlaybackSleepTimer extends ChangeNotifier {
  PlaybackSleepTimer({required this.onStop, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Future<void> Function() onStop;
  final DateTime Function() _now;
  DateTime? deadline;
  String? error;
  Timer? _timer;
  Future<void> _pending = Future.value();
  bool _closed = false;
  bool get active => deadline != null;
  Duration get remaining {
    final value = deadline?.difference(_now()) ?? Duration.zero;
    return value.isNegative ? Duration.zero : value;
  }

  void start(Duration duration) {
    if (_closed) return;
    if (duration <= Duration.zero) throw ArgumentError.value(duration);
    _timer?.cancel();
    error = null;
    deadline = _now().add(duration);
    _timer = Timer(duration, () => unawaited(checkDue()));
    notifyListeners();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    deadline = null;
    error = null;
    if (!_closed) notifyListeners();
  }

  /// Also called on app resume, in case the OS suspended Dart timers.
  Future<void> checkDue() {
    if (_closed || deadline == null) {
      return Future.value();
    }
    if (remaining > Duration.zero) {
      _timer?.cancel();
      _timer = Timer(remaining, () => unawaited(checkDue()));
      return Future.value();
    }
    cancel();
    _pending = _pending.then((_) => onStop()).catchError((Object _) {
      error = '定时停止失败，请手动暂停播放';
      if (!_closed) notifyListeners();
    });
    return _pending;
  }

  Future<void> shutdown() async {
    _closed = true;
    cancel();
    await _pending;
    dispose();
  }
}
