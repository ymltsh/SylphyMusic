import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/data/app_db.dart';
import 'package:sylphy_music/data/library_catalog.dart';
import 'package:sylphy_music/services/library_sync.dart';
import 'package:sylphy_music/services/sources.dart';

class PageAdapter extends MusicAdapter {
  PageAdapter(super.profile, this.pages, {this.onClose});
  final Stream<List<Track>> Function() pages;
  final void Function()? onClose;
  @override
  Stream<List<Track>> libraryPages() => pages();
  @override
  Future<List<Track>> fetchLibrary() =>
      throw StateError('Unbounded API must not be used');
  @override
  void close() => onClose?.call();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PageFactory extends AdapterFactory {
  PageFactory(this.adapter) : super(const AuthVault());
  final PageAdapter adapter;
  @override
  MusicAdapter create(SourceProfile source) => adapter;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppDb db;
  LibrarySync? sync;
  const source = SourceProfile(
    id: 's',
    name: 'Fixture',
    kind: SourceKind.emby,
    url: 'https://example.invalid',
    username: 'fixture',
  );
  Track track(String id) =>
      Track(ref: TrackRef('s', id), title: id, artist: 'A', album: 'B');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sylphy-index-');
    db = AppDb(root);
    await db.open();
    await db.putSource(source);
    await db.replaceSourceTracks(source.id, [track('old')]);
  });
  tearDown(() async {
    await sync?.shutdown();
    sync = null;
    await db.close();
    await root.delete(recursive: true);
  });

  test(
    '50000 tracks are staged pagewise and old snapshot changes only on commit',
    () async {
      var largestPage = 0;
      Stream<List<Track>> pages() async* {
        for (var page = 0; page < 200; page++) {
          final records = List.generate(250, (i) => track('${page * 250 + i}'));
          largestPage = records.length > largestPage
              ? records.length
              : largestPage;
          expect(
            (await db.db.rawQuery(
              'SELECT COUNT(*) AS n FROM tracks WHERE missing=0',
            )).single['n'],
            1,
          );
          yield records;
        }
      }

      sync = LibrarySync(db, PageFactory(PageAdapter(source, pages)));
      final first = sync!.sync(source);
      expect(identical(first, sync!.sync(source)), true);
      await first;
      expect(largestPage, 250);
      expect(sync!.progress[source.id]!.count, 50000);
      expect(
        (await db.db.rawQuery(
          'SELECT COUNT(*) AS n FROM tracks WHERE missing=0',
        )).single['n'],
        50000,
      );
      expect((await db.track(track('old').ref))!.missing, true);
      expect(await db.db.query('index_tracks'), isEmpty);
      final lastPage = await LibraryCatalog(db)
          .page(const CatalogQuery(), offset: 49900);
      expect(lastPage.total, 50000);
      expect(lastPage.rows.length, 100);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('failed later page keeps old snapshot and discards staging', () async {
    Stream<List<Track>> pages() async* {
      yield [track('new')];
      throw StateError('private server detail');
    }

    sync = LibrarySync(db, PageFactory(PageAdapter(source, pages)));
    await expectLater(sync!.sync(source), throwsStateError);
    expect((await db.tracks()).map((t) => t.ref.id), ['old']);
    expect(await db.db.query('index_tracks'), isEmpty);
    expect(
      sync!.progress[source.id]!.message,
      isNot(contains('private server')),
    );
  });

  test(
    'cancel interrupts waiting adapter and shutdown waits for staging cleanup',
    () async {
      final staged = Completer<void>(), gate = Completer<void>();
      Stream<List<Track>> pages() async* {
        yield [track('new')];
        staged.complete();
        await gate.future;
        yield [track('later')];
      }

      final adapter = PageAdapter(
        source,
        pages,
        onClose: () {
          if (!gate.isCompleted) gate.complete();
        },
      );
      sync = LibrarySync(db, PageFactory(adapter));
      final run = sync!.sync(source);
      await staged.future;
      sync!.cancel(source.id);
      await run;
      expect(sync!.progress[source.id]!.state, 'cancelled');
      expect((await db.tracks()).map((t) => t.ref.id), ['old']);
      expect(await db.db.query('index_tracks'), isEmpty);
    },
  );

  test('changed source identity rejects complete staged snapshot', () async {
    Stream<List<Track>> pages() async* {
      yield [track('new')];
      await db.putSource(
        const SourceProfile(
          id: 's',
          name: 'Changed',
          kind: SourceKind.emby,
          url: 'https://other.invalid',
          username: 'fixture',
        ),
      );
    }

    sync = LibrarySync(db, PageFactory(PageAdapter(source, pages)));
    await expectLater(sync!.sync(source), throwsStateError);
    expect((await db.tracks()).map((t) => t.ref.id), ['old']);
    expect(await db.db.query('index_tracks'), isEmpty);
  });

  test('restart drops partial rows but remembers interrupted source for fresh scan', () async {
    await db.stageIndexPage('crashed', source.id, [track('partial')]);
    await db.db.insert('index_runs', {
      'source_id': source.id,
      'run_id': 'crashed',
    });
    await db.close();
    db = AppDb(root);
    await db.open();
    sync = LibrarySync(
      db,
      PageFactory(
        PageAdapter(source, () async* {
          yield [track('fresh')];
        }),
      ),
    );
    expect(await db.db.query('index_tracks'), isEmpty);
    expect(await sync!.interruptedSources(), {source.id});
    expect((await db.tracks()).single.ref.id, 'old');
    await sync!.sync(source);
    expect((await db.tracks()).single.ref.id, 'fresh');
    expect(await sync!.interruptedSources(), isEmpty);
  });
}
