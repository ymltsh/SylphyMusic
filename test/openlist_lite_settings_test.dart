import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/ui/openlist_lite_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('music.sylphy/openlist_lite');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('mode selection uses the group and ignores input while saving', (
    tester,
  ) async {
    final saved = Completer<String>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'mode') {
        calls.add((call.arguments as Map)['value'] as String);
        return saved.future;
      }
      return null;
    });
    await tester.pumpWidget(
      MaterialApp(home: OpenListLiteSettingsPage(setEnabled: (_) async {})),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      'smart',
    );
    await tester.tap(find.text('持续运行'));
    await tester.pumpAndSettle();
    expect(calls, ['continuous']);
    expect(
      tester
          .widgetList<RadioListTile<String>>(find.byType(RadioListTile<String>))
          .every((tile) => tile.enabled == false),
      true,
    );
    await tester.tap(find.text('智能运行（推荐）'));
    await tester.pump();
    expect(calls, ['continuous']);
    saved.complete('continuous');
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<RadioListTile<String>>(find.byType(RadioListTile<String>))
          .every((tile) => tile.enabled == true),
      true,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving during credential loading does not open a dialog', (
    tester,
  ) async {
    final loaded = Completer<String>();
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'adminPassword' ? loaded.future : null,
    );
    await tester.pumpWidget(
      MaterialApp(home: OpenListLiteSettingsPage(setEnabled: (_) async {})),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('查看初始管理员密码'));
    await tester.tap(find.text('查看初始管理员密码'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    loaded.complete('fixture');
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
