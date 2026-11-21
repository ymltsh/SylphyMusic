import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/ui/design_system/miuix_adaptive.dart';
import 'package:sylphy_music/ui/miuix/miuix_dock_navigation.dart';

void main() {
  testWidgets(
    'indicator moves through intermediate positions without teleport',
    (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MiuixTheme(
            data: MiuixThemeData.light(),
            child: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                extendBody: true,
                body: const ColoredBox(
                  color: Color(0xfff0f0f0),
                  child: SizedBox.expand(),
                ),
                bottomNavigationBar: MiuixDockNavigation(
                  selectedIndex: selected,
                  labels: const ['首页', '音乐库', '歌单', '我的'],
                  icons: const [
                    Icons.home,
                    Icons.library_music,
                    Icons.queue_music,
                    Icons.person,
                  ],
                  onSelected: (value) => setState(() => selected = value),
                ),
              ),
            ),
          ),
        ),
      );
      final indicator = find.byKey(const ValueKey('miuix-selection-indicator'));
      expect(find.byType(BackdropFilter), findsOneWidget);
      final dock = find.byKey(const ValueKey('miuix-bottom-navigation'));
      expect(tester.getSize(dock).height, 58);
      final start = tester.getTopLeft(indicator).dx;
      await tester.tap(find.text('我的'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      final middle = tester.getTopLeft(indicator).dx;
      await tester.pumpAndSettle();
      final finish = tester.getTopLeft(indicator).dx;
      expect(selected, 3);
      expect(middle, greaterThan(start));
      expect(middle, lessThan(finish));
      expect(find.byType(MiuixNavigationBarItem), findsNothing);
    },
  );

  testWidgets('inactive tabs keep readable full-opacity theme foreground', (
    tester,
  ) async {
    final palette = MiuixThemeData.light();
    await tester.pumpWidget(
      MaterialApp(
        home: MiuixTheme(
          data: palette,
          child: Scaffold(
            bottomNavigationBar: MiuixDockNavigation(
              selectedIndex: 0,
              labels: const ['首页', '音乐库', '歌单', '我的'],
              icons: const [
                Icons.home,
                Icons.library_music,
                Icons.queue_music,
                Icons.person,
              ],
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    final inactive = tester.widget<Icon>(find.byIcon(Icons.library_music));
    expect(inactive.color, palette.colors.onSurface);
    expect(inactive.color!.a, 1);
  });

  testWidgets('Miuix outlined section does not insert Material Card', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MiuixTheme(
            data: MiuixThemeData.light(),
            child: const SylphyMiuixStyle(
              active: true,
              child: SylphyAdaptiveCard(
                materialOutlined: true,
                child: Text('收藏分组'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(Card), findsNothing);
    expect(find.byType(MiuixCard), findsOneWidget);
  });
}
