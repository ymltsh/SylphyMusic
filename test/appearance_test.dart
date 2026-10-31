import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/appearance.dart';
import 'package:sylphy_music/data/app_db.dart';
import 'package:sylphy_music/ui/app_background.dart';
import 'package:sylphy_music/ui/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppDb db;
  late Appearance appearance;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sylphy-appearance-');
    db = AppDb(root);
    await db.open();
    appearance = Appearance(db);
    await appearance.initialize();
  });
  tearDown(() async {
    await appearance.shutdown();
    await db.close();
    await root.delete(recursive: true);
  });
  test(
    'default disc rotation is off and an explicit choice survives restart',
    () async {
      expect(appearance.discRotation, isFalse);
      await appearance.update(rotateDisc: true);
      final restored = Appearance(db);
      await restored.initialize();
      expect(restored.discRotation, isTrue);
      restored.dispose();
    },
  );
  test(
    'default accent is exactly #5094B2 and custom values survive reload',
    () async {
      expect(appearance.seedHex, '#5094B2');
      expect(
        sylphyTheme(appearance, Brightness.light).colorScheme.primary,
        Appearance.defaultSeed,
      );
      await appearance.update(
        color: const Color(0xffa45c7a),
        visibility: .35,
        theme: ThemeMode.dark,
      );
      final restored = Appearance(db);
      await restored.initialize();
      expect(restored.seedHex, '#A45C7A');
      expect(restored.mode, ThemeMode.dark);
      expect(restored.backgroundVisibility, .35);
      restored.dispose();
    },
  );
  test(
    'background is copied independently and invalid replacement preserves it',
    () async {
      final source = await File('test/fixtures/cover.png')
          .copy('${root.path}/original.png');
      await appearance.setBackground(source);
      final managed = appearance.backgroundFile!;
      expect(managed.path, isNot(source.path));
      await source.delete();
      expect(await managed.exists(), isTrue);
      final restored = Appearance(db);
      await restored.initialize();
      expect(restored.backgroundFile!.path, managed.path);
      restored.dispose();
      final invalid = await File('${root.path}/invalid.jpg')
          .writeAsString('not an image');
      await expectLater(appearance.setBackground(invalid), throwsA(anything));
      expect(appearance.backgroundFile!.path, managed.path);
      expect(await managed.exists(), isTrue);
      await appearance.clearBackground();
      expect(appearance.backgroundFile, isNull);
      expect(await managed.exists(), isFalse);
      expect(await invalid.exists(), isTrue);
    },
  );
  test(
    'normalization preserves aspect ratio and bounds the longest edge',
    () async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawColor(const Color(0xff5094b2), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(3200, 1600);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      final source = await File('${root.path}/wide.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      await appearance.setBackground(source);
      final codec = await ui.instantiateImageCodec(
        await appearance.backgroundFile!.readAsBytes(),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      expect(frame.image.width, 2048);
      expect(frame.image.height, 1024);
      frame.image.dispose();
      expect(await source.exists(), isTrue);
    },
  );
  test(
    'queued replacement followed by removal leaves no managed background',
    () async {
      final first = appearance.setBackground(File('test/fixtures/cover.png'));
      final second = appearance.setBackground(File('test/fixtures/cover.png'));
      final clear = appearance.clearBackground();
      await Future.wait([first, second, clear]);
      expect(appearance.backgroundFile, isNull);
      expect(await Directory('${root.path}/appearance').list().length, 0);
    },
  );
  test('lyric size, solid background and cover blur survive reload', () async {
    expect(appearance.mode, ThemeMode.system);
    expect(appearance.lyricFontSize, 24);
    expect(appearance.miniLyricFontSize, 20);
    expect(appearance.solidBackground, isTrue);
    expect(appearance.ambient, isFalse);
    await appearance.update(
      lyricFont: 28,
      miniLyricFont: 24,
      solid: false,
      background: true,
    );
    final restored = Appearance(db);
    await restored.initialize();
    expect(restored.lyricFontSize, 28);
    expect(restored.miniLyricFontSize, 24);
    expect(restored.solidBackground, isFalse);
    expect(restored.ambient, isTrue);
    restored.dispose();
  });
  test('choosing a background image turns off solid mode', () async {
    await appearance.update(solid: true);
    await appearance.setBackground(File('test/fixtures/cover.png'));
    expect(appearance.solidBackground, isFalse);
    final restored = Appearance(db);
    await restored.initialize();
    expect(restored.solidBackground, isFalse);
    restored.dispose();
  });
  testWidgets('solid background follows light and dark brightness', (
    tester,
  ) async {
    appearance.solidBackground = true;
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: sylphyTheme(appearance, brightness),
          home: AppBackground(
            appearance: appearance,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final box = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.byType(AppBackground),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(
        box.color,
        brightness == Brightness.dark ? const Color(0xff0f1417) : Colors.white,
      );
    }
    await tester.pumpWidget(const SizedBox());
  });
}
