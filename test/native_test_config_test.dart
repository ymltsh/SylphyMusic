import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../flutter_test_config.dart' as config;

void main() {
  test('test worker discards stale pointers before startup and cleans its own file', () async {
    final reference = File(
      p.join(
        Directory.systemTemp.path,
        'com.alexmercerind.media_kit.NativeReferenceHolder.$pid',
      ),
    );
    final other = File('${reference.path}.unrelated');
    await reference.writeAsString('123456');
    await other.writeAsString('keep');
    try {
      await config.testExecutable(() async {
        expect(await reference.exists(), false);
        await reference.writeAsString('new allocation');
      });
      expect(await reference.exists(), false);
      expect(await other.readAsString(), 'keep');
    } finally {
      if (await reference.exists()) await reference.delete();
      await other.delete();
    }
  }, skip: !Platform.isWindows);

  test('failed test callback still removes its debug pointer file', () async {
    final reference = File(
      p.join(
        Directory.systemTemp.path,
        'com.alexmercerind.media_kit.NativeReferenceHolder.$pid',
      ),
    );
    await expectLater(
      config.testExecutable(() async {
        await reference.writeAsString('new allocation');
        throw StateError('fixture failure');
      }),
      throwsStateError,
    );
    expect(await reference.exists(), false);
  }, skip: !Platform.isWindows);
}
