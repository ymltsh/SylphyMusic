import 'dart:async';

import 'package:synchronized/synchronized.dart';

/// The command never entered the native gate within the allowed wait budget.
/// This does NOT imply it is safe to dispose an already running native call.
class NativeCommandQueueTimeout implements Exception {
  const NativeCommandQueueTimeout(this.maxWait);
  final Duration maxWait;

  @override
  String toString() => 'Native command queue timed out after $maxWait';
}

/// Serializes native player operations and rejects work invalidated while
/// waiting in the queue. The caller owns timeout and engine replacement.
class NativeCommandGate {
  final Lock _lock = Lock();

  Future<bool> run(
    Future<void> Function() operation, {
    required bool Function() isCurrent,
    Duration? maxQueueWait,
    void Function(Duration elapsed)? onQueueEntered,
  }) {
    final result = Completer<bool>();
    final queued = Stopwatch()..start();
    var abandoned = false;
    Timer? deadline;
    if (maxQueueWait != null) {
      deadline = Timer(maxQueueWait, () {
        // The stale closure remains in the lock's queue, but is guaranteed
        // not to touch the native player when the lock is eventually released.
        abandoned = true;
        if (!result.isCompleted) {
          result.completeError(NativeCommandQueueTimeout(maxQueueWait));
        }
      });
    }
    unawaited(
      _lock
          .synchronized(() async {
            deadline?.cancel();
            if (abandoned || !isCurrent()) return false;
            try {
              onQueueEntered?.call(queued.elapsed);
            } catch (_) {
              // Diagnostics must not prevent the command from executing.
            }
            await operation();
            return true;
          })
          .then(
            (value) {
              if (!result.isCompleted) result.complete(value);
            },
            onError: (Object error, StackTrace stack) {
              if (!result.isCompleted) result.completeError(error, stack);
            },
          ),
    );
    return result.future.whenComplete(() => deadline?.cancel());
  }
}
