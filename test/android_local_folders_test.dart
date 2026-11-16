import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/services/android_local_folders.dart';
import 'package:sylphy_music/services/local_library.dart';

void main() {
  test('SAF result parses counts and stable paths', () {
    final scan = SafFolderScan.fromMap({
      'files': [
        {'name': '中文歌曲.mp3', 'path': '/tmp/abcd.mp3', 'reused': true},
      ],
      'visited_count': 4,
      'copied_count': 0,
      'reused_count': 1,
    });
    expect(scan.files.single.name, '中文歌曲.mp3');
    expect(scan.files.single.reused, true);
    expect(scan.visitedCount, 4);
  });

  test('SAF audio keeps embedded tags and reuses unchanged files', () async {
    final root = await Directory.systemTemp.createTemp('sylphy-saf-test-');
    try {
      final audio = File('${root.path}/abcdef.mp3');
      await File('test/fixtures/tone.mp3').copy(audio.path);
      final scan = SafFolderScan.fromMap({
        'files': [
          {'name': '原始曲目.mp3', 'path': audio.path, 'reused': false},
        ],
      });
      final tracks = await scan.buildTracks(LocalLibrary(root), 'source', []);
      // Tagged test/fixtures/tone.mp3 must keep its embedded title.
      expect(tracks.single.title, 'Sylphy MP3');
      expect(tracks.single.remote['originalName'], '原始曲目.mp3');
      expect(tracks.single.remote['Path'], '原始曲目.mp3');
      final reused = SafFolderScan.fromMap({
        'files': [
          {'name': '原始曲目.mp3', 'path': audio.path, 'reused': true},
        ],
      });
      final next = await reused.buildTracks(
        LocalLibrary(root),
        'source',
        tracks,
      );
      expect(identical(next.single, tracks.single), isTrue);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('untagged SAF audio uses original filename, not private hash', () async {
    final root = await Directory.systemTemp.createTemp('sylphy-saf-untagged-');
    try {
      final audio = File('${root.path}/hashed.mp3');
      await audio.writeAsBytes([1, 2, 3]);
      final scan = SafFolderScan.fromMap({
        'files': [
          {
            'name': '中文文件名.mp3',
            'relativePath': '子目录/中文文件名.mp3',
            'path': audio.path,
            'reused': false,
          },
        ],
      });
      final tracks = await scan.buildTracks(LocalLibrary(root), 'source', []);
      expect(tracks.single.title, '中文文件名');
      expect(tracks.single.remote['Path'], '子目录/中文文件名.mp3');
    } finally {
      await root.delete(recursive: true);
    }
  });
}
