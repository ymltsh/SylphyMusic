import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/player_layout.dart';
import 'package:sylphy_music/core/app_controller.dart';
import 'package:sylphy_music/ui/player_layout/metadata_links.dart';
import 'package:sylphy_music/ui/player_layout/metadata_text.dart';

const longTitle = '14. Contemplation in Snow 白皑中的冥想 · 特别收录版本';
const longArtist =
    'HOYO-MiX · 原神-闪耀的群星 The Stellar Moments · Original Soundtrack';

Widget view({
  required String text,
  required Size size,
  double fontSize = 22,
  double scale = 1,
  int maxLines = 2,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: Center(
        child: SizedBox.fromSize(
          size: size,
          child: PlayerMetadataText(
            text: text,
            style: TextStyle(fontSize: fontSize),
            alignment: Alignment.center,
            textAlign: TextAlign.center,
            maxLines: maxLines,
          ),
        ),
      ),
    ),
  ),
);

class _PreviewApp extends Fake implements SylphyApp {}

void main() {
  testWidgets('metadata links fit short frames and stay inactive in preview', (
    tester,
  ) async {
    for (final size in [const Size(240, 32), const Size(90, 12)]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.fromSize(
                size: size,
                child: PlayerMetadataLinks(
                  app: _PreviewApp(),
                  track: null,
                  preview: true,
                  style: const TextStyle(fontSize: 22),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      );
      for (final key in ['player-open-artist', 'player-open-album']) {
        final link = find.byKey(ValueKey(key));
        expect(tester.widget<GestureDetector>(link).onTap, isNull);
        await tester.tap(link);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('title uses only complete lines and ellipsizes the remainder', (
    tester,
  ) async {
    for (final height in [32.0, 64.0]) {
      await tester.pumpWidget(view(text: longTitle, size: Size(240, height)));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(longTitle),
      );
      expect(paragraph.maxLines, height == 32 ? 1 : 2);
      expect(paragraph.didExceedMaxLines, isTrue);
      expect(paragraph.size.height, lessThanOrEqualTo(height));
      expect(tester.takeException(), isNull);
    }
    await tester.longPress(find.byType(PlayerMetadataText));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(longTitle), findsNWidgets(2));
  });

  testWidgets('metadata stays inside phone, desktop and short custom frames', (
    tester,
  ) async {
    for (final canvas in [
      const Size(320, 500),
      const Size(360, 680),
      const Size(1200, 750),
    ]) {
      for (final scale in [1.0, 2.0]) {
        final layout = playerTemplate();
        for (final part in [PlayerPart.title, PlayerPart.artist]) {
          final element = layout.elements.firstWhere((e) => e.type == part);
          final bounds = layout.bounds(element, canvas);
          for (final height in [bounds.height, 12.0]) {
            final text = part == PlayerPart.title ? longTitle : longArtist;
            await tester.pumpWidget(
              view(
                text: text,
                size: Size(bounds.width, height),
                fontSize: element.fontSize,
                scale: scale,
                maxLines: part == PlayerPart.title ? 2 : 1,
              ),
            );
            final frame = tester.getRect(find.byType(PlayerMetadataText));
            final paragraph = tester.renderObject<RenderParagraph>(
              find.text(text),
            );
            final topLeft = paragraph.localToGlobal(Offset.zero);
            final bottomRight = paragraph.localToGlobal(
              paragraph.size.bottomRight(Offset.zero),
            );
            expect(topLeft.dx, greaterThanOrEqualTo(frame.left - .01));
            expect(topLeft.dy, greaterThanOrEqualTo(frame.top - .01));
            expect(bottomRight.dx, lessThanOrEqualTo(frame.right + .01));
            expect(bottomRight.dy, lessThanOrEqualTo(frame.bottom + .01));
            if (part == PlayerPart.artist) expect(paragraph.maxLines, 1);
            expect(tester.takeException(), isNull);
          }
        }
      }
    }
  });
}
