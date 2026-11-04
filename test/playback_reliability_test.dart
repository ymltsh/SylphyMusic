import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/services/native_command_gate.dart';
import 'package:sylphy_music/services/playback_reliability.dart';

void main() {
  test('native commands never overlap', () async {
    final gate = NativeCommandGate();
    final entered = Completer<void>();
    final release = Completer<void>();
    final events = <String>[];
    final first = gate.run(() async {
      events.add('first-start');
      entered.complete();
      await release.future;
      events.add('first-end');
    }, isCurrent: () => true);
    await entered.future;
    final second = gate.run(() async {
      events.add('second');
    }, isCurrent: () => true);
    await Future<void>.delayed(Duration.zero);
    expect(events, ['first-start']);
    release.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(events, ['first-start', 'first-end', 'second']);
  });

  test('invalidated native command never runs', () async {
    final gate = NativeCommandGate();
    final release = Completer<void>();
    final entered = Completer<void>();
    var generation = 0;
    final first = gate.run(() async {
      entered.complete();
      await release.future;
    }, isCurrent: () => true);
    await entered.future;
    var ran = false;
    final pending = gate.run(() async {
      ran = true;
    }, isCurrent: () => generation == 0);
    generation = 1;
    release.complete();
    await first;
    expect(await pending, isFalse);
    expect(ran, isFalse);
  });

  test('local 403 is recoverable but upstream 403 is terminal', () {
    expect(
      classifyPlaybackFailure('HTTP 403', 'local_ticket_expired'),
      PlaybackFailureKind.localTicketExpired,
    );
    expect(
      classifyPlaybackFailure('HTTP 403', '403'),
      PlaybackFailureKind.authentication,
    );
    expect(
      classifyPlaybackFailure('HTTP 503', '503'),
      PlaybackFailureKind.retryable,
    );
    expect(
      classifyPlaybackFailure('HTTP 404', '404'),
      PlaybackFailureKind.missing,
    );
  });

  test('playback history retains the most recent 300 entries', () {
    var history = <int>[];
    for (var i = 0; i < 400; i++) {
      history = appendPlaybackHistory(history, i);
    }
    expect(history.length, 300);
    expect(history.first, 100);
    expect(history.last, 399);
  });
}
