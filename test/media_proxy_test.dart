import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/data/app_db.dart';
import 'package:sylphy_music/services/byte_range.dart';
import 'package:sylphy_music/services/cache.dart';
import 'package:sylphy_music/services/cache_jobs.dart';
import 'package:sylphy_music/services/media_assets.dart';
import 'package:sylphy_music/services/media_proxy.dart';
import 'package:sylphy_music/services/sources.dart';

class NetworkTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class TestFactory extends AdapterFactory {
  TestFactory() : super(const AuthVault());
  @override
  MusicAdapter create(SourceProfile profile) => TestAdapter(profile);
}

class TestAdapter extends MusicAdapter {
  TestAdapter(super.profile);
  @override
  Future<Uri> mediaUrl(Track track) async => Uri.parse(profile.url);
  @override
  Future<Map<String, String>> mediaHeaders() async => {};
  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  NetworkTestBinding();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('disk_space_2'),
        (_) async => 100000.0,
      );
  late Directory root;
  late AppDb db;
  late CacheManager cache;
  late MediaProxy proxy;
  late HttpServer origin;
  late SourceProfile profile;
  late Uri ticket;
  late HttpClient client;
  final bytes = Uint8List.fromList(List.generate(8192, (i) => i % 251));
  final ranges = <String?>[];
  var version = '"v1"';
  var stallPreviewRemainder = false;
  Completer<void>? gate, requested;
  Completer<void>? stalledBodyGate;
  const track = Track(
    ref: TrackRef('a', 'one'),
    title: 'Track',
    artist: 'A',
    album: 'B',
  );

  setUp(() async {
    ranges.clear();
    version = '"v1"';
    stallPreviewRemainder = false;
    gate = null;
    requested = null;
    stalledBodyGate = null;
    root = await Directory.systemTemp.createTemp('sylphy-proxy-');
    db = AppDb(root);
    await db.open();
    origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin.listen((request) async {
      if (requested?.isCompleted == false) requested!.complete();
      await gate?.future;
      ranges.add(request.headers.value('range'));
      final range = ByteRange.parse(
        request.headers.value('range'),
        bytes.length,
      )!;
      request.response.headers.set('etag', version);
      request.response.headers.contentType = ContentType('audio', 'flac');
      request.response.contentLength = range.length;
      if (request.headers.value('range') != null) {
        request.response.statusCode = 206;
        request.response.headers.set(
          'content-range',
          'bytes ${range.start}-${range.end}/${bytes.length}',
        );
      }
      if (stallPreviewRemainder && range.start == 1024) {
        try {
          request.response.add([bytes[range.start]]);
          await request.response.flush();
          await stalledBodyGate!.future;
          await request.response.close();
        } catch (_) {
          // The proxy deliberately closes the obsolete upstream connection.
        }
        return;
      }
      if (request.method != 'HEAD') {
        request.response.add(bytes.sublist(range.start, range.end + 1));
      }
      await request.response.close();
    });
    profile = SourceProfile(
      id: 'a',
      name: 'A',
      kind: SourceKind.emby,
      url: 'http://127.0.0.1:${origin.port}/audio',
      username: 'test',
    );
    await db.putSource(profile);
    await db.replaceSourceTracks(profile.id, [track]);
    final factory = TestFactory();
    cache = CacheManager(db, factory, Directory('${root.path}/audio'));
    await cache.initialize();
    proxy = MediaProxy(db, cache, factory);
    await proxy.start();
    ticket = proxy.ticket(track, profile);
    client = HttpClient();
  });

  tearDown(() async {
    if (gate?.isCompleted == false) gate!.complete();
    if (stalledBodyGate?.isCompleted == false) stalledBodyGate!.complete();
    client.close(force: true);
    await proxy.dispose();
    await cache.shutdown();
    await origin.close(force: true);
    await db.close();
    await root.delete(recursive: true);
  });

  Future<({int status, List<int> body, String? range})> get({
    String? range,
    String method = 'GET',
    Uri? url,
  }) async {
    final request = await client.openUrl(method, url ?? ticket);
    if (range != null) request.headers.set('range', range);
    final response = await request.close();
    return (
      status: response.statusCode,
      body: await response.fold<List<int>>([], (a, b) => a..addAll(b)),
      range: response.headers.value('content-range'),
    );
  }

  test(
    'complete relay commits READY; offline ranges include suffix and HEAD',
    () async {
      expect((await get()).body, bytes);
      for (var i = 0; i < 100 && !await cache.contains(track.ref); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await cache.contains(track.ref), isTrue);
      final part = await get(range: 'bytes=100-199');
      expect(part.status, 206);
      expect(part.body, bytes.sublist(100, 200));
      expect(
        (await get(range: 'bytes=-10')).body,
        bytes.sublist(bytes.length - 10),
      );
      expect((await get(range: 'bytes=200-100')).status, 416);
      expect((await get(range: 'bytes=0-9', method: 'HEAD')).body, isEmpty);
      expect(ranges, [null]);
    },
  );

  test(
    'P2 prefix is reused for playback and complete cache has exact bytes',
    () async {
      await cache.prefetchNext(track, profile, bytesLimit: 1024);
      expect(cache.preview(track.ref)?.bytes.length, 1024);
      expect((await get()).body, bytes);
      expect(ranges, ['bytes=0-1023', 'bytes=1024-8191']);
      for (var i = 0; i < 100 && !await cache.contains(track.ref); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await (await cache.find(track.ref))!.file.readAsBytes(), bytes);
    },
  );

  test(
    'changed validator discards P2 and refetches original requested range',
    () async {
      await cache.prefetchNext(track, profile, bytesLimit: 1024);
      version = '"v2"';
      expect(
        (await get(range: 'bytes=512-2047')).body,
        bytes.sublist(512, 2048),
      );
      expect(ranges, ['bytes=0-1023', 'bytes=1024-2047', 'bytes=512-2047']);
      expect(await cache.contains(track.ref), isFalse);
    },
  );

  test(
    'changed preview validator retries without draining a stalled body',
    () async {
      await cache.prefetchNext(track, profile, bytesLimit: 1024);
      version = '"v2"';
      stallPreviewRemainder = true;
      stalledBodyGate = Completer<void>();
      final result = await get(range: 'bytes=512-2047')
          .timeout(const Duration(seconds: 5));
      expect(result.status, 206);
      expect(result.body, bytes.sublist(512, 2048));
      expect(ranges, ['bytes=0-1023', 'bytes=1024-2047', 'bytes=512-2047']);
      expect(cache.preview(track.ref), isNull);
      expect(await cache.contains(track.ref), isFalse);
    },
  );

  test('tickets are rejected after source is disabled or deleted', () async {
    await db.putSource(
      SourceProfile(
        id: profile.id,
        name: profile.name,
        kind: profile.kind,
        url: profile.url,
        username: profile.username,
        enabled: false,
      ),
    );
    expect((await get()).status, 403);
    await db.removeSourceData(profile.id);
    expect((await get()).status, 403);
    expect(ranges, isEmpty);
    expect(
      (await get(url: ticket.replace(path: '/audio/unknown'))).status,
      403,
    );
  });

  test(
    'same-length corruption and resource metadata changes invalidate READY',
    () async {
      await cache.fetchWhole(track, profile);
      final original = (await cache.find(track.ref))!;
      final damaged = [...bytes]..[0] = 255;
      await original.file.writeAsBytes(damaged, flush: true);
      await original.file.setLastModified(
        DateTime.now().add(const Duration(seconds: 2)),
      );
      expect(await cache.find(track.ref), isNull);
      await cache.fetchWhole(track, profile);
      await db.replaceSourceTracks(profile.id, [
        Track(
          ref: track.ref,
          title: track.title,
          artist: track.artist,
          album: track.album,
          remote: {'size': bytes.length + 1},
        ),
      ]);
      expect(await cache.find(track.ref), isNull);
    },
  );

  test(
    'manual clear defers deletion until active file reader releases',
    () async {
      await cache.fetchWhole(track, profile);
      final file = (await cache.find(track.ref))!.file;
      cache.lease(track.ref);
      await cache.clear(keys: {track.ref.key});
      expect(await file.exists(), true);
      cache.release(track.ref);
      await cache.shutdown();
      expect(await file.exists(), false);
      expect(await db.db.query('cache'), isEmpty);
    },
  );

  test(
    'restart discards partial and orphan files while retaining READY',
    () async {
      await cache.fetchWhole(track, profile);
      await File('${cache.root.path}/tmp/interrupted.partial')
          .writeAsBytes([1, 2, 3]);
      await File('${cache.root.path}/ready/orphan').writeAsBytes([1, 2, 3]);
      await cache.initialize();
      expect(await cache.contains(track.ref), true);
      expect(
        await Directory('${cache.root.path}/tmp').list().toList(),
        isEmpty,
      );
      expect(await File('${cache.root.path}/ready/orphan').exists(), false);
    },
  );

  test('200-track frozen job resumes after interruption and commits exact files', () async {
    final tracks = List.generate(
      200,
      (i) => Track(
        ref: TrackRef(profile.id, 'stress-$i'),
        title: 'Track $i',
        artist: 'Fixture',
        album: 'Stress',
      ),
    );
    await db.replaceSourceTracks(profile.id, tracks);
    var jobs = CacheJobs(db, cache)..paused = true;
    final refs = tracks.map((item) => item.ref).toList();
    final jobId = await jobs.schedule('Frozen 200', [...refs, refs.first]);
    refs.clear();
    expect((await db.db.query('cache_job_items')).length, 200);
    gate = Completer<void>();
    requested = Completer<void>();
    try {
      await jobs.resume();
      await requested!.future.timeout(const Duration(seconds: 5));
      await jobs.shutdown().timeout(const Duration(seconds: 5));
      expect(await db.db.query('cache'), isEmpty);
      // Recreate the scheduler over its persisted snapshot, as on app restart.
      jobs = CacheJobs(db, cache);
      gate!.complete();
      await jobs.run().timeout(const Duration(seconds: 40));
      expect(
        (await db.db.query(
          'cache_jobs',
          where: 'id=?',
          whereArgs: [jobId],
        )).single['state'],
        'completed',
      );
      expect((await db.db.query('cache')).length, 200);
      expect(
        (await db.db.query('cache_job_items'))
            .every((row) => row['state'] == 'done'),
        true,
      );
      for (final track in [tracks.first, tracks[99], tracks.last]) {
        expect(await (await cache.find(track.ref))!.file.readAsBytes(), bytes);
      }
      expect(
        await Directory('${cache.root.path}/tmp').list().toList(),
        isEmpty,
      );
    } finally {
      if (!gate!.isCompleted) gate!.complete();
      await jobs.shutdown();
    }
  });

  test('source disable aborts active user transfer and retains existing READY and task snapshot', () async {
    await cache.fetchWhole(track, profile);
    final readyFile = (await cache.find(track.ref))!.file;
    const pendingTrack = Track(
      ref: TrackRef('a', 'pending'),
      title: 'Pending',
      artist: '',
      album: '',
    );
    await db.replaceSourceTracks(profile.id, [track, pendingTrack]);
    final jobs = CacheJobs(db, cache);
    gate = Completer<void>();
    requested = Completer<void>();
    try {
      final id = await jobs.schedule('Preserved snapshot', [
        track.ref,
        pendingTrack.ref,
      ]);
      await requested!.future.timeout(const Duration(seconds: 5));
      await db.db.update(
        'sources',
        {'enabled': 0},
        where: 'id=?',
        whereArgs: [profile.id],
      );
      proxy.revokeSource(profile.id);
      await jobs.sourceUnavailable(profile.id);
      await cache.cancelSource(profile.id).timeout(const Duration(seconds: 5));
      await jobs.shutdown();
      final rows = await db.db.query(
        'cache_job_items',
        where: 'job_id=?',
        whereArgs: [id],
        orderBy: 'position',
      );
      expect(rows.map((r) => r['state']), ['done', 'failed']);
      expect(
        (await db.db.query(
          'cache_jobs',
          where: 'id=?',
          whereArgs: [id],
        )).single['state'],
        'failed',
      );
      expect(await readyFile.exists(), true);
      expect(await cache.contains(track.ref), true);
      expect(await cache.contains(pendingTrack.ref), false);
      expect((await db.tracks()).length, 2);
    } finally {
      if (!gate!.isCompleted) gate!.complete();
      await jobs.shutdown();
    }
  });

  test('revoking source interrupts in-flight origin response and rejects old ticket', () async {
    gate = Completer<void>();
    requested = Completer<void>();
    final response = get();
    await requested!.future.timeout(const Duration(seconds: 5));
    await db.db.update(
      'sources',
      {'enabled': 0},
      where: 'id=?',
      whereArgs: [profile.id],
    );
    proxy.revokeSource(profile.id);
    expect((await response.timeout(const Duration(seconds: 5))).status, 502);
    expect((await get()).status, 403);
  });

  test(
    'source disable closes an in-flight P2 request without publishing prefix',
    () async {
      gate = Completer<void>();
      requested = Completer<void>();
      final prefix = cache.prefetchNext(track, profile, bytesLimit: 1024);
      await requested!.future.timeout(const Duration(seconds: 5));
      await db.db.update(
        'sources',
        {'enabled': 0},
        where: 'id=?',
        whereArgs: [profile.id],
      );
      await cache.cancelSource(profile.id);
      await prefix.timeout(const Duration(seconds: 5));
      expect(cache.preview(track.ref), isNull);
      expect(await db.db.query('cache'), isEmpty);
    },
  );

  test(
    'changing P2 plan to an already cached track closes the previous request',
    () async {
      const ready = Track(
        ref: TrackRef('a', 'ready'),
        title: 'Ready',
        artist: '',
        album: '',
      );
      await db.replaceSourceTracks(profile.id, [track, ready]);
      await cache.fetchWhole(ready, profile);
      gate = Completer<void>();
      requested = Completer<void>();
      final previous = cache.prefetchNext(track, profile, bytesLimit: 1024);
      await requested!.future.timeout(const Duration(seconds: 5));
      await cache.prefetchNext(ready, profile);
      await previous.timeout(const Duration(seconds: 5));
      expect(cache.preview(track.ref), isNull);
      expect(await cache.contains(ready.ref), true);
    },
  );

  test(
    'cancelling one job preserves a shared transfer required by another job',
    () async {
      final jobs = CacheJobs(db, cache);
      jobs.paused = true;
      final first = await jobs.schedule('First', [track.ref]);
      final second = await jobs.schedule('Second', [track.ref]);
      gate = Completer<void>();
      requested = Completer<void>();
      try {
        await jobs.resume();
        await requested!.future.timeout(const Duration(seconds: 5));
        await jobs.cancelJob(first);
        gate!.complete();
        String state = 'pending';
        for (var i = 0; i < 100 && state != 'completed'; i++) {
          state =
              (await db.db.query(
                    'cache_jobs',
                    where: 'id=?',
                    whereArgs: [second],
                  )).single['state']
                  as String;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(state, 'completed');
        expect(ranges.length, 1);
        expect(await cache.contains(track.ref), true);
        expect(
          (await db.db.query(
            'cache_jobs',
            where: 'id=?',
            whereArgs: [first],
          )).single['state'],
          'cancelled',
        );
      } finally {
        if (!gate!.isCompleted) gate!.complete();
        await jobs.shutdown();
      }
    },
  );
  test('audio and assets share one LRU and preserve leased audio on admission failure', () async {
    final assets = MediaAssetStore(
      db,
      root,
      quota: cache.quota,
      freeSpace: () async => 1000,
    );
    try {
      await assets.initialize();
      cache.maxBytes = bytes.length + 5;
      await cache.fetchWhole(track, profile);
      cache.lease(track.ref);
      await expectLater(
        assets.put('a', 'lyrics', 'lyrics', 'v1', [65, 66, 67, 68, 69, 70]),
        throwsStateError,
      );
      expect(await cache.contains(track.ref), true);
      cache.release(track.ref);
      await assets.put('a', 'lyrics', 'lyrics', 'v1', [65, 66, 67, 68, 69, 70]);
      expect(await cache.contains(track.ref), false);
      expect((await cache.quota.usage()).total, 6);
    } finally {
      await assets.shutdown();
    }
  });
  test(
    'optional media cannot evict the song a cache job just completed',
    () async {
      final assets = MediaAssetStore(
        db,
        root,
        quota: cache.quota,
        freeSpace: () async => 1000,
      );
      final jobs = CacheJobs(db, cache)..paused = true;
      var covers = 0, lyrics = 0;
      jobs.attachMediaLoaders(
        cover: (_) async {
          covers++;
          await assets.put('a', 'optional', 'lyrics', 'v1', [
            65,
            66,
            67,
            68,
            69,
            70,
          ]);
          return null;
        },
        lyrics: (_) async {
          lyrics++;
          throw StateError('optional unavailable');
        },
      );
      try {
        await assets.initialize();
        cache.maxBytes = bytes.length + 5;
        final id = await jobs.schedule('fixture', [track.ref]);
        jobs.paused = false;
        await jobs.run();
        expect(covers, 1);
        expect(lyrics, 1);
        expect(await cache.contains(track.ref), true);
        expect(
          (await db.db.query(
            'cache_jobs',
            where: 'id=?',
            whereArgs: [id],
          )).single['state'],
          'completed',
        );
      } finally {
        await jobs.shutdown();
        await assets.shutdown();
      }
    },
  );
  test(
    'cancel during cover loading skips lyrics and retains complete audio',
    () async {
      final jobs = CacheJobs(db, cache)..paused = true;
      final started = Completer<void>(), finish = Completer<void>();
      var lyrics = 0;
      jobs.attachMediaLoaders(
        cover: (_) async {
          started.complete();
          await finish.future;
          return null;
        },
        lyrics: (_) async {
          lyrics++;
          return null;
        },
      );
      final id = await jobs.schedule('fixture', [track.ref]);
      jobs.paused = false;
      final running = jobs.run();
      try {
        await started.future.timeout(const Duration(seconds: 5));
        await jobs.cancelJob(id);
        finish.complete();
        await running;
        expect(lyrics, 0);
        expect(await cache.contains(track.ref), true);
        expect(
          (await db.db.query(
            'cache_jobs',
            where: 'id=?',
            whereArgs: [id],
          )).single['state'],
          'cancelled',
        );
      } finally {
        if (!finish.isCompleted) finish.complete();
        await jobs.shutdown();
      }
    },
  );
  test(
    'concurrent audio and lyric commits cannot oversubscribe the shared budget',
    () async {
      final assets = MediaAssetStore(
        db,
        root,
        quota: cache.quota,
        freeSpace: () async => 1000,
      );
      try {
        await assets.initialize();
        cache.maxBytes = bytes.length + 2;
        await Future.wait([
          cache.fetchWhole(track, profile),
          assets
              .put('a', 'remote', 'lyrics', 'v1', [65, 66, 67, 68, 69, 70])
              .then<void>(
                (_) {},
                onError: (Object e) {
                  expect(e, isStateError);
                },
              ),
        ]);
        final usage = await cache.quota.usage();
        expect(usage.total, lessThanOrEqualTo(cache.maxBytes));
        final audio = await cache.find(track.ref);
        final lyric = await assets.read('a', 'remote');
        expect(audio != null || lyric != null, true);
        if (audio != null) {
          expect(await audio.file.readAsBytes(), bytes);
        }
        if (lyric != null) {
          expect(await lyric.file.readAsBytes(), [65, 66, 67, 68, 69, 70]);
        }
      } finally {
        await assets.shutdown();
      }
    },
  );
}
