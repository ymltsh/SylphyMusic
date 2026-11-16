import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import 'local_library.dart';

/// Android's SAF tree picker is not a filesystem Directory. The native side
/// enumerates the authorized tree and imports stable private copies for the
/// existing path-based playback engine. Other platforms keep their old path.
class AndroidLocalFolders {
  static const MethodChannel _channel = MethodChannel(
    'music.sylphy/local_folders',
  );

  static Future<({Uri uri, String name})?> pick() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('pick');
    if (result == null) return null;
    final uri = Uri.parse(result['uri'] as String);
    if (uri.scheme != 'content') {
      throw const FormatException('文件夹选择器未提供 SAF URI');
    }
    return (uri: uri, name: result['name'] as String? ?? '本地音乐文件夹');
  }

  static Future<SafFolderScan> scan({
    required Uri uri,
    required String sourceId,
    required Directory root,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('scan', {
      'uri': uri.toString(),
      'sourceId': sourceId,
      'root': root.path,
    });
    if (result == null) throw const FormatException('SAF 扫描未返回结果');
    return SafFolderScan.fromMap(result);
  }

  static Future<void> release(Uri uri) async {
    await _channel.invokeMethod<void>('release', {'uri': uri.toString()});
  }
}

class SafFolderFile {
  const SafFolderFile({
    required this.path,
    required this.name,
    required this.relativePath,
    required this.reused,
  });
  final String path, name, relativePath;
  final bool reused;
}

class SafFolderScan {
  const SafFolderScan({
    required this.files,
    required this.visitedCount,
    required this.copiedCount,
    required this.reusedCount,
  });
  final List<SafFolderFile> files;
  final int visitedCount, copiedCount, reusedCount;

  factory SafFolderScan.fromMap(Map<String, dynamic> value) {
    final files = (value['files'] as List<dynamic>?) ?? const [];
    return SafFolderScan(
      files: files
          .map((raw) {
            final entry = Map<String, dynamic>.from(raw as Map);
            return SafFolderFile(
              path: entry['path'] as String,
              name: entry['name'] as String,
              relativePath:
                  entry['relativePath'] as String? ?? entry['name'] as String,
              reused: entry['reused'] == true,
            );
          })
          .toList(growable: false),
      visitedCount: value['visited_count'] as int? ?? 0,
      copiedCount: value['copied_count'] as int? ?? 0,
      reusedCount: value['reused_count'] as int? ?? 0,
    );
  }

  /// A private copy's hashed filename is not a user-facing title. Keep the
  /// embedded tag when present, otherwise use the SAF display filename.
  Future<List<Track>> buildTracks(
    LocalLibrary scanner,
    String sourceId,
    List<Track> previous,
  ) async {
    final byPath = <String, Track>{
      for (final track in previous)
        if (track.remote['path'] is String)
          track.remote['path'] as String: track,
    };
    final tracks = <Track>[];
    for (final item in files) {
      final old = byPath[item.path];
      if (item.reused && old != null) {
        tracks.add(old);
        continue;
      }
      final file = File(item.path);
      if (!await file.exists()) {
        throw FileSystemException('导入后的歌曲文件不存在', item.path);
      }
      final track = await scanner.read(file, sourceId);
      final displayTitle = p.basenameWithoutExtension(item.name);
      final title = track.title == p.basenameWithoutExtension(item.path)
          ? displayTitle
          : track.title;
      tracks.add(
        Track(
          ref: track.ref,
          title: title,
          artist: track.artist,
          album: track.album,
          albumArtist: track.albumArtist,
          durationMs: track.durationMs,
          coverId: track.coverId,
          year: track.year,
          disc: track.disc,
          number: track.number,
          remote: {
            ...track.remote,
            'originalName': item.name,
            // Preserve the folder tree for LibraryCatalog; playback still reads
            // the private 'path' stored by LocalLibrary.read().
            'Path': item.relativePath,
          },
          missing: track.missing,
        ),
      );
    }
    return tracks;
  }
}
