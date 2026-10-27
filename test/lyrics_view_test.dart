import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/ui/lyrics_view.dart';

void main() {
  final source = List.generate(
    40,
    (i) =>
        '[00:${i.toString().padLeft(2, '0')}.00]第 $i 行 ${i == 20 ? '很长的歌词需要完整显示而且不能截断' * 8 : '测试歌词'}',
  ).join('\n');

  Widget view(
    String text,
    Duration position, {
    ValueChanged<Duration>? onSeek,
    double width = 360,
    double height = 480,
    double scale = 1,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: height,
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: LyricsView(text: text, position: position, onSeek: onSeek),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'variable height lyrics retain reading focus after seek, resize and large text',
    (tester) async {
      await tester.pumpWidget(view(source, const Duration(seconds: 20)));
      await tester.pumpAndSettle();
      final line = find.textContaining('第 20 行');
      expect(line, findsOneWidget);
      expect(tester.widget<Text>(line).maxLines, isNull);
      expect(
        tester.getCenter(line).dy,
        closeTo(
          tester.getTopLeft(find.byKey(const ValueKey('timed-lyrics'))).dy +
              tester
                      .getSize(find.byKey(const ValueKey('timed-lyrics')))
                      .height *
                  .43,
          2,
        ),
      );
      await tester.pumpWidget(
        view(
          source,
          const Duration(seconds: 20),
          width: 300,
          height: 360,
          scale: 1.5,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(line).dy,
        closeTo(
          tester.getTopLeft(find.byKey(const ValueKey('timed-lyrics'))).dy +
              tester
                      .getSize(find.byKey(const ValueKey('timed-lyrics')))
                      .height *
                  .43,
          2,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual browsing stays put across progress and return resumes following',
    (tester) async {
      await tester.pumpWidget(view(source, const Duration(seconds: 10)));
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('timed-lyrics'));
      await tester.drag(list, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(find.text('回到当前'), findsOneWidget);
      final state = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)),
      );
      final before = state.position.pixels;
      await tester.pumpWidget(view(source, const Duration(seconds: 12)));
      await tester.pumpAndSettle();
      expect(state.position.pixels, before);
      await tester.tap(find.text('回到当前'));
      await tester.pumpAndSettle();
      expect(find.text('回到当前'), findsNothing);
      expect(
        tester.getCenter(find.textContaining('第 12 行')).dy,
        closeTo(
          tester.getTopLeft(list).dy + tester.getSize(list).height * .43,
          2,
        ),
      );
    },
  );

  testWidgets('translation timestamps share a row and tapping seeks', (
    tester,
  ) async {
    Duration? seek;
    await tester.pumpWidget(
      view(
        '[00:01]Original\n[00:01]译文\n[00:05]\n[00:08]Next',
        const Duration(seconds: 1),
        onSeek: (value) => seek = value,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Original\n译文'), findsOneWidget);
    final grouped = tester.widget<Text>(find.text('Original\n译文'));
    final spans = (grouped.textSpan! as TextSpan).children!;
    expect(spans.last.style!.fontSize, lessThan(22));
    expect(spans.last.style!.fontWeight, FontWeight.w400);
    await tester.tap(find.text('Original\n译文'));
    expect(seek, const Duration(seconds: 1));
    await tester.pumpWidget(view('没有时间轴的完整文本\n第二段', Duration.zero));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('文本歌词 · 暂无时间轴'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
