import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:sylphy_music/core/app_controller.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/data/library_catalog.dart';
import 'package:sylphy_music/services/library_sync.dart';
import 'package:sylphy_music/ui/library_browser.dart';

import '../test/library_sync_test.dart' show PageAdapter, PageFactory;
import '../test/live_emby_test.dart' show MemoryVault;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native SQLite indexes and browses 50000 metadata records in bounded pages',
    (tester) async {
      MediaKit.ensureInitialized();
      final root = await Directory.systemTemp.createTemp(
        'sylphy-large-native-',
      );
      final app = await SylphyApp.bootstrap(
        dataRoot: root,
        credentialVault: MemoryVault(),
        resumeBackground: false,
        platformIntegration: false,
      );
      const source = SourceProfile(
        id: 'large-fixture',
        name: 'Large Fixture',
        kind: SourceKind.local,
        url: 'file:///',
        username: '',
      );
      Stream<List<Track>> pages() async* {
        for (var page = 0; page < 200; page++) {
          yield List.generate(
            250,
            (i) => Track(
              ref: TrackRef(source.id, '${page * 250 + i}'),
              title: 'Track ${(page * 250 + i).toString().padLeft(5, '0')}',
              artist: 'Artist ${page % 20}',
              album: 'Album $page',
            ),
          );
        }
      }

      final sync = LibrarySync(app.db, PageFactory(PageAdapter(source, pages)));
      try {
        await app.db.putSource(source);
        await sync.sync(source);
        await app.reload();
        expect(sync.progress[source.id]!.count, 50000);
        final last = await app.catalog.page(
          CatalogQuery(sourceId: source.id),
          offset: 49900,
        );
        expect(last.total, 50000);
        expect(last.rows.length, 100);
        expect(last.rows.last.track.title, 'Track 49999');
        final groups = await app.catalog.page(
          CatalogQuery(sourceId: source.id, view: 2),
        );
        expect(groups.total, 20);
        expect(groups.rows.every((row) => row.count == 2500), true);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LibraryBrowser(
                app: app,
                query: CatalogQuery(sourceId: source.id),
                onAction: (_, _) async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('播放全部 · 50000 首'), findsOneWidget);
        expect(find.text('1–100 / 50000'), findsOneWidget);
        await tester.tap(find.byTooltip('下一页'));
        await tester.pumpAndSettle();
        expect(find.text('101–200 / 50000'), findsOneWidget);
        expect(find.text('Track 00100'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        await sync.shutdown();
        await app.disposeAsync();
        await root.delete(recursive: true);
      }
    },
  );
}
