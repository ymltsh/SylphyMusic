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

  test('expired queued native command cannot run after lock release', () async {
    final gate = NativeCommandGate();
    final entered = Completer<void>();
    final release = Completer<void>();
    var staleExecuted = false;
    final first = gate.run(() async {
      entered.complete();
      await release.future;
    }, isCurrent: () => true);
    await entered.future;
    final pending = gate.run(
      () async {
        staleExecuted = true;
      },
      isCurrent: () => true,
      maxQueueWait: const Duration(milliseconds: 10),
    );
    await expectLater(pending, throwsA(isA<NativeCommandQueueTimeout>()));
    release.complete();
    await first;
    final next = await gate.run(() async {}, isCurrent: () => true);
    expect(next, isTrue);
    expect(staleExecuted, isFalse);
  });

  test('long-paused proxied media refreshes, but fresh and local do not', () {
    final now = DateTime.utc(2026, 11, 6, 12);
    bool refresh({DateTime? ticket, DateTime? paused}) =>
        shouldRefreshRemotePlaybackSource(
          ticketIssuedAt: ticket,
          pausedAt: paused,
          now: now,
          ticketLifetime: const Duration(hours: 2),
        );
    expect(refresh(), isFalse); // Local file or complete READY cache.
    expect(refresh(ticket: now.subtract(const Duration(minutes: 5))), isFalse);
    expect(
      refresh(
        ticket: now.subtract(const Duration(minutes: 5)),
        paused: now.subtract(const Duration(minutes: 16)),
      ),
      isTrue,
    );
    expect(
      refresh(
        ticket: now.subtract(const Duration(minutes: 116)),
        paused: now.subtract(const Duration(minutes: 1)),
      ),
      isTrue,
    );
    expect(refresh(ticket: now.add(const Duration(minutes: 1))), isTrue);
  });

  test('long-paused HTTP proxy is reopened, not cached/local files', () {
    final now = DateTime.utc(2026, 11, 7, 8);
    bool reopen(bool proxy, Duration? age) => shouldReopenPausedProxy(
      usingProxy: proxy,
      pausedAt: age == null ? null : now.subtract(age),
      now: now,
    );
    expect(reopen(false, const Duration(hours: 3)), isFalse);
    expect(reopen(true, null), isFalse);
    expect(reopen(true, const Duration(minutes: 3)), isFalse);
    expect(reopen(true, const Duration(minutes: 15)), isTrue);
    expect(reopen(true, const Duration(hours: 3)), isTrue);
    expect(
      shouldReopenPausedProxy(
        usingProxy: true,
        pausedAt: now.add(const Duration(seconds: 1)),
        now: now,
      ),
      isTrue,
    );
  });

  test('cached file reopens only after long pause', () {
    final now = DateTime.utc(2026, 11, 8, 14);
    bool reopen(bool cached, Duration? pause) => shouldReopenPausedCache(
      usingCompleteCache: cached,
      pausedAt: pause == null ? null : now.subtract(pause),
      now: now,
    );
    expect(reopen(false, const Duration(hours: 1)), isFalse);
    expect(reopen(true, null), isFalse);
    expect(reopen(true, const Duration(minutes: 14)), isFalse);
    expect(reopen(true, const Duration(minutes: 15)), isTrue);
    expect(reopen(true, const Duration(hours: 3)), isTrue);
    expect(
      shouldReopenPausedCache(
        usingCompleteCache: true,
        pausedAt: now.add(const Duration(seconds: 1)),
        now: now,
      ),
      isTrue,
    );
  });

  test('unconfirmed resume never overrides a focus loss or newer command', () {
    bool attempt({
      bool current = true,
      bool request = true,
      bool paused = false,
      bool focusLost = false,
      bool progress = false,
      bool busy = false,
    }) => mayRecoverUnconfirmedResume(
      stillCurrent: current,
      playRequested: request,
      userPaused: paused,
      focusLost: focusLost,
      progressConfirmed: progress,
      recoveryRunning: busy,
    );
    expect(attempt(), isTrue);
    expect(attempt(current: false), isFalse);
    expect(attempt(request: false), isFalse);
    expect(attempt(paused: true), isFalse);
    expect(attempt(focusLost: true), isFalse);
    expect(attempt(progress: true), isFalse);
    expect(attempt(busy: true), isFalse);
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
