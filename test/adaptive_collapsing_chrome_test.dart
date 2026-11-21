import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/ui/design_system/adaptive_collapsing_chrome.dart';
import 'package:sylphy_music/ui/design_system/miuix_adaptive.dart';

void main() {
  test('the folding rule is shared by Material 3 and Miuix', () {
    expect(
      sylphyToolbarFoldDecision(
        folded: false,
        scrollOffset: 20,
        scrollDelta: 8,
      ),
      isNull,
    );
    expect(
      sylphyToolbarFoldDecision(
        folded: false,
        scrollOffset: 120,
        scrollDelta: 6,
      ),
      isTrue,
    );
    expect(
      sylphyToolbarFoldDecision(
        folded: true,
        scrollOffset: 125,
        scrollDelta: -6,
      ),
      isFalse,
    );
    expect(
      sylphyToolbarFoldDecision(folded: true, scrollOffset: 2, scrollDelta: 0),
      isFalse,
    );
  });

  for (final miuix in [false, true]) {
    Widget withStyle(Widget child) => miuix
        ? MiuixTheme(
            data: MiuixThemeData.light(),
            child: SylphyMiuixStyle(active: true, child: child),
          )
        : SylphyMiuixStyle(active: false, child: child);

    testWidgets(
      'folded More menu keeps its callback in ${miuix ? 'Miuix' : 'MD3'}',
      (tester) async {
        var invoked = false;
        await tester.pumpWidget(
          MaterialApp(
            home: withStyle(
              Scaffold(
                body: Center(
                  child: SylphyFoldedMoreMenu(
                    items: [
                      MenuItemButton(
                        onPressed: () => invoked = true,
                        child: const Text('新建歌单'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('sylphy-folded-more')));
        await tester.pumpAndSettle();
        expect(find.text('新建歌单'), findsOneWidget);
        await tester.tap(find.text('新建歌单'));
        await tester.pumpAndSettle();
        expect(invoked, isTrue);
      },
    );

    testWidgets('header gradient/action render in ${miuix ? 'Miuix' : 'MD3'}', (
      tester,
    ) async {
      var searches = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: withStyle(
            Scaffold(
              appBar: AppBar(
                flexibleSpace: const SylphyGradientHeader(),
                title: const Text('音乐库'),
                actions: [
                  SylphyHeaderAction(
                    icon: Icons.search_rounded,
                    tooltip: '搜索',
                    onPressed: () => searches++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.byType(SylphyGradientHeader), findsOneWidget);
      await tester.tap(find.byType(SylphyHeaderAction));
      expect(searches, 1);
    });
  }
}
