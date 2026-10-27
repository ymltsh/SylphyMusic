import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:sylphy_music/core/app_controller.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/core/appearance.dart';
import 'package:sylphy_music/ui/app_shell.dart';
import 'package:sylphy_music/ui/lyrics_view.dart';
import 'package:sylphy_music/ui/now_playing.dart';
import 'package:sylphy_music/ui/player_bar.dart';
import 'package:sylphy_music/ui/player_cover.dart';
import 'package:sylphy_music/ui/player_visuals.dart';
import 'package:sylphy_music/ui/rotating_cover.dart';
import 'package:sylphy_music/ui/app_theme.dart';
import 'package:sylphy_music/ui/system_bars.dart';

import '../test/live_emby_test.dart' show MemoryVault;
import '../test/playback_native_test.dart' show wav;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'UI navigation, onboarding persistence, responsive layouts and player styles',
    (tester) async {
      MediaKit.ensureInitialized();
      final root = await Directory.systemTemp.createTemp('sylphy-ui-');
      final app = await SylphyApp.bootstrap(
        dataRoot: root,
        credentialVault: MemoryVault(),
        resumeBackground: false,
        platformIntegration: false,
      );
      await app.appearance.update(theme: ThemeMode.light);
      final boundary = GlobalKey();
      final output = Directory('build/test_logs/ui');
      await output.create(recursive: true);
      Widget shell() => RepaintBoundary(
        key: boundary,
        child: ListenableBuilder(
          listenable: app.appearance,
          builder: (context, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            themeMode: app.appearance.mode,
            theme: sylphyTheme(app.appearance, Brightness.light),
            darkTheme: sylphyTheme(app.appearance, Brightness.dark),
            builder: (context, child) => AppSystemBars(child: child!),
            home: SylphyShell(app: app),
          ),
        ),
      );
      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 100; i++) {
          await tester.pump();
          if (finder.evaluate().isNotEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fail('Expected UI content did not load');
      }

      Future<void> capture(String name) async {
        await tester.pump();
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${output.path}/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
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
        await tester.pumpWidget(shell());
        await tester.pumpAndSettle();
        expect(find.text('让音乐，轻盈相随'), findsOneWidget);
        await capture('welcome-mobile');
        await tester.tap(find.text('稍后设置，先进入首页'));
        await tester.pumpAndSettle();
        expect(find.byType(NavigationDestination), findsNWidgets(4));
        expect(tester.getSize(find.byType(NavigationBar)).height, 54);
        expect(find.byTooltip('设置'), findsOneWidget);
        tester.binding.platformDispatcher.localeTestValue = const Locale('en');
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('sylphymusic'),
          ),
          findsOneWidget,
        );
        tester.binding.platformDispatcher.localeTestValue = const Locale('zh');
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: find.byType(AppBar), matching: find.text('风灵音乐')),
          findsOneWidget,
        );

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(shell());
        await tester.pumpAndSettle();
        expect(find.text('让音乐，轻盈相随'), findsNothing);
        await app.db.putSource(
          const SourceProfile(
            id: 'demo',
            name: '本地音乐',
            kind: SourceKind.local,
            url: 'file:///',
            username: '',
          ),
        );
        await app.db.putSource(
          const SourceProfile(
            id: 'empty-fixture',
            name: '空曲库',
            kind: SourceKind.local,
            url: 'file:///',
            username: '',
          ),
        );
        final file = await wav(root, 'fixture');
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        const coverRect = Rect.fromLTWH(0, 0, 512, 512);
        canvas.drawRect(
          coverRect,
          Paint()
            ..shader = const LinearGradient(
              colors: [Color(0xff183d53), Color(0xff86b4aa), Color(0xffe3b98c)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(coverRect),
        );
        canvas.drawCircle(
          const Offset(350, 150),
          65,
          Paint()..color = const Color(0xfff4dec0),
        );
        final picture = recorder.endRecording();
        final coverImage = await picture.toImage(512, 512);
        final coverBytes = await coverImage.toByteData(
          format: ui.ImageByteFormat.png,
        );
        final coverFile = File('${root.path}/synthetic-cover.png');
        await coverFile.writeAsBytes(coverBytes!.buffer.asUint8List());
        coverImage.dispose();
        picture.dispose();
        final tracks = List.generate(
          3,
          (i) => Track(
            ref: TrackRef('demo', '$i'),
            title: ['风穿过森林', '午后的一封信', '在远方'][i],
            artist: 'Sylphy Studio',
            album: ['绿野来信', '缓慢时光', '山与海'][i],
            remote: {'path': file.path, 'coverPath': coverFile.path},
          ),
        );
        await app.db.replaceSourceTracks('demo', tracks);
        await app.reload();
        await tester.pumpAndSettle();
        await waitFor(find.text('绿野来信'));
        await tester.pumpAndSettle();
        await capture('home-mobile');
        expect(tester.takeException(), isNull);
        final collapsedFab = find.byKey(const ValueKey('collapsed-player-fab'));
        await tester.longPress(find.byTooltip('播放队列'));
        await tester.pumpAndSettle();
        expect(collapsedFab, findsNothing);
        await tester.longPress(find.text('选择一首音乐开始播放'));
        await tester.pumpAndSettle();
        expect(collapsedFab, findsOneWidget);
        await capture('home-collapsed-fab');
        await tester.tap(collapsedFab);
        await tester.pumpAndSettle();
        expect(collapsedFab, findsNothing);
        expect(find.text('选择一首音乐开始播放'), findsOneWidget);
        await tester.tap(find.text('音乐库').first);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: find.byType(AppBar), matching: find.text('音乐库')),
          findsOneWidget,
        );
        expect(find.byType(ChoiceChip), findsNWidgets(3));
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(const ValueKey('library-filter-0')),
              )
              .selected,
          isTrue,
        );
        expect(find.text('3'), findsOneWidget);
        expect(find.textContaining('播放全部'), findsNothing);
        final summary = find.byKey(const ValueKey('song-summary'));
        final filters = find.byKey(const ValueKey('library-filter-bar'));
        expect(
          tester.getTopLeft(filters).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(summary).dy),
        );
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('library-filter-0'))).dx,
          tester.getTopLeft(summary).dx + 16,
        );
        for (var index = 0; index < 3; index++) {
          final chip = tester.widget<ChoiceChip>(
            find.byKey(ValueKey('library-filter-$index')),
          );
          expect(
            chip.shape,
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          );
        }
        expect(
          find.descendant(of: summary, matching: find.byTooltip('音乐来源')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: summary, matching: find.byTooltip('排序')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: summary, matching: find.byTooltip('升序 / 降序')),
          findsOneWidget,
        );
        expect(
          tester.getCenter(find.byTooltip('排序')).dx,
          greaterThan(tester.getCenter(find.text('3')).dx),
        );
        await capture('library-sort-mobile');
        await tester.tap(find.byTooltip('音乐来源'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('空曲库').last);
        await tester.pumpAndSettle();
        expect(find.text('0'), findsOneWidget);
        expect(find.byTooltip('音乐来源'), findsOneWidget);
        await tester.tap(find.byTooltip('音乐来源'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('全部来源').last);
        await tester.pumpAndSettle();
        expect(find.text('3'), findsOneWidget);

        await tester.tap(find.byTooltip('排序'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('艺术家').last);
        await tester.pumpAndSettle();
        expect(find.text('3'), findsOneWidget);

        expect(find.byType(TextField), findsNothing);
        expect(find.byTooltip('下一页'), findsNothing);
        expect(find.byTooltip('刷新所有来源'), findsNothing);
        await tester.tap(find.byTooltip('搜索'));
        await tester.pumpAndSettle();
        expect(find.text('输入关键词，搜索你的音乐库'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '风穿过');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(find.text('风穿过森林'), findsOneWidget);
        expect(find.text('1'), findsOneWidget);
        await capture('search-mobile');
        await tester.enterText(find.byType(TextField), '无匹配关键词');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(find.text('没有找到匹配的音乐'), findsOneWidget);
        await tester.tap(find.byTooltip('清空搜索'));
        await tester.pumpAndSettle();
        expect(find.text('输入关键词，搜索你的音乐库'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);

        await tester.tap(find.byKey(const ValueKey('library-filter-1')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(const ValueKey('library-filter-1')),
              )
              .selected,
          isTrue,
        );
        expect(find.text('绿野来信'), findsOneWidget);
        // Hold SQLite long enough to observe a real in-flight category query.
        final filterBounds = tester.getRect(filters);
        final summaryBounds = tester.getRect(summary);
        final queryGate = Completer<void>();
        final queryHeld = Completer<void>();
        final heldTransaction = app.db.db.transaction((tx) async {
          queryHeld.complete();
          await queryGate.future;
        });
        await queryHeld.future;
        try {
          for (final view in [2, 0, 1]) {
            await tester.tap(find.byKey(ValueKey('library-filter-$view')));
            await tester.pump();
            expect(tester.getRect(filters), filterBounds);
            expect(tester.getRect(summary), summaryBounds);
            expect(
              find.descendant(of: summary, matching: find.text('—')),
              findsOneWidget,
            );
            expect(tester.widget<ListTile>(summary).onTap, isNull);
            expect(find.byTooltip('音乐来源'), findsOneWidget);
          }
        } finally {
          queryGate.complete();
          await heldTransaction;
        }
        await tester.pumpAndSettle();
        expect(tester.getRect(filters), filterBounds);
        expect(tester.getRect(summary), summaryBounds);
        expect(
          find.descendant(of: summary, matching: find.text('3')),
          findsOneWidget,
        );
        expect(tester.widget<ListTile>(summary).onTap, isNotNull);
        await app.playback.setVolume(0);
        for (final view in [1, 2]) {
          await tester.tap(find.byKey(ValueKey('library-filter-$view')));
          await tester.pumpAndSettle();
          expect(tester.getRect(filters), filterBounds);
          expect(tester.getRect(summary), summaryBounds);
          expect(
            find.descendant(
              of: summary,
              matching: find.text(view == 1 ? '3' : '1'),
            ),
            findsOneWidget,
          );
          expect(
            tester.getTopLeft(filters).dy,
            greaterThanOrEqualTo(tester.getBottomLeft(summary).dy),
          );
          expect(find.byTooltip('音乐来源'), findsOneWidget);
          expect(find.byTooltip('排序'), findsOneWidget);
          expect(tester.widget<ListTile>(summary).onTap, isNotNull);
          await capture(
            view == 1 ? 'library-albums-mobile' : 'library-artists-mobile',
          );
          await tester.tap(summary);
          for (var i = 0; i < 100 && !app.playback.playing; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
          }
          expect(app.playback.playing, isTrue);
          expect(
            app.playback.snapshot.tracks.toSet(),
            tracks.map((t) => t.ref.key).toSet(),
          );
          await app.playback.pause();
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('音乐来源'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('空曲库').last);
          await tester.pumpAndSettle();
          expect(
            find.descendant(of: summary, matching: find.text('0')),
            findsOneWidget,
          );
          expect(tester.getRect(filters), filterBounds);
          expect(tester.widget<ListTile>(summary).onTap, isNull);
          await tester.tap(find.byTooltip('音乐来源'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('全部来源').last);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('歌单').first);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: find.byType(AppBar), matching: find.text('歌单')),
          findsOneWidget,
        );
        await tester.tap(find.text('我的').first);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: find.byType(AppBar), matching: find.text('我的')),
          findsOneWidget,
        );
        await tester.tap(find.text('歌单').first);
        await tester.pumpAndSettle();
        expect(find.text('新建歌单'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('设置'));
        await tester.pumpAndSettle();
        await capture('settings-mobile');
        await tester.tap(find.text('音乐源管理'));
        await tester.pumpAndSettle();
        expect(find.text('同步所有来源'), findsOneWidget);
        await capture('sources-mobile');
        await tester.tap(find.text('本地音乐').first);
        await tester.pumpAndSettle();
        // Browsing a source closes its management page, then settings can return home.
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('3'), findsOneWidget);
        await tester.tap(find.text('首页').first);
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(1200, 850);
        await tester.pumpAndSettle();
        expect(find.byType(NavigationRail), findsOneWidget);
        await capture('home-desktop');
        await app.appearance.update(
          theme: ThemeMode.dark,
          record: true,
          frost: true,
        );
        final restored = Appearance(app.db);
        await restored.initialize();
        expect(restored.mode, ThemeMode.dark);
        expect(restored.disc, isTrue);
        expect(restored.glass, isTrue);
        restored.dispose();
        tester.view.physicalSize = const Size(360, 800);
        await tester.pumpAndSettle();
        await capture('home-mobile-dark');
        expect(tester.takeException(), isNull);
        await app.playback.setVolume(0);
        final historyBeforeResume = [...app.history.refs];
        await app.playback.setQueue([tracks.first.ref], autoplay: false);
        expect(app.history.refs, historyBeforeResume);
        await app.playback.play();
        await Future<void>.delayed(const Duration(seconds: 1));
        await app.playback.pause();
        expect(app.history.refs, [
          tracks.first.ref,
          ...historyBeforeResume.where((ref) => ref != tracks.first.ref),
        ]);
        await tester.pumpAndSettle();
        await tester.longPress(
          find.descendant(
            of: find.byType(PlayerBar),
            matching: find.text('风穿过森林'),
          ),
        );
        await tester.pumpAndSettle();
        final collapsedFabWithTrack = find.byKey(
          const ValueKey('collapsed-player-fab'),
        );
        expect(collapsedFabWithTrack, findsOneWidget);
        expect(
          find.descendant(
            of: collapsedFabWithTrack,
            matching: find.byType(RotatingCover),
          ),
          findsOneWidget,
        );
        await capture('home-player-fab');
        await tester.tap(collapsedFabWithTrack);
        await tester.pumpAndSettle();
        expect(collapsedFabWithTrack, findsNothing);
        expect(find.byType(PlayerBar), findsOneWidget);
        final ctx = tester.element(find.byType(SylphyShell));
        Navigator.push(
          ctx,
          MaterialPageRoute(builder: (_) => NowPlayingPage(app: app)),
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 500));
        await waitFor(
          find.descendant(
            of: find.byType(PlayerCover),
            matching: find.byType(Image),
          ),
        );
        await capture('player-disc-mobile');
        expect(find.bySemanticsLabel('唱片封面'), findsOneWidget);
        final playIcon = find.descendant(
          of: find.byTooltip('播放'),
          matching: find.byType(Icon),
        );
        expect(
          IconTheme.of(tester.element(playIcon)).color,
          Theme.of(tester.element(playIcon)).colorScheme.onPrimary,
        );
        expect(tester.takeException(), isNull);
        // A right-to-left swipe on the playback page opens the one lyrics page.
        await tester.dragFrom(const Offset(300, 330), const Offset(-220, 0));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('lyrics-page')), findsOneWidget);
        await tester.tap(find.byTooltip('返回播放页'));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('唱片封面'), findsOneWidget);
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
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.bySemanticsLabel('专辑封面'), findsOneWidget);
        await waitFor(find.textContaining('暂无歌词'));
        expect(find.textContaining('暂无歌词'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('open-lyrics/lyrics')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('lyrics-page')), findsOneWidget);
        await waitFor(find.text('当前歌曲没有可用歌词'));
        await tester.pumpAndSettle();
        await File(file.path.replaceAll('.wav', '.lrc')).writeAsString(
          '[00:00]风穿过森林\n[00:00]The wind through the trees\n'
          '[00:01]让旋律轻轻停留\n[00:02]长长的一句歌词，需要换成两行才能完整展示\n'
          '[00:04]\n[00:06]远方的光\n[00:08]照亮归途\n[00:10]尾声',
        );
        await tester.tap(find.text('重试'));
        await waitFor(find.byKey(const ValueKey('timed-lyrics')));
        await tester.pumpAndSettle();
        expect(find.text('歌词 · 跟随播放'), findsNothing);
        expect(find.text('风穿过森林\nThe wind through the trees'), findsOneWidget);
        await capture('player-lyrics-mobile');
        await tester.drag(
          find.byKey(const ValueKey('timed-lyrics')),
          const Offset(0, -160),
        );
        await tester.pumpAndSettle();
        expect(find.text('回到当前'), findsOneWidget);
        await tester.tap(find.text('回到当前'));
        await tester.pumpAndSettle();
        expect(find.text('回到当前'), findsNothing);
        await tester.tap(find.byTooltip('返回播放页'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('lyrics-page')), findsNothing);
        expect(
          find.byKey(const ValueKey('lyrics-preview/lyrics')),
          findsOneWidget,
        );
        expect(find.textContaining('The wind through the trees'), findsNothing);
        await app.playback.seek(const Duration(milliseconds: 2100));
        await tester.pumpAndSettle();
        final wrappedLyric = find.descendant(
          of: find.byType(LyricsPreview),
          matching: find.text('长长的一句歌词，需要换成两行才能完整展示'),
        );
        final wrappedParagraph = tester.renderObject<RenderParagraph>(
          wrappedLyric,
        );
        expect(wrappedParagraph.maxLines, 2);
        expect(wrappedParagraph.didExceedMaxLines, isFalse);
        expect(wrappedParagraph.size.height, greaterThan(30));
        await capture('player-lyrics-preview');
        expect(find.byTooltip('播放队列'), findsOneWidget);
        expect(
          tester.widget<LyricsPreview>(find.byType(LyricsPreview)).fontSize,
          20,
        );
        await tester.tap(find.byTooltip('更多'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('编辑播放页'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('edit-lyrics')));
        await tester.pumpAndSettle();
        final miniFont = find.byKey(const ValueKey('editor-mini-font/20.0'));
        await revealEditorControl(miniFont);
        await tester.tap(miniFont);
        await tester.pumpAndSettle();
        await tester.tap(find.text('大 · 24').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('关闭编辑器'));
        await tester.pumpAndSettle();
        expect(app.appearance.miniLyricFontSize, 24);
        expect(
          tester.widget<LyricsPreview>(find.byType(LyricsPreview)).fontSize,
          24,
        );
        tester.view.physicalSize = const Size(1200, 850);
        await tester.pumpAndSettle();
        await capture('player-immersive-wide');
        expect(find.bySemanticsLabel('专辑封面'), findsOneWidget);
        expect(find.byTooltip('播放队列'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('mini-lyrics-resize')), findsNothing);
        expect(find.byTooltip('拖动调整迷你歌词大小'), findsNothing);
        expect(
          find.byKey(const ValueKey('lyrics-preview/lyrics')),
          findsOneWidget,
        );
        await app.appearance.update(
          theme: ThemeMode.light,
          solid: true,
          background: false,
        );
        await tester.pumpAndSettle();
        final lightPlayIcon = tester.element(find.byTooltip('播放'));
        expect(Theme.of(lightPlayIcon).brightness, Brightness.light);
        final backdropBase = tester.widget<ColoredBox>(
          find
              .descendant(
                of: find.byType(PlayerBackdrop),
                matching: find.byType(ColoredBox),
              )
              .first,
        );
        expect(backdropBase.color, Colors.white);
        await capture('player-light-solid');
        await tester.tap(find.byTooltip('更多'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('编辑播放页'));
        await tester.pumpAndSettle();
        final ambient = find.byKey(const ValueKey('editor-ambient'));
        await revealEditorControl(ambient);
        await tester.tap(ambient);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('关闭编辑器'));
        await tester.pumpAndSettle();
        expect(app.appearance.ambient, isTrue);
        await capture('player-light-cover-blur');
        await tester.tap(find.byKey(const ValueKey('open-lyrics/lyrics')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('lyrics-page')), findsOneWidget);
        expect(
          Theme.of(tester.element(find.byKey(const ValueKey('lyrics-page'))))
              .brightness,
          Brightness.light,
        );
        await capture('player-lyrics-light');
        await tester.tap(find.byTooltip('返回播放页'));
        await tester.pumpAndSettle();
        await tester.dragFrom(const Offset(600, 30), const Offset(0, 260));
        await tester.pumpAndSettle();
        expect(find.byType(NowPlayingPage), findsNothing);
        await tester.pumpWidget(const SizedBox());
      } finally {
        tester.binding.platformDispatcher.clearLocaleTestValue();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await app.disposeAsync();
        await root.delete(recursive: true);
      }
    },
  );
}
