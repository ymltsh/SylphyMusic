import 'dart:ui' show BlendMode;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/app_controller.dart';
import 'package:sylphy_music/core/player_layout.dart';
import 'package:sylphy_music/ui/player_cover.dart';

// Artwork is absent in this widget test, so the app is never accessed.
class _UnusedApp implements SylphyApp {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('No artwork is loaded in this test');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('four-side feather applies both axis masks', (tester) async {
    final app = _UnusedApp();
    Widget cover(CoverFadeDirection direction) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: PlayerCover(
            app: app,
            track: null,
            size: 240,
            height: 160,
            style: PlayerCoverStyle.immersive,
            fadeStart: .6,
            fadeDirection: direction,
          ),
        ),
      ),
    );

    await tester.pumpWidget(cover(CoverFadeDirection.all));
    expect(tester.getSize(find.byType(PlayerCover)), const Size(240, 160));
    final allMasks = tester.widgetList<ShaderMask>(find.byType(ShaderMask));
    expect(allMasks, hasLength(2));
    expect(allMasks.every((mask) => mask.blendMode == BlendMode.dstIn), isTrue);

    for (final direction in [
      CoverFadeDirection.right,
      CoverFadeDirection.left,
      CoverFadeDirection.top,
      CoverFadeDirection.bottom,
    ]) {
      await tester.pumpWidget(cover(direction));
      expect(find.byType(ShaderMask), findsOneWidget);
    }
  });
}
