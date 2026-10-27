import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/services/diagnostic_logs.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sylphy-log-');
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('logging is off by default and does not create a file', () async {
    final logs = DiagnosticLogs(temp);
    logs.record('playback', 'completed');
    await logs.flush();
    expect(await File('${temp.path}/diagnostic.jsonl').exists(), isFalse);
    await logs.shutdown();
  });

  test(
    'toggle, export, and stop do not include events recorded while off',
    () async {
      final logs = DiagnosticLogs(temp);
      await logs.initialize(enabled: true);
      logs.record('playback', 'completed');
      await logs.setEnabled(false);
      logs.record('playback', 'ignored');
      final exported = utf8.decode(await logs.exportBytes());
      expect(exported, contains('"event":"completed"'));
      expect(exported, isNot(contains('ignored')));
      await logs.shutdown();
    },
  );

  test(
    'drop unsafe keys, URL strings, credentials and raw error text',
    () async {
      final logs = DiagnosticLogs(temp);
      await logs.setEnabled(true);
      logs.record(
        'proxy',
        'request_error',
        details: {
          'type': 'SocketException',
          'http_status': 503,
          'url': 'https://private.example/audio?token=abc',
          'token': 'secret',
          'source_kind': 'https://private.example',
          'stage': 'open',
        },
      );
      final exported = utf8.decode(await logs.exportBytes());
      final event = jsonDecode(
        exported.split('\n').firstWhere((s) => s.contains('request_error')),
      );
      expect(event['type'], 'SocketException');
      expect(event['http_status'], 503);
      expect(event['stage'], 'open');
      expect(event.containsKey('url'), false);
      expect(event.containsKey('token'), false);
      expect(event.containsKey('source_kind'), false);
      expect(exported, isNot(contains('private.example')));
      expect(exported, isNot(contains('secret')));
      await logs.shutdown();
    },
  );

  test('rotates old files and exports ordered chronological events', () async {
    final logs = DiagnosticLogs(temp, maxFileBytes: 220, retainedFiles: 3);
    await logs.setEnabled(true);
    for (var i = 0; i < 20; i++) {
      logs.record('playback', 'buffering', details: {'index': i});
    }
    final exported = utf8.decode(await logs.exportBytes());
    expect(exported, contains('"index":19'));
    expect(exported, isNot(contains('"index":0')));
    expect(await File('${temp.path}/diagnostic.3.jsonl').exists(), false);
    await logs.shutdown();
  });

  test('export waits for the in-flight write queue', () async {
    final logs = DiagnosticLogs(temp);
    await logs.setEnabled(true);
    for (var i = 0; i < 80; i++) {
      logs.record('playback', 'queued_event', details: {'index': i});
    }
    final exported = utf8.decode(await logs.exportBytes());
    expect(exported, contains('"index":79'));
    await logs.shutdown();
  });

  test('clear removes previous events and permits new logging', () async {
    final logs = DiagnosticLogs(temp);
    await logs.setEnabled(true);
    logs.record('playback', 'old_event');
    await logs.clear();
    logs.record('playback', 'new_event');
    final exported = utf8.decode(await logs.exportBytes());
    expect(exported, contains('new_event'));
    expect(exported, isNot(contains('old_event')));
    await logs.shutdown();
  });
}
