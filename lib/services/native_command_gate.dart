import 'package:synchronized/synchronized.dart';

/// Serializes native player operations and rejects work invalidated while
/// waiting in the queue. The caller owns timeout and engine replacement.
class NativeCommandGate {
  final Lock _lock = Lock();

  Future<bool> run(
    Future<void> Function() operation, {
    required bool Function() isCurrent,
  }) => _lock.synchronized(() async {
    if (!isCurrent()) return false;
    await operation();
    return true;
  });
}
