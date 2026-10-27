import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/services/sources.dart';
import 'package:uuid/uuid.dart';

import 'live_emby_test.dart' show MemoryVault;

void main() {
  final path = Platform.environment['SYLPHY_EMBY_CREDENTIAL_FILE'];
  final approved =
      Platform.environment['SYLPHY_ALLOW_TEST_PLAYLIST_WRITES'] == '1';
  test(
    'disposable Emby playlist: create, append duplicates, reorder, rename, delete',
    () async {
      final values = (await File(
        path!,
      ).readAsLines()).where((s) => s.trim().isNotEmpty).toList();
      final adapter = EmbyAdapter(
        SourceProfile(
          id: 'live-write-test',
          name: 'Test',
          kind: SourceKind.emby,
          url: values[0].trim(),
          username: values[1].trim(),
        ),
        MemoryVault(),
      );
      final name = 'Sylphy Test ${const Uuid().v4()}';
      String? createdId;
      try {
        await adapter.login(values[2]);
        final tracks = await adapter.fetchLibrary();
        expect(tracks.length, greaterThanOrEqualTo(2));
        final created = await adapter.createPlaylist(name);
        createdId = created.id;
        final before = await adapter.fetchPlaylist(createdId);
        expect(before.name, name);
        expect(before.tracks, isEmpty);
        final entries = [
          tracks[0].ref.key,
          tracks[1].ref.key,
          tracks[0].ref.key,
        ];
        await adapter.mutatePlaylist(before, entries);
        final appended = await adapter.fetchPlaylist(createdId);
        expect(appended.tracks, entries);
        final reordered = [entries[1], entries[0]];
        await adapter.mutatePlaylist(appended, reordered);
        expect((await adapter.fetchPlaylist(createdId)).tracks, reordered);
        await adapter.renamePlaylist(createdId, '$name renamed');
        expect((await adapter.fetchPlaylist(createdId)).name, '$name renamed');
      } catch (error) {
        fail('临时 Emby 歌单写入联调失败（${error.runtimeType}）；凭据与曲库内容已隐藏');
      } finally {
        try {
          if (createdId != null) {
            final playlist = await adapter.fetchPlaylist(createdId);
            if (playlist.name == name || playlist.name == '$name renamed') {
              await adapter.deletePlaylist(createdId);
              expect(
                (await adapter.fetchPlaylists()).any((p) => p.id == createdId),
                isFalse,
              );
            } else {
              fail('临时歌单名称发生外部变化，已停止清理');
            }
          }
        } finally {
          adapter.close();
        }
      }
    },
    skip: path == null || !approved
        ? 'Requires explicit permission for disposable test playlist writes'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
