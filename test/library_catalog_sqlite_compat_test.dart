import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/data/app_db.dart';
import 'package:sylphy_music/data/library_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppDb db;
  late LibraryCatalog catalog;

  SourceProfile source(String id, SourceKind kind) => SourceProfile(
    id: id,
    name: id,
    kind: kind,
    url: 'https://example.invalid',
    username: id,
  );
  Track track(
    String source,
    String id,
    String path, {
    String artist = '同一个歌手',
    String album = 'Album',
  }) => Track(
    ref: TrackRef(source, id),
    title: id,
    artist: artist,
    album: album,
    remote: {'Path': path},
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sylphy-sqlite-compat-');
    db = AppDb(root);
    await db.open();
    catalog = LibraryCatalog(db);
    await db.putSource(source('a', SourceKind.emby));
    await db.putSource(source('b', SourceKind.subsonic));
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  test('artist portrait source preference and unicode track identity work without JSON1', () async {
    await db.replaceSourceTracks('a', [
      track('a', 'id/中文-"', 'D:/Audio/Disc/one.mp3'),
    ]);
    await db.replaceSourceTracks('b', [
      track('b', 'id:two', 'D:/Audio/Disc/two.mp3'),
    ]);
    final artist = await catalog.page(const CatalogQuery(view: 2));
    expect(artist.total, 1);
    expect(artist.rows.single.count, 2);
    // The selected representative must resolve to an existing Track.
    expect(artist.rows.single.portraitTrack.ref.sourceId, isNotEmpty);
    expect(artist.rows.single.portraitTrack.ref.id, isNotEmpty);
    expect(artist.rows.single.portraitTrack.artist, '同一个歌手');
  });

  test('folder browse preserves public keys, source isolation, and nested navigation', () async {
    await db.replaceSourceTracks('a', [
      track('a', 'base', 'D:\\Music\\Artist\\base.flac'),
      track('a', 'one', 'D:\\Music\\Artist\\Album\\one.flac'),
      track('a', 'two', 'D:\\Music\\Artist\\Album\\two.flac'),
      track('a', 'other', 'D:\\Music\\Artist\\Other\\three.flac'),
    ]);
    await db.replaceSourceTracks('b', [
      track('b', 'four', 'D:/Music/Artist/Album/four.flac'),
    ]);
    final rootPage = await catalog.page(const CatalogQuery(view: 3));
    expect(rootPage.total, 2); // per-source roots, never merged
    final first = rootPage.rows.firstWhere((r) => r.track.ref.sourceId == 'a');
    expect(first.isFolder, true);
    expect(jsonDecode(first.key), ['a', first.folder]);
    final page = await catalog.page(CatalogQuery(view: 3).folderIn(first.key));
    expect(page.total, greaterThan(0));
    expect(page.rows.every((r) => r.track.ref.sourceId == 'a'), true);
    final folder = page.rows.firstWhere((r) => r.isFolder);
    final nested = await catalog.page(
      CatalogQuery(view: 3).folderIn(folder.key),
    );
    expect(nested.total, greaterThan(0));
    expect(
      (await catalog.queue(CatalogQuery(view: 3).folderIn(folder.key).songs))
          .length,
      greaterThan(0),
    );
  });

  test('index staging does not affect live folders before commit', () async {
    await db.replaceSourceTracks('a', [track('a', 'old', 'D:/Old/old.flac')]);
    const run = 'new-scan';
    await db.stageIndexPage(run, 'a', [track('a', 'new', 'D:/New/new.flac')]);
    var current = await catalog.page(const CatalogQuery(view: 3));
    expect(current.rows.single.folder, 'D:/Old');
    await db.commitIndex(run, source('a', SourceKind.emby));
    current = await catalog.page(const CatalogQuery(view: 3));
    expect(current.rows.single.folder, 'D:/New');
    await db.discardIndex(run);
  });

  test(
    'old records require a new source sync; no implicit metadata migration',
    () async {
      await db.db.insert(
        'tracks',
        track('a', 'legacy', 'D:/Old/song.flac').toRow(),
      );
      final rootPage = await catalog.page(const CatalogQuery(view: 3));
      expect(rootPage.rows.single.folder, isNull);
      await db.replaceSourceTracks('a', [
        track('a', 'legacy', 'D:/Old/song.flac'),
      ]);
      final refreshed = await catalog.page(const CatalogQuery(view: 3));
      expect(refreshed.rows.single.folder, 'D:/Old');
    },
  );

  test('WebDAV folder paths come from IDs, not remote_json', () async {
    await db.putSource(source('dav', SourceKind.webdav));
    await db.replaceSourceTracks('dav', [
      Track(
        ref: const TrackRef('dav', 'Music/中文/one.flac'),
        title: 'one',
        artist: 'Artist',
        album: 'Album',
      ),
    ]);
    final rows = await catalog.page(
      const CatalogQuery(view: 3, sourceId: 'dav'),
    );
    expect(rows.rows.single.folder, './Music/中文');
  });
}
