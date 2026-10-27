import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/services/local_library.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sylphy-tags-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test('MP3 ID3 and 96k FLAC metadata are indexed', () async {
    final scanner = LocalLibrary(root);
    final mp3 = await scanner.read(File('test/fixtures/tone.mp3'), 'local');
    final flac = await scanner.read(File('test/fixtures/tone.flac'), 'local');
    expect(mp3.title, 'Sylphy MP3');
    expect(mp3.artist, 'Test Artist');
    expect(mp3.album, 'Test Album');
    expect(mp3.number, 1);
    expect(mp3.year, 2026);
    expect(mp3.durationMs, greaterThanOrEqualTo(1900));
    expect(flac.title, 'Sylphy FLAC');
    expect(flac.albumArtist, 'Album Artist');
    expect(flac.remote['sampleRate'], 96000);
    expect(flac.number, 2);
  });
  test('embedded cover extraction remains scoped to exact TrackRef', () async {
    final scanner = LocalLibrary(root),
        file = File('test/fixtures/covered.mp3');
    final a = await scanner.read(file, 'a'), b = await scanner.read(file, 'b');
    expect(a.remote['coverPath'], isNotNull);
    expect(a.remote['coverPath'], isNot(b.remote['coverPath']));
    expect(
      await File(a.remote['coverPath'] as String).readAsBytes(),
      await File('test/fixtures/cover.png').readAsBytes(),
    );
  });
  test(
    'scan soft removal input and unchanged files preserve references',
    () async {
      final folder = await Directory('${root.path}/music').create();
      final file = await File('test/fixtures/tone.mp3')
          .copy('${folder.path}/track.mp3');
      final scanner = LocalLibrary(root);
      final first = await scanner.scan(folder, 'source', []);
      final second = await scanner.scan(folder, 'source', first);
      expect(second.single.ref, first.single.ref);
      expect(identical(second.single, first.single), isTrue);
      await file.delete();
      expect(await scanner.scan(folder, 'source', second), isEmpty);
    },
  );
}
