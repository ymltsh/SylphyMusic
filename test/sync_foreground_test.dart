import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/services/sync_foreground.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lifecycle = MethodChannel('music.sylphy/sync_lifecycle');
  const permission = MethodChannel('music.sylphy/notification_permission');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late SyncForeground service;
  final calls = <String>[];
  var interrupted = 0, fail = false, running = false;
  setUp(() {
    interrupted = 0;
    fail = false;
    running = false;
    calls.clear();
    messenger.setMockMethodCallHandler(permission, (_) async {
      calls.add('permission');
      return null;
    });
    messenger.setMockMethodCallHandler(lifecycle, (call) async {
      calls.add(call.method);
      if (call.method == 'start') {
        if (fail) throw PlatformException(code: 'restricted');
        running = true;
      }
      if (call.method == 'stop') running = false;
      if (call.method == 'status') return running;
      return null;
    });
    service = SyncForeground(() => interrupted++, android: true);
  });
  tearDown(() {
    service.dispose();
    messenger.setMockMethodCallHandler(lifecycle, null);
    messenger.setMockMethodCallHandler(permission, null);
  });
  test(
    'start acknowledges service; progress throttles; stop removes service',
    () async {
      await service.start();
      await service.update('title', 'one');
      await service.update('title', 'two');
      expect(calls, ['permission', 'start', 'status', 'update']);
      await service.update('title', 'two', force: true);
      await service.stop();
      expect(running, isFalse);
    },
  );
  test('failed start propagates and later retry succeeds', () async {
    fail = true;
    await expectLater(service.start(), throwsA(isA<PlatformException>()));
    fail = false;
    await service.start();
    expect(running, isTrue);
    await service.stop();
  });
  test(
    'first scan waits until the notification permission prompt finishes',
    () async {
      final decision = Completer<void>();
      messenger.setMockMethodCallHandler(permission, (_) => decision.future);
      final start = service.start();
      await Future<void>.delayed(Duration.zero);
      expect(running, false);
      expect(calls, isEmpty);
      decision.complete();
      await start;
      expect(running, true);
      await service.stop();
    },
  );
  test('native pause and timeout interrupt the controller', () async {
    await service.start();
    for (final event in ['pause', 'timeout', 'unavailable']) {
      await messenger.handlePlatformMessage(
        'music.sylphy/sync_lifecycle',
        const StandardMethodCodec().encodeMethodCall(MethodCall(event)),
        (_) {},
      );
    }
    expect(interrupted, 3);
    await service.stop();
  });
  test('desktop sync does not call Android channels', () async {
    service.dispose();
    service = SyncForeground(() => interrupted++, android: false);
    await service.start();
    await service.update('title', 'detail');
    await service.stop();
    expect(calls, isEmpty);
  });
  test('native pause acknowledgement waits for asynchronous cleanup', () async {
    service.dispose();
    final cleaning = Completer<void>(), cleaned = Completer<void>();
    service = SyncForeground(() async {
      cleaning.complete();
      await cleaned.future;
      await service.stop();
    }, android: true);
    await service.start();
    var acknowledged = false;
    final message = messenger.handlePlatformMessage(
      'music.sylphy/sync_lifecycle',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('pause')),
      (_) {
        acknowledged = true;
      },
    );
    await cleaning.future;
    expect(acknowledged, isFalse);
    expect(running, isTrue);
    cleaned.complete();
    await message;
    expect(acknowledged, isTrue);
    expect(running, isFalse);
  });
}
