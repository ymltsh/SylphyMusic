import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/data/app_db.dart';
import 'package:sylphy_music/services/artwork.dart';
import 'package:sylphy_music/services/playback.dart';
import 'package:sylphy_music/services/sources.dart';

import 'live_emby_test.dart' show MemoryVault;
import 'media_proxy_test.dart' show NetworkTestBinding;

void main() {
  NetworkTestBinding();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('disk_space_2'),
        (_) async => 100000.0,
      );
  late Directory root;
  late AppDb db;
  late HttpServer server;
  late ArtworkStore store;
  late EmbyAdapter adapter;
  final requests = <Uri>[];
  final statuses = <String, int>{};
  var delay = false, active = 0, peak = 0, notModified = 0;
  var conditional = false;
  Track track({
    String id = 'song',
    String tag = 'song-v1',
    String albumTag = '',
    String cover = 'album',
  }) => Track(
    ref: TrackRef('s', id),
    title: '',
    artist: '',
    album: '',
    coverId: cover,
    remote: {
      'AlbumId': 'album',
      if (tag.isNotEmpty) 'ImageTags': {'Primary': tag},
      if (albumTag.isNotEmpty) 'AlbumPrimaryImageTag': albumTag,
    },
  );
  setUp(() async {
    statuses.clear();
    requests.clear();
    delay = false;
    active = 0;
    peak = 0;
    conditional = false;
    notModified = 0;
    root = await Directory.systemTemp.createTemp('sylphy-cover-');
    db = AppDb(root);
    await db.open();
    final png = await File('test/fixtures/cover.png').readAsBytes();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      requests.add(r.uri);
      active++;
      if (active > peak) peak = active;
      expect(r.headers.value('X-Emby-Token'), 'fixture-token');
      if (delay) await Future<void>.delayed(const Duration(milliseconds: 70));
      final id = r.uri.pathSegments[2];
      r.response.headers.set('ETag', '"fixture-cover-v1"');
      if (conditional &&
          r.headers.value('If-None-Match') == '"fixture-cover-v1"') {
        notModified++;
        r.response.statusCode = 304;
        await r.response.close();
        active--;
        return;
      }
      r.response.statusCode = statuses[id] ?? 200;
      r.response.headers.contentType = ContentType('image', 'png');
      r.response.add(png);
      await r.response.close();
      active--;
    });
    final source = SourceProfile(
      id: 's',
      name: 'fixture',
      kind: SourceKind.emby,
      url: 'http://127.0.0.1:${server.port}/emby',
      username: 'fixture',
    );
    await db.putSource(source);
    final vault = MemoryVault();
    await vault.write('s', 'token', 'fixture-token');
    final factory = AdapterFactory(vault);
    adapter = EmbyAdapter(source, vault);
    store = ArtworkStore(db, factory, root);
  });
  tearDown(() async {
    await store.shutdown();
    adapter.close();
    await server.close(force: true);
    await db.close();
    await root.delete(recursive: true);
  });
  test(
    'notification metadata includes a readable cached artwork URI',
    () async {
      final song = track();
      final file = await store.load(song);
      expect(file, isNotNull);
      final item = mediaItemForTrack(song, artUri: file!.uri);
      expect(item.artUri, file.uri);
      expect(item.artUri!.scheme, 'file');
      expect(await File.fromUri(item.artUri!).exists(), isTrue);
    },
  );

  test(
    'song Primary tag overrides stale album cover_id and preserves prefix',
    () async {
      final url = (await adapter.coverUrl(track()))!;
      expect(url.path, '/emby/Items/song/Images/Primary');
      expect(url.queryParameters['tag'], 'song-v1');
      expect(await store.load(track()), isNotNull);
      expect(requests.single.queryParameters['tag'], 'song-v1');
    },
  );
  test('album artwork uses matching album ID and tag', () async {
    final url = (await adapter.coverUrl(track(tag: '', albumTag: 'album-v2')))!;
    expect(url.path, '/emby/Items/album/Images/Primary');
    expect(url.queryParameters['tag'], 'album-v2');
  });
  test(
    'root base URL and inherited Primary tag use the matching image item',
    () async {
      final direct = EmbyAdapter(
        SourceProfile(
          id: 'root',
          name: 'fixture',
          kind: SourceKind.emby,
          url: 'http://127.0.0.1:${server.port}',
          username: 'fixture',
        ),
        MemoryVault(),
      );
      try {
        expect(
          (await direct.coverUrl(track()))!.path,
          '/Items/song/Images/Primary',
        );
        const inherited = Track(
          ref: TrackRef('s', 'song'),
          title: '',
          artist: '',
          album: '',
          remote: {
            'ParentPrimaryImageItemId': 'parent',
            'ParentPrimaryImageTag': 'parent-v1',
          },
        );
        final url = (await direct.coverUrl(inherited))!;
        expect(url.path, '/Items/parent/Images/Primary');
        expect(url.queryParameters['tag'], 'parent-v1');
      } finally {
        direct.close();
      }
    },
  );
  test(
    'missing own picture falls back to album; authorization errors do not',
    () async {
      statuses['song'] = 404;
      expect(await store.load(track()), isNotNull);
      expect(requests.length, 2);
      expect(requests.last.path, '/emby/Items/album/Images/Primary');
      statuses['other'] = 401;
      requests.clear();
      expect(await store.load(track(id: 'other')), isNull);
      expect(requests.length, 1);
    },
  );
  test(
    'failed loads are retryable and successful files survive a new store',
    () async {
      statuses['song'] = 503;
      expect(await store.load(track()), isNull);
      statuses.clear();
      final file = await store.load(track(), forceRefresh: true);
      expect(file, isNotNull);
      expect(requests.length, 2);
      await store.shutdown();
      store = ArtworkStore(db, AdapterFactory(adapter.vault), root);
      expect((await store.load(track()))!.path, file!.path);
      expect(requests.length, 2);
    },
  );
  test(
    'tag change invalidates disk and in-flight keys; duplicate loads coalesce',
    () async {
      delay = true;
      final first = store.load(track());
      final duplicate = store.load(track());
      final files = await Future.wait([first, duplicate]);
      final updated = await store.load(
        track(tag: 'song-v2'),
        forceRefresh: true,
      );
      expect(requests.length, 2);
      expect(files[0]!.path, files[1]!.path);
      expect(updated, isNotNull);
      expect(store.revision(track()), greaterThan(1));
    },
  );
  test('bulk cover loading bounds concurrent network requests', () async {
    delay = true;
    final files = await Future.wait(
      List.generate(16, (i) => store.load(track(id: 'song$i'))),
    );
    expect(files.every((f) => f != null), true);
    expect(peak, lessThanOrEqualTo(6));
  });
  test('album art is shared and unrelated song metadata does not invalidate a tagged image', () async {
    final a = track(id: 'first', tag: '', albumTag: 'shared-v1');
    final b = track(id: 'second', tag: '', albumTag: 'shared-v1');
    final files = await Future.wait([store.load(a), store.load(b)]);
    expect(requests.length, 1);
    expect(files[0]!.path, files[1]!.path);
    final modified = Track(
      ref: a.ref,
      title: 'renamed',
      artist: '',
      album: '',
      coverId: a.coverId,
      remote: {...a.remote, 'DateModified': 'new timestamp', 'ImageTags': null},
    );
    expect(await store.load(modified), isNotNull);
    expect(requests.length, 1);
  });
  test(
    'persisted image validators support a 304 refresh without replacing bytes',
    () async {
      final first = await store.load(track());
      await store.shutdown();
      store = ArtworkStore(db, AdapterFactory(adapter.vault), root);
      conditional = true;
      final next = await store.load(track(), forceRefresh: true);
      expect(next!.path, first!.path);
      expect(notModified, 1);
      expect(requests.length, 2);
    },
  );
}
