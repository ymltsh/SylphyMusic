import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/data/app_db.dart';
import 'package:sylphy_music/services/cloud_sync.dart';
import 'package:sylphy_music/services/sources.dart';

class ServerState {
  String name = 'Playlist';
  List<String> keys = [];
  bool readonly = false, failAfterWrite = false;
  int writes = 0;
}

class FakeFactory extends AdapterFactory {
  FakeFactory(this.state) : super(const AuthVault());
  final ServerState state;
  @override
  MusicAdapter create(SourceProfile profile) => FakeAdapter(profile, state);
}

class FakeAdapter extends MusicAdapter {
  FakeAdapter(super.profile, this.state);
  final ServerState state;
  @override
  Future<RemotePlaylist> fetchPlaylist(String id) async => RemotePlaylist(
    id: id,
    name: state.name,
    tracks: [...state.keys],
    readonly: state.readonly,
  );
  @override
  Future<List<RemotePlaylist>> fetchPlaylists() async => [
    await fetchPlaylist('remote'),
  ];
  @override
  Future<void> mutatePlaylist(
    RemotePlaylist before,
    List<String> desired,
  ) async {
    state.writes++;
    state.keys = [...desired];
    if (state.failAfterWrite) {
      throw StateError('connection lost after server commit');
    }
  }

  @override
  Future<void> renamePlaylist(String id, String name) async {
    state.name = name;
  }

  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory root;
  late AppDb db;
  late ServerState state;
  late PlaylistSyncService sync;
  const source = SourceProfile(
    id: 'source',
    name: 'Source',
    kind: SourceKind.emby,
    url: 'https://example.invalid',
    username: 'test',
  );
  final a = const TrackRef('source', 'a').key,
      b = const TrackRef('source', 'b').key;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sylphy-sync-');
    db = AppDb(root);
    await db.open();
    await db.putSource(source);
    state = ServerState();
    sync = PlaylistSyncService(db, FakeFactory(state));
    await db.putPlaylist(
      const PlaylistModel(
        id: 'playlist',
        name: 'Playlist',
        kind: PlaylistKind.cloud,
        sourceId: 'source',
        remoteId: 'remote',
        baseName: 'Playlist',
      ),
    );
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  test(
    'timeout after successful append is acknowledged without duplicate replay',
    () async {
      await sync.editLocal('playlist', [a, a]);
      state.failAfterWrite = true;
      await sync.syncOne('playlist');
      expect((await db.playlist('playlist'))!.status, SyncStatus.failed);
      expect(state.writes, 1);
      state.failAfterWrite = false;
      await sync.syncOne('playlist');
      expect((await db.playlist('playlist'))!.status, SyncStatus.synced);
      expect(state.writes, 1);
      expect(state.keys, [a, a]);
      expect(await db.playlistKeys('playlist'), [a, a]);
    },
  );
  test(
    'readonly refresh preserves unsynced draft through repeated refreshes',
    () async {
      await sync.editLocal('playlist', [a]);
      state.keys = [b];
      state.readonly = true;
      await sync.syncOne('playlist');
      await sync.refreshCloudForSource(source);
      await sync.refreshCloudForSource(source);
      expect(await db.playlistKeys('playlist'), [a]);
      expect((await db.playlist('playlist'))!.status, SyncStatus.readonly);
    },
  );
  test(
    'overlapping reorder conflict pauses writes and saves local snapshot',
    () async {
      await db.putPlaylist(
        PlaylistModel(
          id: 'playlist',
          name: 'Playlist',
          kind: PlaylistKind.cloud,
          sourceId: 'source',
          remoteId: 'remote',
          base: [a, b],
        ),
      );
      await sync.editLocal('playlist', [b, a]);
      state.keys = [a, b, a];
      await sync.syncOne('playlist');
      await sync.syncOne('playlist');
      expect(state.writes, 0);
      expect((await db.playlist('playlist'))!.status, SyncStatus.conflict);
      expect(await db.playlistKeys('playlist'), [b, a]);
    },
  );
  test('cloud playlists reject tracks from other accounts', () async {
    await expectLater(
      sync.editLocal('playlist', [const TrackRef('other', 'a').key]),
      throwsStateError,
    );
    expect(await db.playlistKeys('playlist'), isEmpty);
  });
  test('offline rename synchronizes and advances name baseline', () async {
    await sync.renameLocal('playlist', 'Renamed');
    await sync.syncOne('playlist');
    expect(state.name, 'Renamed');
    final playlist = await db.playlist('playlist');
    expect(playlist!.baseName, 'Renamed');
    expect(playlist.status, SyncStatus.synced);
  });
}
