import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/ui/library_browser.dart';
import 'package:sylphy_music/ui/miuix/miuix_song_row_style.dart';

void main() {
  test('ordinary Miuix music rows have no individual card background', () {
    final colors = MiuixThemeData.light().colors;
    expect(
      MiuixSongRowStyle.highlight(
        colors,
        current: false,
        selectedInBatch: false,
      ),
      Colors.transparent,
    );
    expect(MiuixSongRowStyle.coverRadius, 12);
  });

  test('batch selection visually outweighs the current-track tint', () {
    final colors = MiuixThemeData.dark().colors;
    final current = MiuixSongRowStyle.highlight(
      colors,
      current: true,
      selectedInBatch: false,
    );
    final selected = MiuixSongRowStyle.highlight(
      colors,
      current: true,
      selectedInBatch: true,
    );
    expect(current.a, lessThan(selected.a));
  });

  test('the last song can scroll beyond the floating dock', () {
    expect(
      libraryListBottomPadding(viewportWidth: 393, overlayPadding: 86),
      182,
    );
    expect(
      libraryListBottomPadding(
        viewportWidth: 900,
        basePadding: 12,
        overlayPadding: 0,
      ),
      12,
    );
  });

  testWidgets('song popup retains actions under Miuix visual styling', (
    tester,
  ) async {
    String? action;
    await tester.pumpWidget(
      MaterialApp(
        home: MiuixTheme(
          data: MiuixThemeData.light(),
          child: Scaffold(
            body: MiuixSongMenuTheme(
              child: PopupMenuButton<String>(
                tooltip: '歌曲操作',
                onSelected: (value) => action = value,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'favorite', child: Text('收藏')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final menu = tester.element(find.byType(PopupMenuButton<String>));
    expect(PopupMenuTheme.of(menu).shape, isA<MiuixSquircleBorder>());
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(action, 'favorite');
  });
}
