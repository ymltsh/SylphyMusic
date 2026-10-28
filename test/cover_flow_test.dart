import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/ui/cover_flow.dart';

void main() {
  testWidgets('shows the selected cover, activates it, and can swipe', (
    tester,
  ) async {
    var activated = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              height: 600,
              child: CoverFlowView(
                itemCount: 3,
                coverBuilder: (context, index, size) => SizedBox.square(
                  dimension: size,
                  child: ColoredBox(
                    color: [
                      Colors.deepPurple,
                      Colors.blue,
                      Colors.orange,
                    ][index],
                  ),
                ),
                titleBuilder: (index) => 'Album $index',
                subtitleBuilder: (index) => 'Artist $index',
                onActivate: (index) => activated = index,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Album 0'), findsOneWidget);
    final bounds = tester.getRect(find.byType(CoverFlowView));
    await tester.tapAt(bounds.center);
    await tester.pump();
    expect(activated, 0);

    await tester.timedDrag(
      find.byType(CoverFlowView),
      const Offset(-160, 0),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    expect(find.text('Album 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
