import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/ui/design_system/adaptive_collapsing_chrome.dart';
import 'package:sylphy_music/ui/design_system/miuix_adaptive.dart';

void main() {
  test(
    'the scroll tracker ignores micro reversals and respects hysteresis',
    () {
      final tracker = SylphyToolbarScrollTracker();
      for (var i = 0; i < 5; i++) {
        expect(
          tracker.observe(
            folded: false,
            scrollOffset: 70 + i * 2.0,
            scrollDelta: 3,
          ),
          isNull,
        );
      }
      expect(
        tracker.observe(folded: false, scrollOffset: 100, scrollDelta: 12),
        isTrue,
      );
      expect(
        tracker.observe(folded: true, scrollOffset: 99, scrollDelta: -5),
        isNull,
      );
      expect(
        tracker.observe(folded: true, scrollOffset: 110, scrollDelta: 8),
        isNull,
      );
      for (var i = 0; i < 3; i++) {
        expect(
          tracker.observe(
            folded: true,
            scrollOffset: 105 - i * 5.0,
            scrollDelta: -7,
          ),
          isNull,
        );
      }
      expect(
        tracker.observe(folded: true, scrollOffset: 81, scrollDelta: -9),
        isFalse,
      ); // expand on a sustained reverse gesture
      expect(
        tracker.observe(folded: true, scrollOffset: 5, scrollDelta: 0),
        isFalse,
      );
    },
  );

  for (final miuix in [false, true]) {
    testWidgets('pill and circular More share an AppBar row: '
        "${miuix ? 'Miuix' : 'MD3'}", (tester) async {
      var searches = 0;
      var settings = 0;
      var folded = false;
      late StateSetter update;

      await tester.pumpWidget(
        MaterialApp(
          home: MiuixTheme(
            data: MiuixThemeData.light(),
            child: SylphyMiuixStyle(
              active: miuix,
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return Scaffold(
                    appBar: AppBar(
                      title: const Text('音乐库'),
                      actions: [
                        SylphyHeaderActionCapsule(
                          onSearch: () => searches++,
                          onSettings: () => settings++,
                        ),
                        SylphyFoldedHeaderSlot(
                          visible: folded,
                          child: SylphyFoldedMoreMenu(
                            items: [
                              MenuItemButton(
                                onPressed: () {},
                                child: const Text('排序'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('sylphy-header-action-capsule')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('搜索'));
      await tester.tap(find.byTooltip('设置'));
      expect(searches, 1);
      expect(settings, 1);
      expect(find.byKey(const ValueKey('sylphy-folded-more')), findsNothing);

      update(() => folded = true);
      await tester.pump();
      await tester.pumpAndSettle();
      final capsule = find.byKey(
        const ValueKey('sylphy-header-action-capsule'),
      );
      final more = find.byKey(const ValueKey('sylphy-folded-more'));
      expect(more, findsOneWidget);
      expect(
        (tester.getCenter(capsule).dy - tester.getCenter(more).dy).abs(),
        lessThan(2),
      );
      expect(
        tester.getTopLeft(more).dx,
        greaterThan(tester.getTopRight(capsule).dx),
      );
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('排序'), findsOneWidget);
    });
  }

  testWidgets('collapsed toolbar animates its height, not just opacity', (
    tester,
  ) async {
    var collapsed = false;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(
              body: Column(
                children: [
                  SylphyAnimatedToolbar(
                    collapsed: collapsed,
                    expanded: const SizedBox(height: 120, child: Text('展开')),
                    compact: const SizedBox(height: 44, child: Text('折叠')),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    final panel = find.byType(SylphyAnimatedToolbar);
    final before = tester.getSize(panel).height;
    update(() => collapsed = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    final middle = tester.getSize(panel).height;
    await tester.pumpAndSettle();
    final after = tester.getSize(panel).height;
    expect(before, greaterThan(middle));
    expect(middle, greaterThan(after));
  });
}
