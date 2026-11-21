import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/ui/design_system/miuix_adaptive.dart';
import 'package:sylphy_music/ui/miuix/miuix_dock_navigation.dart';

void main() {
  testWidgets(
    'native glass dock responds to tab selection with rounded icons',
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
      final dock = find.byType(MiuixGlassNavigationBar);
      expect(dock, findsOneWidget);
      expect(tester.getSize(dock).height, 56);
      final glass = tester.widget<MiuixGlassNavigationBar>(dock);
      expect(glass.items, hasLength(4));
      expect(glass.indicatorColor, isNotNull);
      expect(find.byType(MiuixIcon), findsNWidgets(4));
      expect(
        tester.widget<MiuixIcon>(find.byType(MiuixIcon).first).icon,
        Icons.cottage_rounded,
      );
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(selected, 3);
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
    final glass = tester.widget<MiuixGlassNavigationBar>(
      find.byType(MiuixGlassNavigationBar),
    );
    expect(glass.unselectedColor, palette.colors.onSurface);
    expect(glass.unselectedColor!.a, 1);
    expect(glass.selectedColor, palette.colors.primary);
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
