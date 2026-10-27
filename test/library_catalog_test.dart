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
  SourceProfile source(String id, {bool enabled = true}) => SourceProfile(
    id: id,
    name: id,
    kind: SourceKind.emby,
    url: 'https://example.invalid',
    username: id,
    enabled: enabled,
  );
  Track track(String sourceId, String id, {String? title}) => Track(
    ref: TrackRef(sourceId, id),
    title: title ?? id,
    artist: 'Artist',
    album: 'Album',
    year: 2020,
    durationMs: 1000,
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sylphy-catalog-');
    db = AppDb(root);
    await db.open();
    catalog = LibraryCatalog(db);
    await db.putSource(source('a'));
    await db.putSource(source('b'));
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  test(
    'paging and queue identities preserve the same deterministic order',
    () async {
      await db.replaceSourceTracks(
        'a',
        List.generate(
          205,
          (i) => track('a', 'id${i.toString().padLeft(3, '0')}'),
        ),
      );
      final first = await catalog.page(const CatalogQuery());
      final second = await catalog.page(const CatalogQuery(), offset: 100);
      final last = await catalog.page(const CatalogQuery(), offset: 200);
      expect(first.total, 205);
      expect(first.rows.length, 100);
      expect(second.rows.first.track.ref.id, 'id100');
      expect(last.rows.length, 5);
      expect(
        (await catalog.queue(const CatalogQuery())).map((r) => r.id),
        [
          ...first.rows,
          ...second.rows,
          ...last.rows,
        ].map((row) => row.track.ref.id),
      );
      final reverse = await catalog.page(const CatalogQuery(descending: true));
      expect(reverse.rows.first.track.ref.id, 'id204');
    },
  );

  test(
    'groups combine sources and drill down without replacing song identities',
    () async {
      await db.replaceSourceTracks('a', [track('a', 'one')]);
      await db.replaceSourceTracks('b', [track('b', 'one')]);
      for (final view in [1, 2]) {
        final query = CatalogQuery(view: view, sort: 'duration');
        final groups = await catalog.page(query);
        expect(groups.total, 1);
        expect(groups.rows.single.count, 2);
        expect(groups.rows.single.sources, 2);
        final songs = await catalog.page(
          query.songsIn(view == 1 ? 'album' : 'artist', groups.rows.single.key),
        );
        expect(songs.total, 2);
        expect(songs.rows.map((row) => row.track.ref.sourceId).toSet(), {
          'a',
          'b',
        });
      }
    },
  );

  test(
    'group play-all uses every matching song and preserves filters',
    () async {
      await db.replaceSourceTracks('a', [
        track('a', 'one', title: 'keep one'),
        track('a', 'two', title: 'keep two'),
        track('a', 'blocked', title: 'keep blocked'),
        track('a', 'other'),
      ]);
      await db.replaceSourceTracks('b', [
        track('b', 'outside', title: 'keep outside'),
      ]);
      await db.setBlocked(const TrackRef('a', 'blocked'), true);
      for (final view in [1, 2]) {
        for (final sort in ['name', 'duration', 'year']) {
          final query = CatalogQuery(
            view: view,
            sourceId: 'a',
            search: 'keep',
            sort: sort,
            descending: true,
          );
          final groups = await catalog.page(query);
          expect(groups.total, 1);
          final songs = query.songs;
          expect(songs.view, 0);
          expect(songs.sort, sort);
          expect(songs.descending, isTrue);
          final refs = await catalog.queue(songs);
          expect(refs.toSet(), {
            const TrackRef('a', 'one'),
            const TrackRef('a', 'two'),
          });
          final narrowed = query.songsIn(
            view == 1 ? 'album' : 'artist',
            groups.rows.single.key,
          );
          expect((await catalog.queue(narrowed.songs)).toSet(), refs.toSet());
        }
        expect(
          await catalog.queue(
            CatalogQuery(view: view, sourceId: 'missing').songs,
          ),
          isEmpty,
        );
      }
    },
  );

  test('source, literal search and blacklist filters apply before paging and grouping', () async {
    final special = track('a', 'quote"\\id', title: '100%_music');
    await db.replaceSourceTracks('a', [special, track('a', 'other')]);
    await db.replaceSourceTracks('b', [track('b', 'hidden')]);
    await db.putSource(source('b', enabled: false));
    expect((await catalog.page(const CatalogQuery(search: '%_'))).total, 1);
    await db.setBlocked(special.ref, true);
    expect((await catalog.page(const CatalogQuery(search: '%_'))).total, 0);
    expect(
      (await catalog.page(const CatalogQuery(blocked: true)))
          .rows
          .single
          .track
          .ref,
      special.ref,
    );
    expect((await catalog.page(const CatalogQuery(sourceId: 'b'))).total, 0);
    await db.setBlocked(const TrackRef('b', 'hidden'), true);
    expect((await catalog.page(const CatalogQuery(blocked: true))).total, 2);
    expect(
      (await catalog.page(const CatalogQuery(view: 1))).rows.single.count,
      1,
    );
  });
}
