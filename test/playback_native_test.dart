import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:sylphy_music/core/app_controller.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/services/local_library.dart';
import 'package:sylphy_music/ui/app_shell.dart';
import 'package:sylphy_music/ui/playlist_page.dart';
import 'package:sylphy_music/ui/cache_tasks.dart';

Future<File> wav(Directory root, String name) async {
  const size = 6 * 8000 * 2;
  final bytes = ByteData(44 + size);
  void text(int at, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(at + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, 36 + size, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, 8000, Endian.little);
  bytes.setUint32(28, 16000, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, size, Endian.little);
  return File('${root.path}/$name.wav')
      .writeAsBytes(bytes.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library =
      Platform.environment['SYLPHY_MPV_LIBRARY'] ??
      'build/windows/x64/runner/Debug/libmpv-2.dll';
  final available = File(library).existsSync();
  late Directory root;
  late SylphyApp app;
  late List<Track> tracks;
  setUp(() async {
    if (!available) return;
    MediaKit.ensureInitialized(libmpv: File(library).absolute.path);
    root = await Directory.systemTemp.createTemp('sylphy-native-');
    app = await SylphyApp.bootstrap(
      dataRoot: root,
      resumeBackground: false,
      platformIntegration: false,
    );
    await app.playback.setVolume(0);
    await app.db.putSource(
      const SourceProfile(
        id: 'local',
        name: 'Local',
        kind: SourceKind.local,
        url: 'file:///',
        username: '',
      ),
    );
    tracks = [];
    for (final name in ['first', 'second', 'third']) {
      tracks.add(await LocalLibrary(root).read(await wav(root, name), 'local'));
    }
    await app.db.replaceSourceTracks('local', tracks);
    await app.reload();
    for (final track in tracks) {
      await app.artwork.load(track);
    }
  });
  tearDown(() async {
    if (!available) return;
    await app.disposeAsync();
    await root.delete(recursive: true);
  });

  test(
    'real libmpv local audio, seek, next, queue removal, paused restore',
    () async {
      final player = app.playback;
      await player.setQueue(tracks.map((t) => t.ref).toList(), autoplay: false);
      if (player.player.state.duration <= Duration.zero) {
        await player.player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 10));
      }
      expect(player.currentRef, tracks.first.ref);
      await player.seek(const Duration(seconds: 3));
      expect((await app.db.queue()).positionMs, closeTo(3000, 2));
      await player.next();
      await player.pause();
      expect(player.currentRef, tracks[1].ref);
      expect((await app.db.queue()).positionMs, lessThan(1000));
      await player.removeAt(0);
      expect(player.snapshot.index, 0);
      expect(player.currentRef, tracks[1].ref);
      await player.seek(const Duration(seconds: 2));
      await player.pause();
      final saved = await app.db.queue();
      expect(saved.positionMs, closeTo(2000, 2));
      expect(saved.tracks.length, 2);
      await player.previous();
      expect(player.currentRef, tracks[1].ref);
      await player.seek(const Duration(seconds: 2));
      await player.pause();
      await app.disposeAsync();
      app = await SylphyApp.bootstrap(
        dataRoot: root,
        resumeBackground: false,
        platformIntegration: false,
      );
      expect(app.playback.playing, isFalse);
      // Native floating-point timestamps can round down by one millisecond.
      expect(app.playback.position.inMilliseconds, closeTo(2000, 2));
      expect(app.playback.currentRef, tracks[1].ref);
      await app.playback.clearQueue();
      expect((await app.db.queue()).tracks, isEmpty);
    },
    skip: !available ? 'Build Windows debug or set SYLPHY_MPV_LIBRARY' : false,
  );

  test(
    'combined modes preserve current audio, persist and restore queue traversal',
    () async {
      final player = app.playback;
      await player.setQueue(
        tracks.map((t) => t.ref).toList(),
        start: 1,
        autoplay: false,
      );
      await player.seek(const Duration(seconds: 2));
      await player.pause();
      await player.cyclePlaybackMode();
      expect(player.snapshot.playbackMode, PlaybackMode.singleLoop);
      expect(player.snapshot.shuffle, isFalse);
      await player.cyclePlaybackMode();
      expect(player.snapshot.playbackMode, PlaybackMode.shuffle);
      expect(player.snapshot.repeat, RepeatKind.all);
      expect(player.snapshot.order.first, 1);
      expect(player.snapshot.order.toSet(), {0, 1, 2});
      expect(player.currentRef, tracks[1].ref);
      expect(player.position.inMilliseconds, closeTo(2000, 2));
      expect(player.playing, isFalse);
      final randomOrder = List.of(player.snapshot.order);
      await app.disposeAsync();
      app = await SylphyApp.bootstrap(
        dataRoot: root,
        resumeBackground: false,
        platformIntegration: false,
      );
      expect(app.playback.snapshot.playbackMode, PlaybackMode.shuffle);
      expect(app.playback.snapshot.order, randomOrder);
      expect(app.playback.currentRef, tracks[1].ref);
      expect(app.playback.playing, isFalse);
      await app.playback.cyclePlaybackMode();
      expect(app.playback.snapshot.playbackMode, PlaybackMode.listLoop);
      expect(app.playback.snapshot.order, [0, 1, 2]);
      await app.playback.jumpTo(2);
      await app.playback.next();
      await app.playback.pause();
      expect(app.playback.currentRef, tracks.first.ref);
    },
    skip: !available ? 'Build Windows debug or set SYLPHY_MPV_LIBRARY' : false,
  );

  test(
    'successful native playback progress clears a previous failure',
    () async {
      await app.playback.setQueue([tracks.first.ref]);
      await app.playback.player.stream.position
          .firstWhere((p) => p > Duration.zero)
          .timeout(const Duration(seconds: 5));
      app.playback.error = 'fixture transient load failure';
      for (var i = 0; i < 100 && app.playback.error != null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(app.playback.error, isNull);
      expect(app.playback.currentRef, tracks.first.ref);
      await app.playback.pause();
    },
    skip: !available,
  );

  testWidgets('mobile shell and queue render without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: SylphyShell(app: app)));
    await tester.runAsync(() async {
      for (var i = 0; i < 200; i++) {
        await tester.pump();
        if (find.text('属于你的音乐时光').evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      throw StateError('Catalog page did not load');
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('播放队列'));
    await tester.pumpAndSettle();
    expect(find.text('播放队列 · 0 首'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, skip: !available);

  testWidgets('playlist mutation and task refresh update their visible pages', (
    tester,
  ) async {
    Future<void> waitFor(String text) async {
      await tester.runAsync(() async {
        for (var i = 0; i < 200; i++) {
          await tester.pump();
          if (find.text(text).evaluate().isNotEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        throw StateError('Page did not show $text');
      });
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      MaterialApp(
        home: PlaylistPage(
          app: app,
          id: 'favorites',
          buildTracks: (tracks) => Text('Visible ${tracks.length}'),
          onEdit: () {},
          onAdd: () {},
          onCache: () {},
        ),
      ),
    );
    await waitFor('Visible 0');
    await tester.runAsync(() => app.toggleFavorite(tracks.first));
    await waitFor('Visible 1');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(MaterialApp(home: CacheTasksPage(app: app)));
    await waitFor('尚未创建缓存任务');
    await tester.pump(const Duration(seconds: 2));
    await waitFor('尚未创建缓存任务');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, skip: !available);
}
