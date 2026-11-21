import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/ui/capsule_toggle.dart';
import 'package:sylphy_music/ui/design_system/miuix_adaptive.dart';

const _options = [
  CapsuleOption(value: 0, label: '歌曲', icon: Icons.music_note_outlined),
  CapsuleOption(value: 1, label: '专辑', icon: Icons.album_outlined),
];

void main() {
  testWidgets('Material 3 keeps ChoiceChip and original selection callback', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MiuixTheme(
            data: MiuixThemeData.light(),
            child: SylphyMiuixStyle(
              active: false,
              child: CapsuleToggle<int>(
                options: _options,
                selected: selected,
                onChanged: (value) => selected = value,
                keyPrefix: 'style-test',
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    expect(find.byType(MiuixPressable), findsNothing);
    await tester.tap(find.text('专辑'));
    expect(selected, 1);
  });

  testWidgets('Miuix uses native squircle and press feedback', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MiuixTheme(
            data: MiuixThemeData.light(),
            child: SylphyMiuixStyle(
              active: true,
              child: CapsuleToggle<int>(
                options: _options,
                selected: selected,
                onChanged: (value) => selected = value,
                keyPrefix: 'style-test',
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(MiuixPressable), findsNWidgets(2));
    expect(find.byKey(const ValueKey('style-test-0')), findsOneWidget);
    await tester.tap(find.text('专辑'));
    expect(selected, 1);
  });

  testWidgets('adaptive pressable runs the original callback only once', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MiuixTheme(
            data: MiuixThemeData.light(),
            child: SylphyMiuixStyle(
              active: true,
              child: SylphyAdaptivePressable(
                onTap: () => taps++,
                child: const SizedBox(
                  width: 120,
                  height: 52,
                  child: Text('打开'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    expect(taps, 1);
  });
}
