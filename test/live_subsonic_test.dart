import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/services/sources.dart';
import 'package:uuid/uuid.dart';

import 'live_emby_test.dart' show MemoryVault;

void main() {
  final path = Platform.environment['SYLPHY_SUBSONIC_TEST_FILE'];
  test(
    'isolated Navidrome: login, index, original stream, cover, playlist CRUD',
    () async {
      final values = (await File(
        path!,
      ).readAsLines()).where((line) => line.trim().isNotEmpty).toList();
      final uri = Uri.parse(values[0]);
      if (uri.host != '127.0.0.1' && uri.host != 'localhost') {
        fail('Writes allowed only to an isolated loopback fixture server');
      }
      final adapter = SubsonicAdapter(
        SourceProfile(
          id: 'navidrome-test',
          name: 'Test',
          kind: SourceKind.subsonic,
          url: values[0],
          username: values[1],
        ),
        MemoryVault(),
      );
      final client = HttpClient();
      String? createdId;
      try {
        await adapter.login(values[2]);
        final library = await adapter.fetchLibrary();
        expect(library.length, greaterThanOrEqualTo(2));
        final response = await (await client.getUrl(
          await adapter.mediaUrl(library.first),
        )).close();
        expect(response.statusCode, 200);
        expect(
          await response.fold<int>(0, (sum, chunk) => sum + chunk.length),
          greaterThan(1000),
        );
        final covered = library
            .where((track) => track.coverId.isNotEmpty)
            .first;
        final cover = await (await client.getUrl(
          (await adapter.coverUrl(covered))!,
        )).close();
        expect(cover.statusCode, 200);
        expect(
          await cover.fold<int>(0, (sum, chunk) => sum + chunk.length),
          greaterThan(50),
        );
        final created = await adapter.createPlaylist(
          'Sylphy Local Test ${const Uuid().v4()}',
        );
        createdId = created.id;
        final keys = [
          library[0].ref.key,
          library[1].ref.key,
          library[0].ref.key,
        ];
        await adapter.mutatePlaylist(
          await adapter.fetchPlaylist(createdId),
          keys,
        );
        final saved = await adapter.fetchPlaylist(createdId);
        expect(saved.tracks, keys);
        final desired = [keys[1], keys[0]];
        await adapter.mutatePlaylist(saved, desired);
        expect((await adapter.fetchPlaylist(createdId)).tracks, desired);
        await adapter.renamePlaylist(createdId, 'Renamed synthetic test');
        expect(
          (await adapter.fetchPlaylist(createdId)).name,
          'Renamed synthetic test',
        );
      } finally {
        if (createdId != null) await adapter.deletePlaylist(createdId);
        client.close(force: true);
        adapter.close();
      }
    },
    skip: path == null
        ? 'Set SYLPHY_SUBSONIC_TEST_FILE for isolated server integration'
        : false,
  );
}
