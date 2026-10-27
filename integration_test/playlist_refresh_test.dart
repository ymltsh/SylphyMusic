import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:sylphy_music/core/app_controller.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/ui/app_shell.dart';
import 'package:sylphy_music/ui/app_theme.dart';
import 'package:sylphy_music/ui/cover_art.dart';
import 'package:sylphy_music/ui/player_bar.dart';
import 'package:sylphy_music/ui/playlist_page.dart';

import '../test/live_emby_test.dart' show MemoryVault;
import '../test/playback_native_test.dart' show wav;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'playlist cover grids, detail playback, editing and readonly restrictions',
    (tester) async {
      MediaKit.ensureInitialized();
      final root = await Directory.systemTemp.createTemp('sylphy-playlist-ui-');
      final app = await SylphyApp.bootstrap(
        dataRoot: root,
        credentialVault: MemoryVault(),
        resumeBackground: false,
        platformIntegration: false,
      );
      final boundary = GlobalKey();
      var textScale = 1.0;
      Widget shell() => RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          theme: sylphyTheme(app.appearance, Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: SylphyShell(app: app),
        ),
      );
      Future<void> capture(String name) async {
        await tester.pump();
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File('build/test_logs/ui/$name.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 150; i++) {
          await tester.pump();
          if (finder.evaluate().isNotEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fail('Expected playlist UI did not load: $finder');
      }

      Finder card(String id) => find.byKey(ValueKey('playlist/$id'));
      Future<void> openCard(String id) async {
        await tester.ensureVisible(card(id));
        await tester.tap(card(id));
        await tester.pumpAndSettle();
      }

      Future<void> menu(String id) async {
        final button = find.descendant(
          of: card(id),
          matching: find.byTooltip('歌单操作'),
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      try {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 800);
        await app.db.setSetting('ui_onboarded', 'true');
        await app.db.putSource(
          const SourceProfile(
            id: 'local',
            name: '合成音乐',
            kind: SourceKind.local,
            url: 'file:///',
            username: '',
          ),
        );
        final audio = await wav(root, 'playlist');
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(const Color(0xff5094b2), BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(128, 128);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final cover = File('${root.path}/cover.png');
        await cover.writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
        final tracks = [
          for (var i = 0; i < 2; i++)
            Track(
              ref: TrackRef('local', '$i'),
              title: '合成歌曲 $i',
              artist: 'Sylphy',
              album: '测试专辑',
              remote: {'path': audio.path, 'coverPath': cover.path},
            ),
        ];
        await app.db.replaceSourceTracks('local', tracks);
        final local = const PlaylistModel(
          id: 'a-local',
          name: '风穿过森林的歌单 · Playlist',
          kind: PlaylistKind.local,
        );
        const empty = PlaylistModel(
          id: 'b-empty',
          name: '空歌单',
          kind: PlaylistKind.local,
        );
        const readonly = PlaylistModel(
          id: 'c-readonly',
          name: '只读云歌单',
          kind: PlaylistKind.cloud,
          sourceId: 'fixture-cloud',
          status: SyncStatus.readonly,
        );
        const conflict = PlaylistModel(
          id: 'd-conflict',
          name: '冲突云歌单',
          kind: PlaylistKind.cloud,
          sourceId: 'fixture-cloud',
          status: SyncStatus.conflict,
          message: '保留两份修改',
        );
        for (final p in [local, empty, readonly, conflict]) {
          await app.db.putPlaylist(p);
        }
        final keys = [tracks[0].ref.key, tracks[1].ref.key, tracks[0].ref.key];
        await app.db.replacePlaylistKeys(local.id, keys);
        await app.db.replacePlaylistKeys(readonly.id, [tracks[0].ref.key]);
        await app.db.replacePlaylistKeys(conflict.id, [tracks[1].ref.key]);
        final preview = await app.db.playlistPreview(local.id);
        expect(preview.count, 3);
        expect(preview.firstKey, keys.first);
        expect((await app.db.playlistPreview(empty.id)).firstKey, isNull);
        await app.reload();
        await app.playback.setVolume(0);
        await tester.pumpWidget(shell());
        await tester.pumpAndSettle();
        await tester.tap(find.text('歌单').first);
        await tester.pumpAndSettle();
        final grid = tester.widget<GridView>(find.byType(GridView));
        expect(
          (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          2,
        );
        await waitFor(
          find.descendant(of: card(local.id), matching: find.text('3 首')),
        );
        final firstCover = find.descendant(
          of: card(local.id),
          matching: find.byType(CoverArt),
        );
        expect(tester.widget<CoverArt>(firstCover).track.ref, tracks.first.ref);
        await waitFor(
          find.descendant(of: firstCover, matching: find.byType(Image)),
        );
        await capture('playlists-grid-mobile');
        tester.view.physicalSize = const Size(1200, 850);
        await tester.pumpAndSettle();
        expect(
          (tester.widget<GridView>(find.byType(GridView)).gridDelegate
                  as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          greaterThan(2),
        );
        await capture('playlists-grid-desktop');
        tester.view.physicalSize = const Size(320, 640);
        textScale = 2;
        await tester.pumpWidget(shell());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture('playlists-grid-large-text');
        textScale = 1;
        tester.view.physicalSize = const Size(360, 800);
        await tester.pumpWidget(shell());
        await tester.pumpAndSettle();
        await menu(conflict.id);
        expect(find.text('解决同步冲突'), findsOneWidget);
        await tester.tap(find.text('解决同步冲突'));
        await tester.pumpAndSettle();
        expect(find.text('保留云端，另存本地草稿'), findsOneWidget);
        await tester.tap(find.text('稍后处理'));
        await tester.pumpAndSettle();
        await menu(readonly.id);
        expect(
          tester
              .widget<PopupMenuItem<String>>(
                find.widgetWithText(PopupMenuItem<String>, '重命名歌单'),
              )
              .enabled,
          isFalse,
        );
        expect(
          tester
              .widget<PopupMenuItem<String>>(
                find.widgetWithText(PopupMenuItem<String>, '从服务器删除（在线）'),
              )
              .enabled,
          isFalse,
        );
        expect(find.text('复制为本地歌单'), findsOneWidget);
        expect(find.text('复制为云端歌单'), findsOneWidget);
        expect(find.text('同步此云歌单'), findsOneWidget);
        await tester.tap(find.text('复制为本地歌单'));
        await tester.pumpAndSettle();
        expect(
          app.playlists.where((p) => p.kind == PlaylistKind.local).length,
          3,
        );
        await openCard(readonly.id);
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.edit_outlined),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.playlist_add),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.download_outlined),
              )
              .onPressed,
          isNotNull,
        );
        await capture('playlist-readonly-mobile');
        await tester.pageBack();
        await tester.pumpAndSettle();
        await openCard(empty.id);
        expect(find.text('这个歌单暂无歌曲'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const ValueKey('playlist-play')))
              .onPressed,
          isNull,
        );
        expect(find.byType(PlayerBar), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(PlaylistPage),
            matching: find.byType(CoverArt),
          ),
          findsNothing,
        );
        await capture('playlist-empty-mobile');
        await tester.pageBack();
        await tester.pumpAndSettle();
        await openCard(local.id);
        expect(find.text('3 首歌曲'), findsOneWidget);
        expect(find.byType(PlayerBar), findsOneWidget);
        expect(find.byTooltip('播放全部'), findsNothing);
        await capture('playlist-detail-mobile');
        await tester.tap(find.byTooltip('随机播放歌单'));
        await tester.pumpAndSettle();
        expect(app.playback.snapshot.playbackMode, PlaybackMode.shuffle);
        expect(app.playback.snapshot.tracks, keys);
        expect(app.playback.playing, isTrue);
        expect(find.byTooltip('暂停'), findsOneWidget);
        await tester.tap(find.byTooltip('暂停'));
        await tester.pumpAndSettle();
        expect(app.playback.playing, isFalse);
        await tester.tap(find.byKey(const ValueKey('playlist-play')));
        await tester.pumpAndSettle();
        expect(app.playback.snapshot.playbackMode, PlaybackMode.listLoop);
        expect(app.playback.snapshot.index, 0);
        expect(app.playback.snapshot.tracks, keys);
        await app.playback.pause();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('编辑歌单'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('移除这条歌单记录').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('保存修改'));
        await tester.pumpAndSettle();
        expect(await app.db.playlistKeys(local.id), [keys[1], keys[2]]);
        expect(find.text('2 首歌曲'), findsOneWidget);
        final detailCovers = find.descendant(
          of: find.byType(NestedScrollView),
          matching: find.byType(CoverArt),
        );
        expect(
          tester.widget<CoverArt>(detailCovers.first).track.ref,
          tracks[1].ref,
        );
        tester.view.physicalSize = const Size(320, 640);
        textScale = 2;
        await tester.pumpWidget(shell());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture('playlist-detail-large-text');
        textScale = 1;
        tester.view.physicalSize = const Size(1200, 850);
        await tester.pumpWidget(shell());
        await tester.pumpAndSettle();
        await capture('playlist-detail-desktop');
        await tester.pumpWidget(const SizedBox());
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await app.disposeAsync();
        await root.delete(recursive: true);
      }
    },
  );
}
