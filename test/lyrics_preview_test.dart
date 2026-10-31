import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/player_layout.dart';
import 'package:sylphy_music/ui/lyrics_view.dart';
import 'package:sylphy_music/ui/player_layout/layout_renderer.dart';

void main() {
  Widget view(
    String text,
    Duration position, {
    double height = 108,
    double lineHeight = 1.5,
  }) => MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          height: height,
          child: LyricsPreview(
            text: text,
            position: position,
            fontSize: 24,
            lineHeight: lineHeight,
            highlightColor: Colors.orange,
          ),
        ),
      ),
    ),
  );
  testWidgets('default lyric color follows the system, not the accent', (
    tester,
  ) async {
    const lyrics = PlayerElement(
      id: 'lyrics',
      type: PlayerPart.lyrics,
      frame: Rect.fromLTWH(0, 0, .5, .5),
    );

    Future<Color?> resolve(Brightness brightness, PlayerElement element) async {
      Color? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: MediaQuery(
            data: MediaQueryData(platformBrightness: brightness),
            child: Builder(
              builder: (context) {
                result = PlayerWidgetRegistry.lyricHighlightColor(
                  context,
                  element,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return result;
    }

    expect(await resolve(Brightness.light, lyrics), Colors.black);
    expect(await resolve(Brightness.dark, lyrics), Colors.white);
    expect(
      await resolve(
        Brightness.dark,
        lyrics.copyWith(lyricFollowSystemColor: false),
      ),
      isNull,
    );
    expect(
      await resolve(Brightness.dark, lyrics.copyWith(color: 0xff82c7e4)),
      const Color(0xff82c7e4),
    );
  });

  testWidgets(
    'line height changes actual lyric spacing and visible neighbours',
    (tester) async {
      const lrc = '[00:00]第一句\n[00:01]第二句\n[00:02]第三句\n[00:03]第四句\n[00:04]第五句';
      await tester.pumpWidget(
        view(lrc, const Duration(seconds: 2), height: 300, lineHeight: 1),
      );
      await tester.pumpAndSettle();
      final compact =
          tester.getCenter(find.text('第四句')).dy -
          tester.getCenter(find.text('第三句')).dy;
      await tester.pumpWidget(
        view(lrc, const Duration(seconds: 2), height: 300, lineHeight: 2.5),
      );
      await tester.pumpAndSettle();
      final loose =
          tester.getCenter(find.text('第四句')).dy -
          tester.getCenter(find.text('第三句')).dy;
      expect(loose, greaterThan(compact));
      expect(loose, closeTo(compact * 2.5, .1));
      await tester.pumpWidget(
        view(lrc, const Duration(seconds: 2), height: 108, lineHeight: 2.5),
      );
      await tester.pumpAndSettle();
      expect(find.text('第三句'), findsOneWidget);
      expect(find.byType(Text), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'small previews show at most three lines around the active lyric',
    (tester) async {
      const lrc =
          '[00:00]第一句\n[00:01]第二句\n[00:02]第三句\n'
          '[00:03]第四句\n[00:04]第五句';
      await tester.pumpWidget(view(lrc, const Duration(seconds: 3)));
      expect(find.byType(Text), findsNWidgets(3));
      expect(find.text('第三句'), findsOneWidget);
      expect(find.text('第四句'), findsOneWidget);
      expect(find.text('第五句'), findsOneWidget);
      expect(
        DefaultTextStyle.of(tester.element(find.text('第四句'))).style.color,
        Colors.orange,
      );
      await tester.pumpWidget(
        view(lrc, const Duration(seconds: 3), height: 72),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Text), findsNWidgets(2));
      expect(find.text('第四句'), findsOneWidget);
      expect(find.text('第五句'), findsOneWidget);
    },
  );
  testWidgets('long current sentences wrap into two complete lines', (
    tester,
  ) async {
    const sentence = '这是一句比较长的歌词，用来检查换行后完整展示';
    await tester.pumpWidget(
      view(
        '[00:00]上一句\n[00:01]$sentence\n[00:02]下一句',
        const Duration(seconds: 1),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(find.text(sentence));
    expect(paragraph.maxLines, 2);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.size.height, greaterThan(36));
    expect(paragraph.size.height, lessThanOrEqualTo(72));
    expect(
      DefaultTextStyle.of(tester.element(find.text(sentence))).style.color,
      Colors.orange,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'short scaled previews keep the current wrapped sentence in bounds',
    (tester) async {
      const sentence =
          'Long lyrics should wrap over two lines without cropping';
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 240,
                  height: 60,
                  child: LyricsPreview(
                    text: '[00:00]Before\n[00:01]$sentence\n[00:02]After',
                    position: Duration(seconds: 1),
                    fontSize: 24,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text(sentence), findsOneWidget);
      expect(find.text('Before'), findsNothing);
      expect(find.text('After'), findsNothing);
      final frame = tester.getRect(find.byType(LyricsPreview));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(sentence),
      );
      expect(
        paragraph.localToGlobal(Offset.zero).dy,
        greaterThanOrEqualTo(frame.top - .01),
      );
      expect(
        paragraph.localToGlobal(paragraph.size.bottomRight(Offset.zero)).dy,
        lessThanOrEqualTo(frame.bottom + .01),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('plain lyrics also remain bounded to three lines', (
    tester,
  ) async {
    await tester.pumpWidget(view('第一行\n第二行\n第三行\n第四行', Duration.zero));
    expect(find.byType(Text), findsNWidgets(3));
    expect(find.text('第一行'), findsOneWidget);
    expect(find.text('第三行'), findsOneWidget);
    expect(find.text('第四行'), findsNothing);
  });
  testWidgets('larger previews use up to five lines', (tester) async {
    const lrc =
        '[00:00]第一句\n[00:01]第二句\n[00:02]第三句\n[00:03]第四句\n'
        '[00:04]第五句\n[00:05]第六句';
    await tester.pumpWidget(view(lrc, const Duration(seconds: 2), height: 180));
    expect(find.byType(Text), findsNWidgets(5));
    expect(find.text('第一句'), findsOneWidget);
    expect(find.text('第五句'), findsOneWidget);
    expect(find.text('第六句'), findsNothing);
  });
  testWidgets(
    'bilingual preview keeps the primary line instead of ellipsizing',
    (tester) async {
      const lrc =
          '[00:00]风穿过森林\n[00:00]The wind through the trees\n'
          '[00:01]让旋律轻轻停留\n[00:01]Let the melody linger';
      await tester.pumpWidget(view(lrc, const Duration(seconds: 1)));
      expect(find.text('风穿过森林'), findsOneWidget);
      expect(find.text('The wind through the trees'), findsNothing);
      expect(find.textContaining('·'), findsNothing);
      expect(find.text('让旋律轻轻停留'), findsOneWidget);
    },
  );
}
