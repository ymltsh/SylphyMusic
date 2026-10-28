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
import 'package:sylphy_music/services/app_updates.dart';
import 'package:sylphy_music/services/api_settings.dart';
import 'package:sylphy_music/ui/music_source_connection_page.dart';
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
        expect(find.textContaining('欢迎使用风灵音乐！'), findsOneWidget);
        expect(find.byTooltip('开始使用'), findsOneWidget);
        expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
        await capture('welcome-mobile');
        tester.view.physicalSize = const Size(320, 640);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture('welcome-small');
        tester.view.physicalSize = const Size(360, 800);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('开始使用'));
        await tester.pumpAndSettle();
        expect(find.text('选择歌曲来源'), findsOneWidget);
        expect(find.text('Navidrome / OpenSubsonic'), findsOneWidget);
        await capture('welcome-sources-mobile');
        await tester.tap(find.text('WebDAV'));
        await tester.pumpAndSettle();
        expect(find.byType(MusicSourceConnectionPage), findsOneWidget);
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'WebDAV'))
              .selected,
          true,
        );
        await capture('source-connection-mobile');
        tester.view.physicalSize = const Size(320, 640);
        await tester.pumpAndSettle();
        await capture('source-connection-small');
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(360, 800);
        await tester.pumpAndSettle();
        await tester.tap(find.text('本地音乐'));
        await tester.pumpAndSettle();
        expect(find.text('导入本地音频文件'), findsOneWidget);
        expect(find.text('添加本地音乐文件夹'), findsOneWidget);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        await tester.tap(find.text('下一步：API 配置'));
        await tester.pumpAndSettle();
        final quoteInput = find.widgetWithText(TextFormField, '每日一言 API');
        final mirrorInput = find.widgetWithText(TextFormField, 'GitHub 加速 API');
        await tester.enterText(quoteInput, 'https://example.invalid/json');
        await tester.enterText(mirrorInput, 'http://example.invalid/');
        await tester.tap(find.text('完成设置'));
        await tester.pumpAndSettle();
        expect(app.apiSettings.quoteUrl, ApiSettings.defaultQuoteUrl);
        expect(find.text('API 配置'), findsOneWidget);
        await tester.enterText(quoteInput, ApiSettings.defaultQuoteUrl);
        await tester.enterText(mirrorInput, 'https://example.invalid/proxy/');
        await tester.pumpAndSettle();
        expect(find.text('GitHub 加速 API 需要有效的 HTTPS 前缀地址'), findsNothing);
        await capture('welcome-api-mobile');
        await tester.tap(find.text('完成设置'));
        await tester.pumpAndSettle();
        final persistedApi = ApiSettings(app.db);
        await persistedApi.initialize();
        expect(persistedApi.githubMirror, 'https://example.invalid/proxy/');
        persistedApi.dispose();
        await app.apiSettings.setGitHubMirror(ApiSettings.defaultGitHubMirror);
        expect(find.byType(NavigationDestination), findsNWidgets(4));
        expect(tester.getSize(find.byType(NavigationBar)).height, 54);
        expect(find.byTooltip('设置'), findsOneWidget);
        tester.binding.platformDispatcher.localeTestValue = const Locale('en');
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Sylphy Music'),
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
        expect(find.byType(SegmentedButton<int>), findsNothing);
        for (var index = 0; index < 3; index++) {
          final chip = tester.widget<ChoiceChip>(
            find.byKey(ValueKey('search-filter-$index')),
          );
          expect(
            chip.shape,
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          );
        }
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(const ValueKey('search-filter-0')))
              .selected,
          isTrue,
        );
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
        final albumFlowToggle = find.byKey(
          const ValueKey('album-cover-flow-toggle'),
        );
        expect(albumFlowToggle, findsOneWidget);
        await tester.tap(albumFlowToggle);
        await tester.pumpAndSettle();
        final albumFlow = find.byKey(const ValueKey('album-cover-flow'));
        expect(albumFlow, findsOneWidget);
        expect(find.text('绿野来信'), findsOneWidget);
        await capture('library-albums-cover-flow-mobile');
        await tester.tapAt(tester.getCenter(albumFlow));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: find.byType(AppBar), matching: find.text('绿野来信')),
          findsOneWidget,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('切换到列表'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('album-cover-flow')), findsNothing);
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
        final newPlaylist = find.byKey(const ValueKey('new-playlist'));
        expect(tester.getTopLeft(newPlaylist).dx, 16);
        expect(
          tester.widget<FilledButton>(newPlaylist).style?.shape?.resolve({}),
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        );
        expect(
          tester.getCenter(find.byTooltip('同步云歌单')).dx,
          greaterThan(tester.getCenter(newPlaylist).dx),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('设置'));
        await tester.pumpAndSettle();
        Future<void> openSetting(String title) async {
          final scrollable = find.byType(Scrollable).last;
          // The list is lazy and may be scrolled below an earlier entry.
          await tester.drag(scrollable, const Offset(0, 3000));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text(title),
            200,
            scrollable: scrollable,
          );
          await tester.ensureVisible(find.text(title));
          await tester.pumpAndSettle();
          await tester.tap(find.text(title));
          await tester.pumpAndSettle();
        }

        expect(find.byType(Slider), findsNothing);
        expect(find.byType(SwitchListTile), findsNothing);
        expect(find.byType(DropdownButton<ThemeMode>), findsNothing);
        await capture('settings-mobile');
        await openSetting('播放器设置');
        expect(find.text('播放速度'), findsOneWidget);
        await tester.tap(find.byType(Slider).first);
        await tester.pumpAndSettle();
        expect(app.playback.speed, isNot(1));
        await app.playback.setSpeed(1);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await openSetting('歌词设置');
        await tester.tap(find.byType(DropdownButton<double>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('大').last);
        await tester.pumpAndSettle();
        expect(app.appearance.lyricFontSize, 28);
        expect(app.appearance.miniLyricFontSize, 20);
        await capture('settings-lyrics-mobile');
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('完整歌词 大 · 迷你歌词 标准'), findsOneWidget);
        await app.appearance.update(lyricFont: 24);
        await openSetting('主题与配色');
        await tester.tap(find.byType(DropdownButton<ThemeMode>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('深色').last);
        await tester.pumpAndSettle();
        expect(app.appearance.mode, ThemeMode.dark);
        await capture('settings-theme-dark');
        await tester.pageBack();
        await tester.pumpAndSettle();
        await capture('settings-mobile-dark');
        await app.appearance.update(theme: ThemeMode.light);
        await tester.pumpAndSettle();
        await openSetting('页面背景');
        expect(find.text('自定义背景图'), findsOneWidget);
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(app.appearance.solidBackground, isFalse);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await app.appearance.update(solid: true);
        await openSetting('播放器外观');
        await tester.tap(find.widgetWithText(SwitchListTile, '唱片播放样式'));
        await tester.pumpAndSettle();
        expect(app.appearance.disc, isTrue);
        await tester.tap(find.widgetWithText(SwitchListTile, '唱片旋转'));
        await tester.pumpAndSettle();
        expect(app.appearance.discRotation, isTrue);
        await capture('settings-player-mobile');
        await tester.pageBack();
        await tester.pumpAndSettle();
        await app.appearance.update(record: false, rotateDisc: false);
        await openSetting('下载与缓存');
        await tester.tap(find.text('缓存预算'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '3');
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        expect(app.cache.maxBytes, 3 * 1073741824);
        await tester.tap(find.text('清理全部完整歌曲缓存'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('缓存空间与逐曲清理'));
        await tester.pumpAndSettle();
        expect(find.text('缓存空间'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('查看缓存任务与进度'));
        await tester.pumpAndSettle();
        expect(find.byType(AppBar), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await capture('settings-cache-mobile');
        await tester.pageBack();
        await tester.pumpAndSettle();
        await openSetting('API 设置');
        final lrcToggle = find.byKey(const ValueKey('api-lrc-enabled'));
        expect(tester.widget<SwitchListTile>(lrcToggle).value, isFalse);
        await tester.tap(lrcToggle);
        await tester.pumpAndSettle();
        expect(app.apiSettings.lrcApiEnabled, isTrue);
        await tester.tap(find.byKey(const ValueKey('api-lrc-url')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          'http://127.0.0.1:28883',
        );
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        expect(app.apiSettings.lrcApiUrl, 'http://127.0.0.1:28883/lyrics');
        final auth = find.byKey(const ValueKey('api-lrc-auth'));
        await tester.ensureVisible(auth);
        await tester.pumpAndSettle();
        await tester.tap(auth);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).obscureText,
          isTrue,
        );
        await tester.enterText(
          find.byType(TextField),
          'synthetic-lrc-test-token',
        );
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        expect(
          await app.vault.read('lrcapi', 'token'),
          'synthetic-lrc-test-token',
        );
        await tester.tap(auth);
        await tester.pumpAndSettle();
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        expect(await app.vault.read('lrcapi', 'token'), isNull);
        await capture('settings-lrcapi-mobile');
        await tester.ensureVisible(lrcToggle);
        await tester.pumpAndSettle();
        await tester.tap(lrcToggle);
        await tester.pumpAndSettle();
        expect(app.apiSettings.lrcApiEnabled, isFalse);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await openSetting('检查更新');
        expect(find.text('仅在点击时检查更新，下载后由你手动安装。'), findsOneWidget);
        expect(find.text('正在检查…'), findsNothing);
        await capture('settings-update-mobile');
        await tester.pageBack();
        await tester.pumpAndSettle();
        await openSetting('诊断与反馈');
        expect(find.text('记录诊断日志'), findsOneWidget);
        expect(app.diagnostics.enabled, isFalse);
        await tester.tap(find.byKey(const ValueKey('diagnostics-toggle')));
        await tester.pumpAndSettle();
        expect(app.diagnostics.enabled, isTrue);
        await app.diagnostics.flush();
        expect(
          await File('${app.root.path}/diagnostics/diagnostic.jsonl').exists(),
          isTrue,
        );
        await tester.tap(find.byKey(const ValueKey('diagnostics-toggle')));
        await tester.pumpAndSettle();
        expect(app.diagnostics.enabled, isFalse);
        await capture('settings-diagnostics-mobile');
        await tester.pageBack();
        await tester.pumpAndSettle();
        await openSetting('关于风灵音乐');
        expect(
          find.byKey(const ValueKey('about-logo-easter-egg')),
          findsOneWidget,
        );
        await capture('about-mobile');
        final installed = await AppVersion.installed();
        expect(installed.build, greaterThan(0));
        await tester.scrollUntilVisible(find.text('$installed'), 250);
        await tester.pumpAndSettle();
        await waitFor(find.text('$installed'));
        await tester.scrollUntilVisible(find.text('开源许可证'), 150);
        await tester.pumpAndSettle();
        await tester.tap(find.text('开源许可证'));
        await tester.pumpAndSettle();
        expect(find.byType(LicensePage), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        final aboutLogo = find.byKey(const ValueKey('about-logo-easter-egg'));
        await tester.scrollUntilVisible(aboutLogo, -300);
        await tester.pumpAndSettle();
        for (var i = 0; i < 7; i++) {
          await tester.tap(aboutLogo);
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pump(const Duration(seconds: 7));
        expect(find.text('天琴座'), findsOneWidget);
        await capture('about-constellation-mobile');
        tester.view.physicalSize = const Size(800, 360);
        await tester.pump();
        await capture('about-constellation-landscape');
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('关闭星图'));
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(360, 800);
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(1200, 850);
        await tester.pumpAndSettle();
        await capture('settings-desktop');
        tester.view.physicalSize = const Size(320, 640);
        await tester.pumpAndSettle();
        await openSetting('播放器设置');
        await capture('settings-playback-small');
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(360, 800);
        await tester.pumpAndSettle();
        tester
            .state<ScrollableState>(find.byType(Scrollable).last)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        await tester.tap(find.text('音乐源管理'));
        await tester.pumpAndSettle();
        expect(find.text('同步全部'), findsOneWidget);
        expect(find.text('已连接的音乐源'), findsOneWidget);
        await tester.tap(find.text('添加音乐源'));
        await tester.pumpAndSettle();
        expect(find.byType(MusicSourceConnectionPage), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
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
