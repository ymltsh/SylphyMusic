import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:sylphy_music/core/app_controller.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/ui/cover_art.dart';
import 'package:sylphy_music/ui/cache_storage.dart';
import 'package:sylphy_music/ui/lyrics_page.dart';

import 'live_emby_test.dart' show MemoryVault;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library =
      Platform.environment['SYLPHY_MPV_LIBRARY'] ??
      'build/windows/x64/runner/Debug/libmpv-2.dll';
  final available = File(library).existsSync();
  late Directory root;
  late SylphyApp app;
  const track = Track(
    ref: TrackRef('s', 'song'),
    title: 'fixture',
    artist: 'fixture',
    album: 'fixture',
    coverId: 'song',
    remote: {
      'ImageTags': {'Primary': 'v1'},
    },
  );
  setUp(() async {
    if (!available) return;
    MediaKit.ensureInitialized(libmpv: File(library).absolute.path);
    root = await Directory.systemTemp.createTemp('sylphy-asset-widget-');
    app = await SylphyApp.bootstrap(
      dataRoot: root,
      credentialVault: MemoryVault(),
      resumeBackground: false,
      platformIntegration: false,
    );
    await app.db.putSource(
      const SourceProfile(
        id: 's',
        name: 'fixture',
        kind: SourceKind.emby,
        url: 'https://example.invalid',
        username: 'test',
      ),
    );
    await app.db.replaceSourceTracks('s', [track]);
    app.playback.current = track;
  });
  tearDown(() async {
    if (!available) return;
    await app.disposeAsync();
    await root.delete(recursive: true);
  });
  Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 200; i++) {
        await tester.pump();
        if (ready()) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      throw StateError('Asset widget did not update');
    });
    await tester.pump();
  }

  String imagePath(WidgetTester tester) {
    final image = tester.widget<Image>(find.byType(Image)).image;
    return ((image is ResizeImage ? image.imageProvider : image) as FileImage)
        .file
        .path;
  }

  testWidgets(
    'visible cover switches to a refreshed immutable file without remounting',
    (tester) async {
      final png = (await tester.runAsync(
        () => File('test/fixtures/cover.png').readAsBytes(),
      ))!;
      final old = await tester.runAsync(
        () => app.assets.put(
          's',
          app.artwork.key(track),
          'cover',
          track.artworkVersion,
          png,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverArt(app: app, track: track),
          ),
        ),
      );
      await waitFor(tester, () => find.byType(Image).evaluate().isNotEmpty);
      expect(imagePath(tester), old!.file.path);
      final next = await tester.runAsync(
        () => app.assets.put(
          's',
          app.artwork.key(track),
          'cover',
          track.artworkVersion,
          [...png, 0],
        ),
      );
      await waitFor(
        tester,
        () =>
            find.byType(Image).evaluate().isNotEmpty &&
            imagePath(tester) == next!.file.path,
      );
      expect(next!.file.path, isNot(old.file.path));
      expect(await tester.runAsync(old.file.exists), true);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox());
        await app.assets.waitForIdle();
      });
      await tester.runAsync(() => app.assets.waitForIdle());
      expect(await tester.runAsync(old.file.exists), false);
      expect(tester.takeException(), isNull);
    },
    skip: !available,
  );
  testWidgets('open lyrics page reacts to cache refresh and manual import', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await app.assets.put(
        's',
        app.artwork.key(track),
        'cover',
        track.artworkVersion,
        await File('test/fixtures/cover.png').readAsBytes(),
      );
    });
    await tester.runAsync(
      () => app.assets.put(
        's',
        app.lyrics.key(track),
        'lyrics',
        track.resourceVersion,
        utf8.encode('[00:01.00]Old fixture line'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LyricsPage(
          app: app,
          track: track,
          theme: ThemeData(),
          lyrics: Future.value('[00:01.00]Old fixture line'),
        ),
      ),
    );
    await waitFor(
      tester,
      () => find.text('Old fixture line').evaluate().isNotEmpty,
    );
    await tester.runAsync(
      () => app.assets.put(
        's',
        app.lyrics.key(track),
        'lyrics',
        track.resourceVersion,
        utf8.encode('[00:01.00]Updated fixture line'),
      ),
    );
    await waitFor(
      tester,
      () => find.text('Updated fixture line').evaluate().isNotEmpty,
    );
    final file = await tester.runAsync(
      () =>
          File('${root.path}/manual.lrc')
              .writeAsString('[00:01.00]Manual fixture line'),
    );
    await tester.runAsync(() => app.importLyricsFile(track, file!));
    await waitFor(
      tester,
      () => find.text('Manual fixture line').evaluate().isNotEmpty,
    );
    expect(find.text('Old fixture line'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox());
      await app.assets.waitForIdle();
    });
  }, skip: !available);
  testWidgets(
    'cache page lists cover and manual lyric resources without cached audio',
    (tester) async {
      await tester.runAsync(() async {
        await app.assets.put(
          's',
          'album',
          'cover',
          'v1',
          await File('test/fixtures/cover.png').readAsBytes(),
        );
        await app.assets.link(track.ref, 'album', 'cover');
        await app.assets.link(const TrackRef('s', 'other'), 'album', 'cover');
        await app.assets.put(
          's',
          'manual',
          'lyrics',
          'manual-v1',
          utf8.encode('manual fixture'),
          pinned: true,
        );
        await app.assets.link(track.ref, 'manual', 'manual');
      });
      await tester.pumpWidget(MaterialApp(home: CacheStoragePage(app: app)));
      await waitFor(tester, () => find.text('fixture').evaluate().isNotEmpty);
      expect(find.textContaining('2 首关联歌曲'), findsOneWidget);
      await tester.tap(find.text('fixture'));
      await tester.pumpAndSettle();
      expect(find.text('共享文件，全局占用只计算一次'), findsOneWidget);
      expect(find.textContaining('包含受保护的手动歌词'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !available,
  );
}
