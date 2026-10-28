import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:sylphy_music/core/app_controller.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/core/player_layout.dart';
import 'package:sylphy_music/core/player_layout_store.dart';
import 'package:sylphy_music/ui/now_playing.dart';
import 'package:sylphy_music/ui/player_cover.dart';
import 'package:sylphy_music/ui/lyrics_view.dart';
import 'package:sylphy_music/ui/player_layout/layout_editor.dart';

import '../test/live_emby_test.dart' show MemoryVault;
import '../test/playback_native_test.dart' show wav;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'editor gestures, isolation, apply, recovery menu and responsive layouts',
    (tester) async {
      MediaKit.ensureInitialized();
      final root = await Directory.systemTemp.createTemp('sylphy-layout-ui-');
      final app = await SylphyApp.bootstrap(
        dataRoot: root,
        credentialVault: MemoryVault(),
        resumeBackground: false,
        platformIntegration: false,
      );
      if (const bool.fromEnvironment('SYLPHY_HEADLESS_AUDIO')) {
        final native = app.playback.player.platform;
        if (native is NativePlayer) {
          await native.setProperty('options/ao', 'null');
        }
      }
      final boundary = GlobalKey();
      Future<void> capture(String name) async {
        await tester.pump();
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/test_logs/layout').create(recursive: true);
        await File('build/test_logs/layout/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 100; i++) {
          await tester.pump();
          if (finder.evaluate().isNotEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fail('UI did not load');
      }

      Future<void> edit() async {
        await tester.tap(find.byTooltip('更多'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('编辑播放页'));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerLayoutEditor), findsOneWidget);
      }

      Future<void> revealEditorControl(Finder control) async {
        final scrollable = find.descendant(
          of: find.byKey(const ValueKey('player-inspector')),
          matching: find.byType(Scrollable),
        );
        tester.state<ScrollableState>(scrollable).position.jumpTo(0);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(control, 120, scrollable: scrollable);
        await tester.pumpAndSettle();
      }

      try {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 800);
        final file = await wav(root, 'layout');
        final short = await file.readAsBytes();
        final audio = Uint8List(44 + (short.length - 44) * 10)
          ..setRange(0, 44, short);
        for (var i = 0; i < 10; i++) {
          audio.setRange(
            44 + i * (short.length - 44),
            44 + (i + 1) * (short.length - 44),
            short,
            44,
          );
        }
        final header = ByteData.sublistView(audio);
        header.setUint32(4, audio.length - 8, Endian.little);
        header.setUint32(40, audio.length - 44, Endian.little);
        await file.writeAsBytes(audio);
        final cover = await File('test/fixtures/cover.png')
            .copy('${root.path}/cover.png');
        await File(file.path.replaceAll('.wav', '.lrc'))
            .writeAsString('[00:00]风穿过森林\n[00:02]让旋律轻轻停留\n[00:04]照亮归途');
        await app.db.putSource(
          const SourceProfile(
            id: 'local',
            name: '合成测试',
            kind: SourceKind.local,
            url: 'file:///',
            username: '',
          ),
        );
        final track = Track(
          ref: const TrackRef('local', 'fixture'),
          title: '风穿过森林',
          artist: 'Sylphy Studio',
          album: '绿野来信',
          remote: {'path': file.path, 'coverPath': cover.path},
        );
        await app.db.replaceSourceTracks('local', [track]);
        await app.reload();
        await app.playback.setVolume(0);
        await app.playback.setQueue([track.ref], autoplay: false);
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: NowPlayingPage(app: app),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('播放模式：列表循环'), findsOneWidget);
        expect(find.byTooltip('随机播放'), findsNothing);
        await tester.tap(find.byTooltip('播放模式：列表循环'));
        await waitFor(find.byTooltip('播放模式：单曲循环'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('播放模式：单曲循环'));
        await waitFor(find.byTooltip('播放模式：随机播放'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('播放模式：随机播放'));
        await waitFor(find.byTooltip('播放模式：列表循环'));
        await tester.pumpAndSettle();
        expect(find.byType(AppBar), findsNothing);
        expect(find.byTooltip('收起播放器'), findsNothing);
        final quickActions = find.byKey(const ValueKey('player-quick-actions'));
        expect(quickActions, findsOneWidget);
        expect(
          tester.getBottomLeft(quickActions).dy,
          lessThan(
            tester
                .getTopLeft(
                  find.byKey(const ValueKey('player-element/progress')),
                )
                .dy,
          ),
        );
        final actionPositions = [
          '睡眠定时',
          '歌词页',
          '收藏',
          '更多',
        ].map((label) => tester.getCenter(find.byTooltip(label)).dx).toList();
        expect(actionPositions, orderedEquals([...actionPositions]..sort()));
        await tester.tap(find.byTooltip('睡眠定时'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('15 分钟'));
        await tester.pumpAndSettle();
        expect(app.sleepTimer.active, isTrue);
        await tester.tap(find.byTooltip('歌词页'));
        await waitFor(find.byKey(const ValueKey('lyrics-page')));
        await tester.pumpAndSettle();
        expect(app.sleepTimer.active, isTrue);
        await tester.tap(find.byTooltip('返回播放页'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('睡眠定时'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消定时'));
        await tester.pumpAndSettle();
        expect(app.sleepTimer.active, isFalse);
        await tester.tap(find.byTooltip('收藏'));
        await tester.pumpAndSettle();
        expect(await app.db.playlistKeys('favorites'), contains(track.ref.key));
        expect(find.byTooltip('取消收藏'), findsOneWidget);
        await tester.tap(find.byTooltip('取消收藏'));
        await tester.pumpAndSettle();
        await app.playback.play();
        app.sleepTimer.start(const Duration(milliseconds: 150));
        for (
          var i = 0;
          i < 100 && (app.sleepTimer.active || app.playback.playing);
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
        expect(app.sleepTimer.active, isFalse);
        expect(app.playback.playing, isFalse);
        await app.appearance.update(record: true);
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('唱片封面'), findsOneWidget);
        await edit();
        expect(find.bySemanticsLabel('唱片封面'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('edit-cover')));
        await tester.pumpAndSettle();
        final rotation = find.byKey(const ValueKey('editor-disc-rotation'));
        await revealEditorControl(rotation);
        await tester.tap(rotation);
        await tester.pumpAndSettle();
        expect(app.appearance.discRotation, isTrue);
        expect(await app.db.setting('ui_disc_rotation'), 'true');
        expect(
          tester.widget<PlayerCover>(find.byType(PlayerCover)).rotate,
          isTrue,
        );
        await tester.tap(rotation);
        await tester.pumpAndSettle();
        expect(app.appearance.discRotation, isFalse);
        await capture('editor-mobile');
        final ref = app.playback.current!.ref;
        final position = app.playback.position;
        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byKey(const ValueKey('edit-cover')),
          const Offset(40, 0),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.byTooltip('撤销'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.redo))
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.byTooltip('重做'));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const ValueKey('resize-handle')),
          const Offset(-25, -25),
        );
        await tester.pumpAndSettle();
        await capture('editor-selected-mobile');
        expect(
          tester.getRect(find.byType(PlayerCover)),
          tester.getRect(find.byKey(const ValueKey('edit-cover'))),
        );
        await tester.tap(find.byKey(const ValueKey('edit-progress')));
        await tester.pumpAndSettle();
        expect(app.playback.position, position);
        expect(app.playback.current!.ref, ref);
        expect(app.playback.playing, isFalse);
        await tester.tap(find.byKey(const ValueKey('edit-lyrics')));
        await tester.pumpAndSettle();
        final lineHeightSlider = find.byKey(
          const ValueKey('editor-lyric-line-height'),
        );
        await tester.ensureVisible(lineHeightSlider);
        await tester.pumpAndSettle();
        await tester.drag(lineHeightSlider, const Offset(35, 0));
        await tester.pumpAndSettle();
        final chosenLineHeight = tester.widget<Slider>(lineHeightSlider).value;
        expect(chosenLineHeight, isNot(1.5));
        expect(
          tester
              .widget<LyricsPreview>(find.byType(LyricsPreview).first)
              .lineHeight,
          chosenLineHeight,
        );
        await tester.tap(find.byTooltip('撤销'));
        await tester.pumpAndSettle();
        expect(tester.widget<Slider>(lineHeightSlider).value, 1.5);
        await tester.tap(find.byTooltip('重做'));
        await tester.pumpAndSettle();
        expect(tester.widget<Slider>(lineHeightSlider).value, chosenLineHeight);
        await capture('editor-lyrics-spacing-mobile');
        await tester.tap(find.byTooltip('预览布局'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('edit-progress')), findsNothing);
        await tester.tapAt(tester.getCenter(find.byTooltip('播放')));
        await tester.pumpAndSettle();
        expect(app.playback.playing, isFalse);
        await tester.tap(find.byTooltip('继续编辑'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('保存并应用'));
        await waitFor(find.byType(NowPlayingPage));
        await tester.pumpAndSettle();
        expect(app.playerLayouts.active, isNotNull);
        expect(
          app.playerLayouts.active!.elements
              .firstWhere((e) => e.type == PlayerPart.lyrics)
              .lyricLineHeight,
          chosenLineHeight,
        );
        expect(
          tester
              .widget<LyricsPreview>(find.byType(LyricsPreview).first)
              .lineHeight,
          chosenLineHeight,
        );
        expect(app.appearance.disc, isTrue);
        expect(find.bySemanticsLabel('唱片封面'), findsOneWidget);
        expect(
          app.playerLayouts.active!.elements.first.frame,
          isNot(playerTemplate().elements.first.frame),
        );
        expect(find.byTooltip('播放队列'), findsOneWidget);
        await app.playerLayouts.save(
          app.playerLayouts.active!.copyWith(
            elements: [
              for (final e in app.playerLayouts.active!.elements)
                if (e.type == PlayerPart.controls)
                  e.copyWith(
                    radius: 8,
                    playWidth: 88,
                    playHeight: 80,
                    controlSpacing: 8,
                  )
                else
                  e,
            ],
          ),
        );
        await tester.pumpAndSettle();
        final playButton = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.play_arrow_rounded),
        );
        expect(
          (playButton.style!.shape!.resolve(
            {},
          ) as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(8),
        );
        expect(playButton.style!.fixedSize!.resolve({}), const Size(88, 80));
        final playFinder = find.widgetWithIcon(
          IconButton,
          Icons.play_arrow_rounded,
        );
        expect(tester.getSize(playFinder), const Size(88, 80));
        double gap() =>
            tester.getTopLeft(playFinder).dx -
            tester.getTopRight(find.byTooltip('上一首')).dx;
        expect(gap(), closeTo(8, .1));
        await app.playerLayouts.save(
          app.playerLayouts.active!.copyWith(
            elements: [
              for (final e in app.playerLayouts.active!.elements)
                if (e.type == PlayerPart.controls)
                  e.copyWith(controlSpacing: 32)
                else
                  e,
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(gap(), greaterThan(8));
        expect(gap(), lessThanOrEqualTo(32));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('open-lyrics/lyrics')));
        await waitFor(find.byKey(const ValueKey('timed-lyrics')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('lyrics-page')), findsOneWidget);
        expect(app.playback.playing, isFalse);
        expect(app.playback.position, position);
        await capture('custom-lyrics-page');
        await tester.tap(find.byTooltip('返回播放页'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('播放队列'));
        await tester.pumpAndSettle();
        expect(find.text('播放队列 · 1 首'), findsOneWidget);
        Navigator.of(tester.element(find.text('播放队列 · 1 首'))).pop();
        await tester.pumpAndSettle();
        expect(find.byTooltip('播放模式：列表循环'), findsOneWidget);
        await tester.tap(find.byTooltip('播放模式：列表循环'));
        await waitFor(find.byTooltip('播放模式：单曲循环'));
        await tester.pumpAndSettle();
        expect(app.playback.snapshot.shuffle, isFalse);
        await capture('custom-player-mobile');
        await tester.tap(find.byTooltip('更多'));
        await tester.pumpAndSettle();
        expect(find.byType(PopupMenuItem<String>), findsNWidgets(2));
        expect(find.text('音质信息'), findsOneWidget);
        expect(find.text('导入这首歌的歌词'), findsNothing);
        await tester.tap(find.text('编辑播放页'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('edit-cover')));
        await tester.pumpAndSettle();
        final discSwitch = find.byKey(const ValueKey('editor-disc'));
        await revealEditorControl(discSwitch);
        await tester.tap(discSwitch);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('关闭编辑器'));
        await tester.pumpAndSettle();
        expect(app.appearance.disc, isFalse);
        expect(find.bySemanticsLabel('专辑封面'), findsOneWidget);
        await tester.tap(find.byTooltip('播放'));
        for (var i = 0; i < 100 && !app.playback.playing; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
        expect(
          app.playback.playing,
          isTrue,
          reason:
              'before edit: position=${app.playback.position.inMilliseconds}, duration=${app.playback.duration.inMilliseconds}, error=${app.playback.error != null}',
        );
        await edit();
        await tester.tap(find.byTooltip('选择布局模板'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('歌词优先').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('保存并应用'));
        await tester.pumpAndSettle();
        await waitFor(find.byKey(const ValueKey('lyrics-preview/lyrics')));
        await tester.pumpAndSettle();
        expect(
          app.playback.playing,
          isTrue,
          reason:
              'after edit: position=${app.playback.position.inMilliseconds}, duration=${app.playback.duration.inMilliseconds}, error=${app.playback.error}',
        );
        await app.playback.pause();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        final pausedPosition = app.playback.position;
        await tester.tap(find.byKey(const ValueKey('open-lyrics/lyrics')));
        await waitFor(find.byKey(const ValueKey('timed-lyrics')));
        await tester.pumpAndSettle();
        await capture('custom-lyrics-mobile');
        tester.view.physicalSize = const Size(1200, 850);
        await tester.pumpAndSettle();
        await capture('custom-lyrics-wide');
        expect(
          tester.getSize(
            find.widgetWithIcon(IconButton, Icons.play_arrow_rounded),
          ),
          const Size(64, 64),
        );
        await tester.tap(find.byTooltip('返回播放页'));
        await tester.pumpAndSettle();
        await capture('custom-player-wide');
        await edit();
        await capture('editor-wide');
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('关闭编辑器'));
        await tester.pumpAndSettle();
        final restored = PlayerLayoutStore(app.db);
        await restored.initialize();
        expect(restored.active!.name, '歌词优先');
        await restored.shutdown();
        // Even a layout with all transport controls removed retains the page menu.
        await app.playerLayouts.save(
          app.playerLayouts.active!.copyWith(elements: []),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('更多'), findsOneWidget);
        expect(find.byTooltip('收起播放器'), findsNothing);
        expect(
          find.byKey(const ValueKey('player-quick-actions')),
          findsOneWidget,
        );
        await edit();
        expect(find.byTooltip('保存并应用'), findsOneWidget);
        await tester.tap(find.byTooltip('关闭编辑器'));
        await tester.pumpAndSettle();
        await edit();
        await tester.tap(find.byTooltip('布局操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('使用系统默认布局'));
        await tester.pumpAndSettle();
        expect(app.playerLayouts.active, isNull);
        expect(find.byTooltip('播放队列'), findsOneWidget);
        tester.view.physicalSize = const Size(320, 640);
        final small = playerTemplate(lyrics: true);
        await app.playerLayouts.save(
          small.copyWith(
            elements: [
              for (final e in small.elements)
                if (e.type == PlayerPart.controls)
                  e.copyWith(playWidth: 96, playHeight: 96, controlSpacing: 32)
                else
                  e,
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(
            find.widgetWithIcon(IconButton, Icons.play_arrow_rounded),
          ),
          const Size(96, 96),
        );
        await capture('custom-controls-small');
        await tester.tap(find.byKey(const ValueKey('open-lyrics/lyrics')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('lyrics-page')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('返回播放页'));
        await tester.pumpAndSettle();
        expect(app.playback.current!.ref, ref);
        expect(app.playback.position, pausedPosition);
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
