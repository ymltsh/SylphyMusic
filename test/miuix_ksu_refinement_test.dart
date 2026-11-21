import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/ui/design_system/miuix_adaptive.dart';
import 'package:sylphy_music/ui/miuix/miuix_dock_navigation.dart';

void main() {
  testWidgets(
    'Material mode keeps a Material card and unchanged search decoration',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  const SylphyAdaptiveCard(child: Text('原有分组')),
                  TextField(
                    decoration: SylphyMiuixStyle.searchDecoration(
                      context,
                      hintText: '搜索',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.byType(Card), findsOneWidget);
      expect(find.byType(MiuixCard), findsNothing);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.filled, isNot(true));
      expect(field.decoration?.border, InputBorder.none);
    },
  );

  testWidgets('Miuix cards and pill search use semantic Miuix surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MiuixTheme(
            data: MiuixThemeData.light(),
            child: SylphyMiuixStyle(
              active: true,
              child: Builder(
                builder: (context) => Column(
                  children: [
                    const SylphyAdaptiveCard(child: Text('原有分组')),
                    TextField(
                      decoration: SylphyMiuixStyle.searchDecoration(
                        context,
                        hintText: '搜索',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(MiuixCard), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.filled, isTrue);
    expect(field.decoration?.border, isA<OutlineInputBorder>());
    expect(field.decoration?.prefixIcon, isA<Icon>());
  });

  testWidgets('Miuix dock has KSU-inspired squircle surface and usable tabs', (
    tester,
  ) async {
    var selected = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MiuixTheme(
            data: MiuixThemeData.light(),
            child: MiuixDockNavigation(
              selectedIndex: 0,
              labels: const ['首页', '音乐库', '歌单', '我的'],
              icons: const [
                Icons.home,
                Icons.library_music,
                Icons.queue_music,
                Icons.person,
              ],
              onSelected: (index) => selected = index,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(MiuixNavigationBar), findsNothing);
    expect(find.byType(MiuixGlassNavigationBar), findsOneWidget);
    expect(find.byType(MiuixIcon), findsNWidgets(4));
    await tester.tap(find.text('音乐库'));
    expect(selected, 1);
  });
}
