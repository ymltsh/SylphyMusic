import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';

import 'dart:convert';

import 'package:path/path.dart' as p;

import '../core/models.dart';
import 'embedded_tags.dart';

const audioExtensions = {
  '.mp3',
  '.flac',
  '.ogg',
  '.opus',
  '.wav',
  '.m4a',
  '.aac',
  '.ape',
  '.aiff',
};

class LocalLibrary {
  LocalLibrary(this.root);
  final Directory root;

  static Future<EmbeddedTags> embeddedAssets(File file) => Isolate.run(() {
    try {
      final reader = file.openSync();
      try {
        final header = reader.readSync(10);
        if (header.length == 10 &&
            ascii.decode(header.sublist(0, 3), allowInvalid: true) == 'ID3') {
          final size = tagUint(header, 6, 4, syncSafe: true);
          if (size > 12 * 1024 * 1024 || size + 10 > reader.lengthSync()) {
            return const EmbeddedTags();
          }
          return parseId3Tags(
            Uint8List.fromList([...header, ...reader.readSync(size)]),
          );
        }
      } finally {
        reader.closeSync();
      }
      final metadata = readMetadata(file, getImage: true);
      return EmbeddedTags(
        cover: metadata.pictures.isEmpty ? null : metadata.pictures.first.bytes,
        lyrics: metadata.lyrics,
        title: metadata.title,
        artist: metadata.artist,
        album: metadata.album,
        albumArtist: metadata.albumArtist,
        year: metadata.year?.year,
        trackNumber: metadata.trackNumber,
        discNumber: metadata.discNumber,
      );
    } catch (_) {
      return const EmbeddedTags();
    }
  });
  static Future<String?> embeddedLyrics(File file) async =>
      (await embeddedAssets(file)).lyrics;

  Future<Track> read(File file, String sourceId) =>
      Isolate.run(() => _read(file, sourceId));

  Track _read(File file, String sourceId) {
    final ref = TrackRef(sourceId, p.normalize(p.absolute(file.path)));
    final stat = file.statSync();
    final remote = <String, dynamic>{
      'path': file.path,
      'size': stat.size,
      'modified': stat.modified.millisecondsSinceEpoch,
      'format': p.extension(file.path).substring(1).toUpperCase(),
    };
    try {
      final metadata = readMetadata(file, getImage: true);
      if (metadata.pictures.isNotEmpty) {
        final cover = File(
          p.join(
            root.path,
            'artwork',
            '${sha256.convert(utf8.encode(ref.key))}.image',
          ),
        );
        cover.parent.createSync(recursive: true);
        cover.writeAsBytesSync(metadata.pictures.first.bytes, flush: true);
        remote['coverPath'] = cover.path;
      }
      if (metadata.lyrics?.isNotEmpty == true) {
        remote['lyrics'] = metadata.lyrics;
      }
      remote['sampleRate'] = metadata.sampleRate;
      remote['bitrate'] = metadata.bitrate;
      return Track(
        ref: ref,
        title: metadata.title?.trim().isNotEmpty == true
            ? metadata.title!
            : p.basenameWithoutExtension(file.path),
        artist: metadata.artist ?? '未知艺术家',
        album: metadata.album ?? '未知专辑',
        albumArtist: metadata.albumArtist ?? '',
        durationMs: metadata.duration?.inMilliseconds ?? 0,
        year: metadata.year?.year ?? 0,
        number: metadata.trackNumber ?? 0,
        disc: metadata.discNumber ?? 0,
        remote: remote,
      );
    } catch (_) {
      return Track(
        ref: ref,
        title: p.basenameWithoutExtension(file.path),
        artist: '未知艺术家',
        album: '未知专辑',
        remote: remote,
      );
    }
  }

  /// Android pickers may return an evictable provider copy. Own an import copy
  /// so playback survives a provider grant or temporary-file cleanup.
  Future<File> ownAndroidImport(File file) async {
    if (!Platform.isAndroid) return file;
    final directory = await Directory(p.join(root.path, 'local'))
        .create(recursive: true);
    final digest = await sha256.bind(file.openRead()).first;
    final destination = File(
      p.join(directory.path, '$digest${p.extension(file.path)}'),
    );
    if (!await destination.exists()) await file.copy(destination.path);
    final sidecar = File(p.setExtension(file.path, '.lrc'));
    if (await sidecar.exists()) {
      await sidecar.copy(p.setExtension(destination.path, '.lrc'));
    }
    return destination;
  }

  Future<List<Track>> scan(
    Directory directory,
    String sourceId,
    List<Track> previous,
  ) async {
    final old = {for (final track in previous) track.remote['path']: track};
    final result = <Track>[];
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File ||
          !audioExtensions.contains(p.extension(entity.path).toLowerCase())) {
        continue;
      }
      final stat = await entity.stat();
      final existing = old[entity.path];
      if (existing != null &&
          existing.remote['size'] == stat.size &&
          existing.remote['modified'] == stat.modified.millisecondsSinceEpoch) {
        result.add(existing);
      } else {
        result.add(await read(entity, sourceId));
      }
    }
    return result;
  }
}
