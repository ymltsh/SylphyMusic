import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/ui/music_source_connection_page.dart';

void main() {
  MusicSourceConnectionDraft? saved;
  Future<void> open(WidgetTester tester, {SourceProfile? source}) async {
    saved = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await Navigator.of(context)
                    .push<MusicSourceConnectionDraft>(
                      MaterialPageRoute(
                        builder: (_) => MusicSourceConnectionPage(
                          initialKind: SourceKind.webdav,
                          source: source,
                        ),
                      ),
                    );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String key, String value) async {
    // Validation and the WebDAV scope section can scroll earlier fields out
    // of the lazy list. Start from the top before locating the next field.
    final scrolling = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    final scrollable = tester.state<ScrollableState>(scrolling);
    scrollable.position.jumpTo(scrollable.position.minScrollExtent);
    await tester.pumpAndSettle();
    final field = find.byKey(ValueKey(key));
    await tester.scrollUntilVisible(field, 120, scrollable: scrolling);
    await tester.enterText(field, value);
    tester.testTextInput.hide();
    await tester.pump();
  }

  testWidgets(
    'optional port preserves proxy path and credentials stay separate',
    (tester) async {
      await open(tester);
      await enter(tester, 'source-name', 'Music fixture');
      await enter(
        tester,
        'source-host',
        'https://example.invalid/music/dav/?folder=one',
      );
      await enter(tester, 'source-port', '8443');
      await enter(tester, 'source-user', 'fixture');
      await enter(tester, 'source-password', 'fixture-secret');
      await tester.tap(find.byTooltip('显示密码'));
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('source-password')),
                matching: find.byType(EditableText),
              ),
            )
            .obscureText,
        false,
      );
      await tester.tap(find.text('连接并同步'));
      await tester.pumpAndSettle();
      expect(saved?.kind, SourceKind.webdav);
      expect(saved?.url, 'https://example.invalid:8443/music/dav/?folder=one');
      expect(saved?.username, 'fixture');
      expect(saved?.password, 'fixture-secret');
    },
  );

  testWidgets(
    'bad connection inputs stay on form and blank port preserves URL',
    (tester) async {
      await open(tester);
      await enter(tester, 'source-name', 'fixture');
      await enter(
        tester,
        'source-host',
        'https://user:secret@example.invalid/dav/',
      );
      await enter(tester, 'source-port', '65536');
      await tester.tap(find.text('连接并同步'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.byType(MusicSourceConnectionPage), findsOneWidget);
      await enter(tester, 'source-host', 'https://example.invalid:10486/emby/');
      await enter(tester, 'source-port', '');
      await tester.tap(find.text('连接并同步'));
      await tester.pumpAndSettle();
      expect(saved?.url, 'https://example.invalid:10486/emby/');
    },
  );

  testWidgets(
    'editing retains account and protocol identity; cancel returns nothing',
    (tester) async {
      const source = SourceProfile(
        id: 'fixture',
        name: 'fixture',
        kind: SourceKind.emby,
        url: 'https://example.invalid/emby/',
        username: 'original',
      );
      await open(tester, source: source);
      expect(find.byType(ChoiceChip), findsNothing);
      final user = find.byKey(const ValueKey('source-user'));
      await tester.scrollUntilVisible(
        user,
        120,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: user, matching: find.byType(EditableText)),
            )
            .readOnly,
        true,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
