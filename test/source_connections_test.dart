import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/data/app_db.dart';
import 'package:sylphy_music/services/source_connections.dart';
import 'package:sylphy_music/services/sources.dart';

class ConnectionAdapter extends MusicAdapter {
  ConnectionAdapter(super.profile, this.validate, this.closed);
  final Future<void> Function() validate;
  final void Function() closed;
  @override
  Future<void> validateConnection() => validate();
  @override
  void close() => closed();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ConnectionFactory extends AdapterFactory {
  ConnectionFactory(this.validate, this.closed) : super(const AuthVault());
  final Future<void> Function() validate;
  final void Function() closed;
  @override
  MusicAdapter create(SourceProfile profile) =>
      ConnectionAdapter(profile, validate, closed);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppDb db;
  late SourceConnections connections;
  var authFails = false, validations = 0, enabledCalls = 0, closed = 0;
  Completer<void>? gate, validating;
  const source = SourceProfile(
    id: 's',
    name: 'S',
    kind: SourceKind.emby,
    url: 'https://example.invalid',
    username: 'u',
  );
  setUp(() async {
    authFails = false;
    validations = 0;
    enabledCalls = 0;
    closed = 0;
    gate = null;
    validating = null;
    root = await Directory.systemTemp.createTemp('sylphy-connections-');
    db = AppDb(root);
    await db.open();
    await db.putSource(source);
    connections = SourceConnections(
      db,
      ConnectionFactory(
        () async {
          validations++;
          if (validating?.isCompleted == false) validating!.complete();
          await gate?.future;
          if (authFails) throw const HttpFailure(401, 'Login expired');
        },
        () {
          closed++;
          if (gate?.isCompleted == false) gate!.complete();
        },
      ),
      onDisabled: (s) async {
        expect((await db.source(s.id))!.enabled, false);
      },
      onEnabled: (s) async {
        enabledCalls++;
        expect((await db.source(s.id))!.enabled, true);
      },
    );
  });
  tearDown(() async {
    await connections.shutdown();
    await db.close();
    await root.delete(recursive: true);
  });

  test('disable preserves metadata and personal playlist; failed reauthentication stays disabled', () async {
    const track = Track(
      ref: TrackRef('s', 'one'),
      title: 'One',
      artist: '',
      album: '',
    );
    await db.replaceSourceTracks(source.id, [track]);
    await db.replacePlaylistKeys('favorites', [track.ref.key]);
    await connections.toggle(source.id);
    authFails = true;
    await expectLater(
      connections.toggle(source.id),
      throwsA(isA<HttpFailure>()),
    );
    expect((await db.source(source.id))!.enabled, false);
    expect((await db.tracks()).single.ref, track.ref);
    expect(await db.playlistKeys('favorites'), [track.ref.key]);
    expect(enabledCalls, 0);
    expect(closed, 1);
  });
  test(
    'reenable authenticates once and schedules synchronization after enabling',
    () async {
      await connections.toggle(source.id);
      await connections.toggle(source.id);
      expect(validations, 1);
      expect(enabledCalls, 1);
      expect(closed, 1);
    },
  );
  test(
    'repeated enable clicks share one validation instead of toggling back off',
    () async {
      await connections.toggle(source.id);
      gate = Completer<void>();
      validating = Completer<void>();
      final first = connections.toggle(source.id);
      await validating!.future;
      final second = connections.toggle(source.id);
      gate!.complete();
      await Future.wait([first, second]);
      expect(validations, 1);
      expect(enabledCalls, 1);
      expect((await db.source(source.id))!.enabled, true);
    },
  );
  test(
    'changed connection during validation is not overwritten by old operation',
    () async {
      await connections.toggle(source.id);
      gate = Completer<void>();
      validating = Completer<void>();
      final enable = connections.toggle(source.id);
      final failed = expectLater(enable, throwsStateError);
      await validating!.future;
      await db.putSource(
        const SourceProfile(
          id: 's',
          name: 'Changed',
          kind: SourceKind.emby,
          url: 'https://other.invalid',
          username: 'u',
          enabled: false,
        ),
      );
      gate!.complete();
      await failed;
      expect((await db.source(source.id))!.url, 'https://other.invalid');
      expect((await db.source(source.id))!.enabled, false);
      expect(enabledCalls, 0);
    },
  );
  test(
    'shutdown aborts validation and cannot enable a source afterwards',
    () async {
      await connections.toggle(source.id);
      gate = Completer<void>();
      validating = Completer<void>();
      final failed = expectLater(
        connections.toggle(source.id),
        throwsStateError,
      );
      await validating!.future;
      await connections.shutdown();
      await failed;
      expect((await db.source(source.id))!.enabled, false);
      expect(enabledCalls, 0);
    },
  );
}
