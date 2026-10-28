import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/data/app_db.dart';
import 'package:sylphy_music/services/artwork.dart';
import 'package:sylphy_music/services/cache.dart';
import 'package:sylphy_music/services/embedded_tags.dart';
import 'package:sylphy_music/services/lyrics_store.dart';
import 'package:sylphy_music/services/media_assets.dart';
import 'package:sylphy_music/services/sources.dart';
import 'package:sylphy_music/services/webdav_tags.dart';

import 'live_emby_test.dart' show MemoryVault;
import 'media_proxy_test.dart' show NetworkTestBinding;

List<int> number(int value, int bytes, {bool sync = false}) => [
  for (var i = bytes - 1; i >= 0; i--)
    (value >> (i * (sync ? 7 : 8))) & (sync ? 127 : 255),
];
List<int> frame(String id, List<int> data, {bool v4 = false}) => [
  ...ascii.encode(id),
  ...number(data.length, 4, sync: v4),
  0,
  0,
  ...data,
];
Uint8List id3(List<int> data, {bool v4 = false}) => Uint8List.fromList([
  73,
  68,
  51,
  v4 ? 4 : 3,
  0,
  0,
  ...number(data.length, 4, sync: true),
  ...data,
]);
List<int> utf16(String text, {bool big = false}) => [
  for (final unit in text.codeUnits)
    ...big ? [unit >> 8, unit & 255] : [unit & 255, unit >> 8],
];
List<int> box(String type, List<int> data) => [
  ...number(data.length + 8, 4),
  ...latin1.encode(type),
  ...data,
];
final png = File('test/fixtures/cover.png').readAsBytesSync();
const lyric = '[00:01.00]中文歌词\n[00:02.00]第二行';
Uint8List fixture() => id3([
  ...frame('USLT', [3, ...ascii.encode('eng'), 0, ...utf8.encode(lyric)]),
  ...frame('APIC', [0, ...ascii.encode('image/png'), 0, 3, 0, ...png]),
]);

void main() {
  NetworkTestBinding();
  test(
    'ID3 v2.3/v2.4 USLT encodings preserve all first characters and BOM',
    () {
      for (final enc in [0, 1, 2, 3]) {
        for (final v4 in [false, true]) {
          final text = enc == 0 ? '[00:01.00]Latin' : lyric;
          final encoded = enc == 0
              ? latin1.encode(text)
              : enc == 3
              ? utf8.encode(text)
              : [
                  ...enc == 1 ? [255, 254] : <int>[],
                  ...utf16(text, big: enc == 2),
                ];
          final descriptor = enc == 1
              ? [255, 254, ...utf16('说明'), 0, 0]
              : enc == 2
              ? [...utf16('说明', big: true), 0, 0]
              : [0];
          final tags = parseId3Tags(
            id3(
              frame('USLT', [
                enc,
                ...ascii.encode('eng'),
                ...descriptor,
                ...encoded,
              ], v4: v4),
              v4: v4,
            ),
          );
          expect(tags.lyrics, text);
        }
      }
      expect(parseId3Tags(fixture()).cover, png);
    },
  );
  test('SYLT milliseconds become timed LRC and malformed optional frames do not hide cover', () {
    final tags = parseId3Tags(
      id3([
        ...frame('USLT', [3, 1]),
        ...frame('SYLT', [
          3,
          ...ascii.encode('eng'),
          2,
          1,
          0,
          ...utf8.encode('第一行'),
          0,
          ...number(1234, 4),
          ...utf8.encode('第二行'),
          0,
          ...number(62345, 4),
        ]),
        ...frame('APIC', [0, ...ascii.encode('image/png'), 0, 3, 0, ...png]),
      ]),
    );
    expect(tags.lyrics, '[00:01.234]第一行\n[01:02.345]第二行');
    expect(tags.cover, png);
  });
  test(
    'FLAC comments/picture and MP4 moov lyrics/cover parse bounded regions',
    () {
      final text = utf8.encode('LYRICS=$lyric');
      List<int> le(int n) => number(n, 4).reversed.toList();
      final comments = [...le(0), ...le(1), ...le(text.length), ...text];
      final picture = [
        ...number(3, 4),
        ...number(9, 4),
        ...ascii.encode('image/png'),
        ...number(0, 4),
        ...List.filled(16, 0),
        ...number(png.length, 4),
        ...png,
      ];
      final tags = parseFlacTags(
        Uint8List.fromList([
          ...ascii.encode('fLaC'),
          4,
          ...number(comments.length, 3),
          ...comments,
          134,
          ...number(picture.length, 3),
          ...picture,
        ]),
      );
      expect(tags.lyrics, lyric);
      expect(tags.cover, png);
      final mp4 = parseMp4Tags(
        Uint8List.fromList(
          box(
            'moov',
            box(
              'udta',
              box('meta', [
                0,
                0,
                0,
                0,
                ...box('ilst', [
                  ...box(
                    '©lyr',
                    box('data', [
                      0,
                      0,
                      0,
                      1,
                      0,
                      0,
                      0,
                      0,
                      ...utf8.encode(lyric),
                    ]),
                  ),
                  ...box(
                    'covr',
                    box('data', [0, 0, 0, 14, 0, 0, 0, 0, ...png]),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      );
      expect(mp4.lyrics, lyric);
      expect(mp4.cover, png);
    },
  );

  group('bounded WebDAV tags', () {
    late HttpServer server;
    late SourceProfile source;
    late WebDavTags tags;
    late MemoryVault vault;
    late Uint8List bytes;
    List<int> tail = [];
    var hits = 0, sent = 0, mode = 'normal';
    Completer<void>? arrived, unblock;
    Track track({String name = 'song.mp3', String version = '"v1"'}) => Track(
      ref: TrackRef('dav', name),
      title: '',
      artist: '',
      album: '',
      coverId: 'cover.png',
      remote: {'format': 'MP3', 'size': 20 * 1024 * 1024, 'etag': version},
    );
    setUp(() async {
      hits = 0;
      sent = 0;
      mode = 'normal';
      arrived = null;
      unblock = null;
      bytes = fixture();
      tail = [];
      vault = MemoryVault();
      await vault.write('dav', 'password', 'secret');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      source = SourceProfile(
        id: 'dav',
        name: 'fixture',
        kind: SourceKind.webdav,
        url: 'http://127.0.0.1:${server.port}/dav',
        username: 'user',
      );
      tags = WebDavTags(AdapterFactory(vault));
      server.listen((r) async {
        hits++;
        expect(
          r.headers.value('authorization'),
          'Basic ${base64Encode(utf8.encode('user:secret'))}',
        );
        expect(r.method, 'GET');
        if (r.headers.value('range') == null) {
          if (r.uri.path.endsWith('.png')) {
            r.response.add(png);
          } else if (r.uri.path.endsWith('.lrc')) {
            r.response.add(utf8.encode(lyric));
          } else {
            r.response.statusCode = 404;
          }
          await r.response.close();
          return;
        }
        if (mode == 'blocked') {
          arrived?.complete();
          await unblock!.future;
        }
        final range = RegExp(r'bytes=(\d+)-(\d+)')
            .firstMatch(r.headers.value('range')!)!;
        final start = int.parse(range[1]!), end = int.parse(range[2]!);
        if (mode == 'ignore') {
          r.response.statusCode = 200;
          await r.response.close();
          return;
        }
        r.response.statusCode = 206;
        r.response.headers.set(
          'Content-Range',
          'bytes $start-${mode == 'bad-range' ? end + 1 : end}/${20 * 1024 * 1024}',
        );
        r.response.headers.set('ETag', mode == 'changed' ? '"v2"' : '"v1"');
        if (mode == 'oversize') {
          bytes = id3([]);
          bytes.setRange(6, 10, number(WebDavTags.maxBytes, 4, sync: true));
        }
        final chunk = List<int>.generate(end - start + 1, (i) {
          final p = start + i;
          if (p < bytes.length) return bytes[p];
          final q = p - (20 * 1024 * 1024 - tail.length);
          return q >= 0 && q < tail.length ? tail[q] : 0;
        });
        sent += chunk.length;
        r.response.add(chunk);
        try {
          await r.response.close();
        } catch (_) {
          /* cancelled */
        }
      });
    });
    tearDown(() async {
      unblock?.complete();
      await tags.shutdown();
      await server.close(force: true);
    });
    test('coalesces cover and lyric reads; transfers tags only; version changes invalidate recent result', () async {
      final result = await Future.wait([
        tags.load(source, track()),
        tags.load(source, track()),
      ]);
      expect(result.first.cover, png);
      expect(result.last.lyrics, lyric);
      expect(hits, 2);
      expect(sent, bytes.length);
      await tags.load(source, track());
      expect(hits, 2);
      await tags.load(source, track(version: '"v2"'));
      expect(hits, 3);
    });
    for (final failure in ['ignore', 'bad-range', 'changed', 'oversize']) {
      test('rejects $failure before downloading audio', () async {
        mode = failure;
        final result = await tags.load(source, track());
        expect(result.cover, isNull);
        expect(result.lyrics, isNull);
        expect(hits, 1);
      });
    }
    test(
      'M4A locates moov after a large mdat without fetching audio',
      () async {
        tail = box(
          'moov',
          box(
            'udta',
            box('meta', [
              0,
              0,
              0,
              0,
              ...box('ilst', [
                ...box(
                  '©lyr',
                  box('data', [0, 0, 0, 1, 0, 0, 0, 0, ...utf8.encode(lyric)]),
                ),
                ...box('covr', box('data', [0, 0, 0, 14, 0, 0, 0, 0, ...png])),
              ]),
            ]),
          ),
        );
        final ftyp = box('ftyp', ascii.encode('M4A     '));
        bytes = Uint8List.fromList([
          ...ftyp,
          ...number(20 * 1024 * 1024 - ftyp.length - tail.length, 4),
          ...ascii.encode('mdat'),
        ]);
        final result = await tags.load(source, track(name: 'song.m4a'));
        expect(result.lyrics, lyric);
        expect(result.cover, png);
        expect(sent, lessThan(tail.length + 100));
      },
    );
    test('sidecars remain available when no embedded tags or range support exist; manual lyrics win', () async {
      mode = 'ignore';
      final root = await Directory.systemTemp.createTemp('dav-sidecar-');
      final db = AppDb(root);
      await db.open();
      await db.putSource(source);
      final assets = MediaAssetStore(db, root, freeSpace: () async => 1000);
      await assets.initialize();
      final cache = CacheManager(db, AdapterFactory(vault), root);
      final art = ArtworkStore(
        db,
        AdapterFactory(vault),
        root,
        assets: assets,
        tags: tags,
      );
      final lyrics = LyricsStore(
        db,
        AdapterFactory(vault),
        assets,
        cache,
        root,
        tags: tags,
      );
      try {
        expect(await art.load(track()), isNotNull);
        expect(await lyrics.load(track()), lyric);
        final imported = File('${root.path}/manual.lrc');
        await imported.writeAsString('manual');
        await lyrics.importFile(track(), imported);
        final before = hits;
        expect(await lyrics.load(track(), forceRefresh: true), 'manual');
        expect(hits, before);
      } finally {
        await art.shutdown();
        await lyrics.shutdown();
        await cache.shutdown();
        await assets.shutdown();
        await db.close();
        await root.delete(recursive: true);
      }
    });
    test(
      'suspending source cancels pending tags and prevents stale publication',
      () async {
        mode = 'blocked';
        arrived = Completer<void>();
        unblock = Completer<void>();
        final result = tags.load(source, track());
        await arrived!.future;
        tags.suspendSource(source.id);
        expect((await result).cover, isNull);
      },
    );
    test('stores embedded assets before READY, distinguishes tracks sharing folder art, and reopens offline', () async {
      final root = await Directory.systemTemp.createTemp('dav-tags-');
      var db = AppDb(root);
      await db.open();
      await db.putSource(source);
      var assets = MediaAssetStore(db, root, freeSpace: () async => 1000);
      await assets.initialize();
      var cache = CacheManager(db, AdapterFactory(vault), root);
      var art = ArtworkStore(
        db,
        AdapterFactory(vault),
        root,
        assets: assets,
        tags: tags,
      );
      var lyrics = LyricsStore(
        db,
        AdapterFactory(vault),
        assets,
        cache,
        root,
        tags: tags,
      );
      try {
        expect(art.key(track()), isNot(art.key(track(name: 'other.mp3'))));
        final result = await Future.wait<Object?>([
          art.load(track()),
          lyrics.load(track()),
        ]);
        expect(await (result[0] as File).readAsBytes(), png);
        expect(result[1], lyric);
        expect(await cache.find(track().ref), isNull);
        expect(hits, 2);
        await art.shutdown();
        await lyrics.shutdown();
        await cache.shutdown();
        await assets.shutdown();
        await db.close();
        mode = 'ignore';
        final previousHits = hits;
        db = AppDb(root);
        await db.open();
        assets = MediaAssetStore(db, root, freeSpace: () async => 1000);
        await assets.initialize();
        cache = CacheManager(db, AdapterFactory(vault), root);
        art = ArtworkStore(
          db,
          AdapterFactory(vault),
          root,
          assets: assets,
          tags: tags,
        );
        lyrics = LyricsStore(
          db,
          AdapterFactory(vault),
          assets,
          cache,
          root,
          tags: tags,
        );
        expect(await art.load(track()), isNotNull);
        expect(await lyrics.load(track()), lyric);
        expect(hits, previousHits);
      } finally {
        await art.shutdown();
        await lyrics.shutdown();
        await cache.shutdown();
        await assets.shutdown();
        await db.close();
        await root.delete(recursive: true);
      }
    });
  });
}
