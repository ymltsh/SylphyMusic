import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/ui/miuix/miuix_dock_navigation.dart';

void main() {
  testWidgets('Miuix dock dispatches the selected tab without owning state', (
    tester,
  ) async {
    var lastSelected = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: MiuixTheme(
          data: MiuixThemeData.light(),
          child: Scaffold(
            bottomNavigationBar: MiuixDockNavigation(
              selectedIndex: 0,
              labels: const ['首页', '音乐库', '歌单', '我的'],
              icons: const [
                Icons.home_outlined,
                Icons.library_music_outlined,
                Icons.queue_music_outlined,
                Icons.person_outline,
              ],
              onSelected: (value) => lastSelected = value,
            ),
            body: const SizedBox.expand(),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('miuix-bottom-navigation')),
      findsOneWidget,
    );
    await tester.tap(find.text('歌单'));
    expect(lastSelected, 2);
  });

  testWidgets('dock is compact and preserves one bottom gesture inset', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(bottom: 24),
            viewPadding: EdgeInsets.only(bottom: 24),
          ),
          child: MiuixTheme(
            data: MiuixThemeData.light(),
            child: Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: MiuixDockNavigation(
                selectedIndex: 3,
                labels: const ['首页', '音乐库', '歌单', '我的'],
                icons: const [
                  Icons.home_outlined,
                  Icons.library_music_outlined,
                  Icons.queue_music_outlined,
                  Icons.person_outline,
                ],
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final nav = find.byKey(const ValueKey('miuix-bottom-navigation'));
    expect(tester.getSize(nav).height, 64);
    final totalHeight = tester.getSize(find.byType(Scaffold)).height;
    final barBottom = tester.getBottomLeft(nav).dy;
    expect(totalHeight - barBottom, closeTo(29, 1));
  });
}
