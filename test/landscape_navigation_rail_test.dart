import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/ui/landscape_navigation_rail.dart';

void main() {
  testWidgets('short landscape rail keeps global actions accessible', (
    tester,
  ) async {
    var selected = -1;
    var searches = 0;
    var settings = 0;
    const icons = [
      Icons.home,
      Icons.music_note,
      Icons.queue_music,
      Icons.person,
    ];
    final destinations = List.generate(
      icons.length,
      (i) => NavigationRailDestination(
        icon: Icon(icons[i]),
        label: Text('Page $i'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 210,
              child: LandscapeNavigationRail(
                selectedIndex: 0,
                destinations: destinations,
                onDestinationSelected: (value) => selected = value,
                onSearch: () => searches++,
                onSettings: () => settings++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.scrollable, isTrue);
    expect(rail.labelType, NavigationRailLabelType.none);
    expect(find.byTooltip('搜索'), findsOneWidget);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byTooltip('搜索')).dy,
      lessThan(tester.getTopLeft(find.byTooltip('设置')).dy),
    );
    await tester.tap(find.byTooltip('搜索'));
    await tester.tap(find.byTooltip('设置'));
    expect(searches, 1);
    expect(settings, 1);
    expect(selected, -1);
    expect(tester.takeException(), isNull);
  });
}
