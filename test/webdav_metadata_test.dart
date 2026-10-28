import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/data/app_db.dart';
import 'package:sylphy_music/services/embedded_tags.dart';
import 'package:sylphy_music/services/sources.dart';
import 'package:sylphy_music/services/webdav_tags.dart';
import 'package:sylphy_music/services/webdav_metadata_enricher.dart';

import 'live_emby_test.dart' show MemoryVault;

class WaitingTags extends WebDavTags {
  WaitingTags() : super(AdapterFactory(MemoryVault()));
  final started = Completer<void>(), finish = Completer<void>();
  @override
  Future<EmbeddedTags> load(
    SourceProfile source,
    Track track, {
    bool force = false,
  }) async {
    if (!started.isCompleted) started.complete();
    await finish.future;
    return const EmbeddedTags();
  }
}

List<int> be(int n, int width) => [
  for (var i = width - 1; i >= 0; i--) (n >> (i * 8)) & 255,
];
List<int> le(int n, int width) => be(n, width).reversed.toList();
List<int> id3Frame(String id, String text) => [
  ...ascii.encode(id),
  ...be(utf8.encode(text).length + 1, 4),
  0,
  0,
  3,
  ...utf8.encode(text),
];
List<int> atom(String type, List<int> data) => [
  ...be(data.length + 8, 4),
  ...latin1.encode(type),
  ...data,
];
List<int> atomData(List<int> bytes) =>
    atom('data', [0, 0, 0, 1, 0, 0, 0, 0, ...bytes]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'v6 migration preserves tracks; disable and deletion reject pending tags',
    () async {
      final folder = await Directory.systemTemp.createTemp('dav-v6-');
      var db = AppDb(folder);
      await db.open();
      addTearDown(() async {
        await db.close();
        await folder.delete(recursive: true);
      });
      const source = SourceProfile(
        id: 'dav',
        name: 'fixture',
        kind: SourceKind.webdav,
        url: 'https://example.invalid',
        username: 'u',
      );
      const track = Track(
        ref: TrackRef('dav', 'song.mp3'),
        title: 'original',
        artist: 'folder',
        album: 'folder',
        remote: {'size': 123},
      );
      await db.putSource(source);
      await db.replaceSourceTracks(source.id, [track]);
      await db.db.execute('DROP TABLE webdav_track_tags');
      await db.db.execute(
        'ALTER TABLE index_tracks DROP COLUMN resource_version',
      );
      await db.db.execute('PRAGMA user_version=6');
      await db.close();
      db = AppDb(folder);
      await db.open();
      expect((await db.track(track.ref))!.title, 'original');
      expect(
        (await db.db.rawQuery('PRAGMA user_version')).single.values.single,
        7,
      );
      const tags = EmbeddedTags(artist: 'tag artist', album: 'tag album');
      await db.putSource(
        SourceProfile.fromRow({...source.toRow(), 'enabled': 0}),
      );
      expect(await db.putWebDavTags(track, tags), isFalse);
      await db.putSource(source);
      expect(await db.putWebDavTags(track, tags), isTrue);
      final reader = WaitingTags();
      final enricher = WebDavMetadataEnricher(db, reader);
      // Another track has no persisted tags and enters the visible-row path.
      const second = Track(
        ref: TrackRef('dav', 'second.mp3'),
        title: 'second',
        artist: '',
        album: '',
      );
      await db.replaceSourceTracks(source.id, [track, second]);
      enricher.prioritize([second]);
      await reader.started.future;
      var stopped = false;
      final shutdown = enricher.shutdown().then((_) {
        stopped = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(stopped, isFalse);
      reader.finish.complete();
      await shutdown;
      await reader.shutdown();
      await db.removeSourceData(source.id);
      expect(await db.db.query('webdav_track_tags'), isEmpty);
      expect(await db.putWebDavTags(track, tags), isFalse);
    },
  );

  test('ID3 textual music tags and existing cover/lyrics fields coexist', () {
    final frames = <int>[
      ...id3Frame('TIT2', '曲名'),
      ...id3Frame('TPE1', '歌手'),
      ...id3Frame('TPE2', '专辑艺术家'),
      ...id3Frame('TALB', '专辑'),
      ...id3Frame('TRCK', '3/12'),
      ...id3Frame('TPOS', '2/2'),
      ...id3Frame('TDRC', '2024-04-01'),
    ];
    // ID3v2.3 tag size uses four sync-safe bytes (small fixture).
    final size = frames.length;
    final bytes = Uint8List.fromList([
      73,
      68,
      51,
      3,
      0,
      0,
      (size >> 21) & 127,
      (size >> 14) & 127,
      (size >> 7) & 127,
      size & 127,
      ...frames,
    ]);
    final t = parseId3Tags(bytes);
    expect(t.title, '曲名');
    expect(t.artist, '歌手');
    expect(t.albumArtist, '专辑艺术家');
    expect(t.album, '专辑');
    expect(t.trackNumber, 3);
    expect(t.discNumber, 2);
    expect(t.year, 2024);
    expect(t.hasMusicMetadata, isTrue);
  });

  test('FLAC Vorbis comments extract artist, album, album artist', () {
    final comments = [
      'TITLE=曲名',
      'ARTIST=歌手',
      'ALBUM=专辑',
      'ALBUMARTIST=合辑艺术家',
      'TRACKNUMBER=4',
      'DATE=2022',
    ];
    final payload = <int>[
      ...le(0, 4), // empty vendor
      ...le(comments.length, 4),
      for (final value in comments) ...[
        ...le(utf8.encode(value).length, 4),
        ...utf8.encode(value),
      ],
    ];
    final tags = parseFlacTags(
      Uint8List.fromList([
        ...ascii.encode('fLaC'),
        0x84,
        ...be(payload.length, 3),
        ...payload,
      ]),
    );
    expect(tags.artist, '歌手');
    expect(tags.albumArtist, '合辑艺术家');
    expect(tags.album, '专辑');
    expect(tags.trackNumber, 4);
    expect(tags.year, 2022);
  });

  test('MP4 ilst extracts text and binary trkn', () {
    final ilst = <int>[
      ...atom('©nam', atomData(utf8.encode('曲名'))),
      ...atom('©ART', atomData(utf8.encode('艺术家'))),
      ...atom('aART', atomData(utf8.encode('专辑艺术家'))),
      ...atom('©alb', atomData(utf8.encode('专辑'))),
      ...atom('trkn', atomData([0, 0, 0, 5, 0, 10, 0, 0])),
    ];
    final bytes = Uint8List.fromList(
      atom(
        'moov',
        atom('udta', atom('meta', [0, 0, 0, 0, ...atom('ilst', ilst)])),
      ),
    );
    final tags = parseMp4Tags(bytes);
    expect(tags.title, '曲名');
    expect(tags.artist, '艺术家');
    expect(tags.albumArtist, '专辑艺术家');
    expect(tags.album, '专辑');
    expect(tags.trackNumber, 5);
  });

  test(
    'WebDAV re-sync keeps verified tags, but invalidates changed files',
    () async {
      final folder = await Directory.systemTemp.createTemp('sylphy-dav-tags-');
      final db = AppDb(folder);
      await db.open();
      addTearDown(() async {
        await db.close();
        await folder.delete(recursive: true);
      });
      const source = SourceProfile(
        id: 'dav',
        name: 'Dav',
        kind: SourceKind.webdav,
        url: 'https://example.invalid/music/',
        username: 'u',
      );
      await db.putSource(source);
      Track song(int size, String etag) => Track(
        ref: const TrackRef('dav', '/music/A/B/song.mp3'),
        title: 'song',
        artist: 'A',
        album: 'B',
        remote: {'size': size, 'etag': etag},
      );
      final initial = song(100, '"one"');
      await db.replaceSourceTracks('dav', [initial]);
      const tags = EmbeddedTags(
        title: '真实标题',
        artist: '真实艺术家',
        album: '真实专辑',
        albumArtist: '合辑作者',
        trackNumber: 3,
      );
      expect(await db.putWebDavTags(initial, tags), isTrue);
      expect(await db.hasWebDavTags(initial), isTrue);
      await db.stageIndexPage('run1', 'dav', [initial]);
      await db.commitIndex('run1', source);
      final preserved = await db.track(initial.ref);
      expect(preserved!.artist, '真实艺术家');
      expect(preserved.album, '真实专辑');
      expect(preserved.albumArtist, '合辑作者');
      expect(preserved.number, 3);

      final changed = song(101, '"two"');
      await db.stageIndexPage('run2', 'dav', [changed]);
      await db.commitIndex('run2', source);
      expect((await db.track(changed.ref))!.artist, 'A');
      expect(await db.hasWebDavTags(changed), isFalse);
      expect(await db.putWebDavTags(initial, tags), isFalse);
    },
  );
}
