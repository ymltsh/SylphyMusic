import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/player_layout.dart';
import 'package:sylphy_music/core/player_layout_store.dart';
import 'package:sylphy_music/data/app_db.dart';
import 'package:sylphy_music/ui/player_layout/layout_editing.dart';

Map<String, Object?> legacyLayout({
  double topFraction = .48,
  double middleFraction = .2,
}) => {
  'version': 1,
  'id': 'legacy',
  'name': '旧布局',
  'topFraction': topFraction,
  'middleFraction': middleFraction,
  'background': 'album',
  'backgroundOpacity': .65,
  'elements': [
    {
      'id': 'cover',
      'type': 'cover',
      'region': 'top',
      'frame': {'x': .1, 'y': .1, 'width': .8, 'height': .8},
      'props': {
        'circle': true,
        'rotate': true,
        'radius': 28,
        'fontSize': 22,
        'opacity': 1,
        'align': 'center',
      },
    },
    {
      'id': 'title',
      'type': 'title',
      'region': 'middle',
      'frame': {'x': .06, 'y': 0, 'width': .88, 'height': .48},
      'props': {'fontSize': 22, 'opacity': 1, 'align': 'center'},
    },
    {
      'id': 'lyrics',
      'type': 'lyrics',
      'region': 'middle',
      'frame': {'x': .02, 'y': .02, 'width': .96, 'height': .96},
      'props': {'fontSize': 24, 'opacity': 1, 'align': 'center'},
    },
    {
      'id': 'progress',
      'type': 'progress',
      'region': 'bottom',
      'frame': {'x': .08, 'y': .02, 'width': .84, 'height': .4},
      'props': {'fontSize': 22, 'opacity': 1, 'align': 'center'},
    },
    {
      'id': 'controls',
      'type': 'controls',
      'region': 'bottom',
      'frame': {'x': .08, 'y': .5, 'width': .84, 'height': .44},
      'props': {'playHeight': 80, 'controlSpacing': 20, 'align': 'center'},
    },
    {
      'id': 'queue',
      'type': 'queue',
      'region': 'bottom',
      'frame': {'x': .4, 'y': .8, 'width': .2, 'height': .2},
      'props': {'align': 'center'},
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('quick actions stay above progress in phone and desktop templates', () {
    for (final size in [
      const Size(320, 640),
      const Size(360, 800),
      const Size(1200, 850),
    ]) {
      for (final lyrics in [false, true]) {
        final layout = playerTemplate(lyrics: lyrics);
        final progress = layout.bounds(
          layout.elements.firstWhere((e) => e.type == PlayerPart.progress),
          size,
        );
        final actions = layout.actionBounds(size);
        expect(actions.bottom, lessThanOrEqualTo(progress.top));
        expect(actions.left, greaterThanOrEqualTo(0));
        expect(actions.right, lessThanOrEqualTo(size.width));
        expect(actions.height, 48);
      }
      final empty = playerTemplate().copyWith(elements: []);
      expect(empty.actionBounds(size).bottom, lessThanOrEqualTo(size.height));
    }
  });
  test('old custom lyrics frames leave room for the action strip', () {
    final layout = playerTemplate();
    final custom = layout.copyWith(
      elements: [
        for (final e in layout.elements)
          if (e.type == PlayerPart.lyrics)
            e.copyWith(frame: const Rect.fromLTWH(.08, .575, .84, .19))
          else
            e,
      ],
    );
    const size = Size(360, 800);
    final lyrics = custom.elements.firstWhere(
      (e) => e.type == PlayerPart.lyrics,
    );
    expect(
      custom.bounds(lyrics, size).bottom,
      lessThan(custom.actionBounds(size).top),
    );
  });
  test('v2 templates round-trip and controls retain their props', () {
    final base = playerTemplate();
    final custom = base.copyWith(
      elements: [
        for (final e in base.elements)
          if (e.type == PlayerPart.controls)
            e.copyWith(
              radius: 8,
              playWidth: 88,
              playHeight: 80,
              controlSpacing: 20,
            )
          else
            e,
      ],
    );
    final restored = PlayerLayout.decode(custom.encode());
    expect(restored.encode(), custom.encode());
    final controls = restored.elements.firstWhere(
      (e) => e.type == PlayerPart.controls,
    );
    expect(controls.radius, 8);
    expect(controls.playWidth, 88);
    expect(controls.playHeight, 80);
    expect(controls.controlSpacing, 20);
    expect(restored.elements.any((e) => e.type == PlayerPart.lyrics), isTrue);
    expect(
      PlayerLayout.fromJson(jsonDecode(base.encode())).toJson()['version'],
      2,
    );
  });

  test('v1 region layouts migrate to one full canvas', () {
    final migrated = PlayerLayout.fromJson(legacyLayout());
    expect(migrated.encode(), contains('"version": 2'));
    expect(migrated.elements.length, 5);
    expect(migrated.elements.where((e) => e.type == PlayerPart.queue), isEmpty);
    for (final e in migrated.elements) {
      final frame = e.frame;
      expect(frame.left, greaterThanOrEqualTo(0));
      expect(frame.top, greaterThanOrEqualTo(0));
      expect(frame.right, lessThanOrEqualTo(1.000001));
      expect(frame.bottom, lessThanOrEqualTo(1.000001));
      expect(e.wideFrame, isNotNull);
    }
    final controls = migrated.elements.firstWhere(
      (e) => e.type == PlayerPart.controls,
    );
    expect(controls.playHeight, 80);
    expect(controls.controlSpacing, 20);
    // Old per-widget circle/rotate flags no longer live on layout elements.
    expect(migrated.toJson()['elements'].toString(), isNot(contains('circle')));
    expect(migrated.toJson()['elements'].toString(), isNot(contains('rotate')));
  });

  test('legacy defaults and missing props remain readable', () {
    final json = legacyLayout();
    final raw = (json['elements'] as List).cast<Map<String, Object?>>();
    for (final e in raw) {
      (e['props'] as Map).remove('playHeight');
      (e['props'] as Map).remove('controlSpacing');
    }
    final controls = PlayerLayout.fromJson(json).elements
        .firstWhere((e) => e.type == PlayerPart.controls);
    expect(controls.playHeight, 64);
    expect(controls.controlSpacing, 12);
  });

  test('legacy invalid region fractions are rejected', () {
    expect(
      () => PlayerLayout.fromJson(legacyLayout(topFraction: .7)),
      throwsFormatException,
    );
  });

  test('full canvas bounds stay inside portrait and wide screens', () {
    for (final lyrics in [false, true]) {
      final layout = playerTemplate(lyrics: lyrics);
      expect(PlayerLayout.decode(layout.encode()).encode(), layout.encode());
      for (final size in [const Size(360, 640), const Size(1200, 800)]) {
        for (final e in layout.elements) {
          final bounds = layout.bounds(e, size);
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.top, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(size.width + .001));
          expect(bounds.bottom, lessThanOrEqualTo(size.height + .001));
          if (e.type == PlayerPart.cover) {
            expect(bounds.width, closeTo(bounds.height, .001));
          }
        }
      }
    }
  });

  test('a wide frame is optional and independent of portrait coordinates', () {
    final layout = playerTemplate();
    const portrait = Size(360, 640);
    const wide = Size(1200, 800);
    final cover = layout.elements.first;
    final portraitBounds = layout.bounds(cover, portrait);
    final wideBounds = layout.bounds(cover, wide);
    expect(portraitBounds, isNot(wideBounds));
    final edited = cover.copyWith(
      wideFrame: const Rect.fromLTWH(.2, .1, .6, .6),
    );
    final restored = PlayerLayout.decode(
      layout.copyWith(elements: [edited, ...layout.elements.skip(1)]).encode(),
    );
    expect(restored.elements.first.wideFrame, edited.wideFrame);
    expect(restored.bounds(restored.elements.first, portrait), portraitBounds);
    expect(restored.bounds(restored.elements.first, wide), isNot(wideBounds));
  });

  test(
    'malformed v2 files, future versions and duplicate components are rejected',
    () {
      final layout = playerTemplate();
      for (final mutation in <void Function(Map<String, dynamic>)>[
        (j) => j['version'] = 999,
        (j) => j['elements'][0]['wideFrame'] = {
          'x': .8,
          'y': 0,
          'width': .5,
          'height': .5,
        },
        (j) => j['elements'][0]['type'] = 'script',
        (j) => j['elements'][0]['frame']['width'] = 2,
        (j) => j['elements'][0]['props']['fontSize'] = -1,
        (j) => j['elements'][0]['props']['playHeight'] = 200,
        (j) => j['elements'][0]['props']['controlSpacing'] = -1,
        (j) => j['elements'].add(j['elements'][0]),
        (j) => j['elements'][0]['props']['opacity'] = '1',
      ]) {
        final json = jsonDecode(layout.encode()) as Map<String, dynamic>;
        mutation(json);
        expect(
          () => PlayerLayout.decode(jsonEncode(json)),
          throwsFormatException,
        );
      }
      expect(
        () => PlayerLayout.decode(' ' * (128 * 1024 + 1)),
        throwsFormatException,
      );
    },
  );

  test(
    'drag transaction has one undo step, redo and locked removal protection',
    () {
      final draft = PlayerLayoutDraft(playerTemplate());
      final before = draft.value.encode();
      final cover = draft.value.elements.first;
      draft.select(cover.id);
      draft.begin();
      draft.update(cover.copyWith(frame: const Rect.fromLTWH(.1, .1, .7, .8)));
      draft.update(cover.copyWith(frame: const Rect.fromLTWH(.2, .1, .7, .8)));
      draft.commit();
      final moved = draft.value.encode();
      expect(draft.dirty, isTrue);
      draft.undo();
      expect(draft.value.encode(), before);
      expect(draft.canUndo, isFalse);
      draft.redo();
      expect(draft.value.encode(), moved);
      draft.update(draft.selected!.copyWith(locked: true));
      final count = draft.value.elements.length;
      draft.remove();
      expect(draft.value.elements.length, count);
      draft.dispose();
    },
  );

  test('snaps to 3x3 and 4x4 grid lines and stays inside the canvas', () {
    final nine = PlayerSnapEngine.constrain(
      const Rect.fromLTWH(119, 50, 40, 40),
      const Size(340, 300),
      divisions: 3,
    );
    expect(nine.frame.left, closeTo(340 / 3, .001));
    expect(nine.vertical, contains(340 / 3));
    final sixteen = PlayerSnapEngine.constrain(
      const Rect.fromLTWH(80, 70, 40, 40),
      const Size(320, 320),
      divisions: 4,
    );
    expect(sixteen.frame.left, closeTo(80, .001));
    final resized = PlayerSnapEngine.constrain(
      const Rect.fromLTWH(100, 80, 200, 200),
      const Size(320, 320),
      divisions: 4,
      resize: true,
    );
    expect(resized.frame.right, lessThanOrEqualTo(320));
    expect(resized.frame.bottom, lessThanOrEqualTo(320));
    final square = PlayerSnapEngine.constrain(
      const Rect.fromLTWH(30, 30, 77, 77),
      const Size(320, 400),
      divisions: 4,
      square: true,
      resize: true,
    );
    expect(square.frame.width, closeTo(square.frame.height, .001));
    final off = PlayerSnapEngine.constrain(
      const Rect.fromLTWH(13, 17, 50, 40),
      const Size(340, 300),
      divisions: 3,
      enabled: false,
    );
    expect(off.frame.left, 13);
    expect(off.vertical, isEmpty);
  });

  group('layout persistence', () {
    late Directory root;
    late AppDb db;
    late PlayerLayoutStore store;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('sylphy-layout-');
      db = AppDb(root);
      await db.open();
      store = PlayerLayoutStore(db);
      await store.initialize();
    });
    tearDown(() async {
      await store.shutdown();
      await db.close();
      await root.delete(recursive: true);
    });
    test('save, select default and restart retain templates', () async {
      await store.save(playerTemplate(), asNew: true);
      final id = store.active!.id;
      await store.save(playerTemplate(lyrics: true), asNew: true);
      expect(store.templates.length, 2);
      await store.select(id);
      final restored = PlayerLayoutStore(db);
      await restored.initialize();
      expect(restored.active!.id, id);
      await restored.select(null);
      expect(restored.active, isNull);
      expect(restored.templates.length, 2);
      await restored.shutdown();
    });
    test(
      'invalid import/save preserves current layout and queue recovers',
      () async {
        await store.save(playerTemplate());
        final before = store.active!.encode();
        final invalid = playerTemplate().copyWith(
          elements: [
            playerTemplate().elements.first.copyWith(
              frame: const Rect.fromLTWH(.9, 0, .3, .1),
            ),
            ...playerTemplate().elements.skip(1),
          ],
        );
        await expectLater(store.save(invalid), throwsFormatException);
        expect(store.active!.encode(), before);
        await store.save(playerTemplate(lyrics: true));
        expect(store.active!.name, '歌词优先');
      },
    );
    test('v1 container payload is upgraded on read', () async {
      await db.setSetting(
        PlayerLayoutStore.settingsKey,
        jsonEncode({
          'version': 1,
          'activeId': 'legacy',
          'templates': [legacyLayout()],
        }),
      );
      final restored = PlayerLayoutStore(db);
      await restored.initialize();
      expect(restored.active!.name, '旧布局');
      expect(restored.active!.encode(), contains('"version": 2'));
      await restored.select(restored.active!.id);
      final saved = jsonDecode(
        await db.setting(PlayerLayoutStore.settingsKey) ?? '{}',
      ) as Map<String, dynamic>;
      expect(saved['version'], 2);
      expect(saved['templates'][0]['version'], 2);
      await restored.shutdown();
    });
    test('bad saved data falls back without overwriting bytes', () async {
      await db.setSetting(PlayerLayoutStore.settingsKey, '{"version":999}');
      final restored = PlayerLayoutStore(db);
      await restored.initialize();
      expect(restored.active, isNull);
      expect(restored.loadFailed, isTrue);
      expect(
        await db.setting(PlayerLayoutStore.settingsKey),
        '{"version":999}',
      );
      await restored.shutdown();
    });
    test('concurrent saves are serialized and persisted together', () async {
      await Future.wait([
        store.save(playerTemplate(), asNew: true),
        store.save(playerTemplate(lyrics: true), asNew: true),
      ]);
      final restored = PlayerLayoutStore(db);
      await restored.initialize();
      expect(restored.templates.length, 2);
      expect(restored.active!.name, '歌词优先');
      await restored.shutdown();
    });
  });
}
