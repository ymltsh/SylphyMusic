import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/data/app_db.dart';
import 'package:sylphy_music/services/media_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppDb db;
  late MediaAssetStore store;
  late DateTime now;
  var free = 1000.0;
  const source = SourceProfile(
    id: 'one',
    name: 'fixture',
    kind: SourceKind.emby,
    url: 'https://example.invalid',
    username: 'test',
  );
  MediaAssetStore make({int lyricsBudget = 20 * 1024 * 1024}) =>
      MediaAssetStore(
        db,
        root,
        clock: () => now,
        freeSpace: () async => free,
        lyricsBudget: lyricsBudget,
      );
  Future<MediaAsset?> save(
    String key,
    String text, {
    bool pinned = false,
    String version = 'v1',
  }) => store.put(
    source.id,
    key,
    'lyrics',
    version,
    utf8.encode(text),
    pinned: pinned,
  );
  Future<void> restart() async {
    await store.shutdown();
    await db.close();
    db = AppDb(root);
    await db.open();
    store = make();
    await store.initialize();
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sylphy-assets-');
    db = AppDb(root);
    await db.open();
    await db.putSource(source);
    now = DateTime.utc(2026, 10, 27);
    free = 1000;
    store = make();
    await store.initialize();
  });
  tearDown(() async {
    await store.shutdown();
    await db.close();
    await root.delete(recursive: true);
  });
  test('v5 migration adds the manifest without dropping source data', () async {
    await store.shutdown();
    await db.db.execute('DROP TABLE media_assets');
    await db.db.execute('DROP TABLE media_asset_migrations');
    await db.db.execute('PRAGMA user_version=5');
    await db.close();
    db = AppDb(root);
    await db.open();
    store = make();
    await store.initialize();
    expect((await db.source('one'))?.username, 'test');
    expect(
      (await db.db.rawQuery('PRAGMA user_version')).single.values.single,
      6,
    );
    expect(await db.db.query('media_assets'), isEmpty);
  });
  test(
    'real database reopen serves complete persisted bytes without a loader',
    () async {
      final original = await save('remote', 'cached lyrics');
      await restart();
      var calls = 0;
      final cached = await store.get(source, 'remote', 'lyrics', 'v1', (
        _,
      ) async {
        calls++;
        throw StateError('offline');
      });
      expect(calls, 0);
      expect(cached!.file.path, original!.file.path);
      expect(await cached.file.readAsString(), 'cached lyrics');
    },
  );
  test(
    'expired data returns immediately, refresh coalesces and publishes once',
    () async {
      await save('remote', 'old lyrics');
      now = now.add(const Duration(days: 2));
      final gate = Completer<AssetPayload?>();
      var calls = 0, updates = 0;
      store.addListener(() => updates++);
      Future<AssetPayload?> load(MediaAsset? _) {
        calls++;
        return gate.future;
      }

      final values = await Future.wait(
        List.generate(
          12,
          (_) => store.get(source, 'remote', 'lyrics', 'v1', load),
        ),
      );
      expect(await values.first!.file.readAsString(), 'old lyrics');
      gate.complete(AssetPayload(utf8.encode('new lyrics')));
      await store.waitForIdle();
      expect(calls, 1);
      expect(updates, 1);
      expect(
        await (await store.read('one', 'remote'))!.file.readAsString(),
        'new lyrics',
      );
    },
  );
  test(
    'offline refresh preserves stale data and uses bounded retry backoff',
    () async {
      await save('remote', 'offline lyrics');
      now = now.add(const Duration(days: 2));
      var calls = 0;
      Future<AssetPayload?> load(MediaAsset? _) async {
        calls++;
        throw StateError('offline');
      }

      expect(
        await (await store.get(
          source,
          'remote',
          'lyrics',
          'v1',
          load,
        ))!.file.readAsString(),
        'offline lyrics',
      );
      await store.waitForIdle();
      await store.get(source, 'remote', 'lyrics', 'v1', load);
      await store.waitForIdle();
      expect(calls, 1);
      await store.get(
        source,
        'remote',
        'lyrics',
        'v1',
        load,
        forceRefresh: true,
      );
      expect(calls, 2);
    },
  );
  test('newer requested version wins over an older delayed request', () async {
    final gate = Completer<AssetPayload?>();
    final old = store.get(source, 'remote', 'lyrics', 'v1', (_) => gate.future);
    await Future<void>.delayed(const Duration(milliseconds: 25));
    final fresh = await store.get(
      source,
      'remote',
      'lyrics',
      'v2',
      (_) async => AssetPayload(utf8.encode('new')),
    );
    gate.complete(AssetPayload(utf8.encode('old')));
    await old;
    expect(fresh!.version, 'v2');
    expect((await store.read('one', 'remote'))!.version, 'v2');
  });
  test('disk shortage and invalid replacement never overwrite the last complete asset', () async {
    await save('remote', 'complete');
    free = 1;
    await expectLater(save('remote', 'replacement'), throwsStateError);
    free = 1000;
    await expectLater(
      store.put('one', 'remote', 'lyrics', 'v2', [0xff]),
      throwsFormatException,
    );
    expect(
      await (await store.read('one', 'remote'))!.file.readAsString(),
      'complete',
    );
  });
  test(
    'same bytes share immutable files only within the same source',
    () async {
      final a = await save('a', 'same lyrics'),
          b = await save('b', 'same lyrics');
      expect(a!.file.path, b!.file.path);
      const other = SourceProfile(
        id: 'two',
        name: 'fixture',
        kind: SourceKind.emby,
        url: 'https://example.invalid',
        username: 'other',
      );
      await db.putSource(other);
      final c = await store.put(
        'two',
        'a',
        'lyrics',
        'v1',
        utf8.encode('same lyrics'),
      );
      expect(c!.file.path, isNot(a.file.path));
    },
  );
  test(
    'corrupt same-length files are rejected after restart and repaired',
    () async {
      final old = await save('remote', 'abcdef');
      await old!.file.writeAsString('broken');
      await restart();
      expect(await store.read('one', 'remote'), isNull);
      final repaired = await store.get(
        source,
        'remote',
        'lyrics',
        'v1',
        (_) async => AssetPayload(utf8.encode('repaired')),
      );
      expect(await repaired!.file.readAsString(), 'repaired');
    },
  );
  test(
    'startup reconciles missing rows, crash remnants and orphan files',
    () async {
      final old = await save('missing', 'missing');
      await old!.file.delete();
      final partial = await File('${store.directory.path}/tmp/crash.part')
          .writeAsString('half');
      final orphan = await File('${store.directory.path}/objects/orphan.lyrics')
          .writeAsString('uncommitted');
      await restart();
      expect(await store.read('one', 'missing'), isNull);
      expect(await partial.exists(), false);
      expect(await orphan.exists(), false);
    },
  );
  test(
    'suspending a source rejects delayed commits while keeping complete data',
    () async {
      await save('existing', 'complete');
      final gate = Completer<AssetPayload?>();
      final work = store.get(source, 'new', 'lyrics', 'v1', (_) => gate.future);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      store.suspendSource('one');
      gate.complete(AssetPayload(utf8.encode('late')));
      await work;
      expect(await store.read('one', 'new'), isNull);
      expect(await store.read('one', 'existing'), isNotNull);
    },
  );
  test('LRU protects manual lyrics and active readers; ordinary clear preserves manual imports', () async {
    await store.shutdown();
    store = make(lyricsBudget: 7);
    await store.initialize();
    await save('manual', 'manual content', pinned: true);
    await save('old', '123456');
    store.retain('one', 'old');
    now = now.add(const Duration(seconds: 1));
    await save('new', 'abcdef');
    expect(await store.read('one', 'old'), isNotNull);
    store.release('one', 'old');
    await store.waitForIdle();
    expect(await store.read('one', 'old'), isNull);
    expect(await store.read('one', 'manual'), isNotNull);
    await store.clear();
    expect(await store.read('one', 'new'), isNull);
    expect(await store.read('one', 'manual'), isNotNull);
    await store.clear(sourceId: 'one', includePinned: true);
    expect(await store.read('one', 'manual'), isNull);
  });
  test('undecodable image responses never enter the manifest', () async {
    await expectLater(
      store.put('one', 'bad', 'cover', 'v1', utf8.encode('<html>error</html>')),
      throwsA(anything),
    );
    expect(await store.read('one', 'bad'), isNull);
    final png = await File('test/fixtures/cover.png').readAsBytes();
    expect(await store.put('one', 'good', 'cover', 'v1', png), isNotNull);
  });
  test('damaged manual imports are retained for recovery instead of automatic deletion', () async {
    final manual = await save('manual', 'original manual', pinned: true);
    await manual!.file.writeAsString('damaged');
    await restart();
    expect(await store.read('one', 'manual'), isNull);
    expect(await manual.file.exists(), true);
    await store.clear();
    expect(await manual.file.exists(), true);
  });
}
