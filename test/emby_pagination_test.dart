import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/services/sources.dart';

import 'media_proxy_test.dart' show NetworkTestBinding;
import 'live_emby_test.dart' show MemoryVault;

void main() {
  NetworkTestBinding();
  late HttpServer server;
  late EmbyAdapter adapter;
  var malformed = false;
  setUp(() async {
    malformed = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path, query = request.uri.queryParameters;
      dynamic payload;
      if (path.endsWith('AuthenticateByName')) {
        payload = {
          'AccessToken': 'fixture-token',
          'ServerId': 'fixture-server',
          'User': {'Id': 'u'},
        };
      } else if (path == '/emby/Users/u/Items/p') {
        payload = {
          'Type': 'Playlist',
          'Name': 'Large Playlist',
          'CanEdit': true,
        };
      } else if (malformed) {
        payload = {'Error': 'invalid list'};
      } else {
        final entries = path.contains('/Playlists/');
        final playlists = query['IncludeItemTypes'] == 'Playlist';
        final total = entries
            ? 520
            : playlists
            ? 505
            : 260;
        final start = int.parse(query['StartIndex'] ?? '0'),
            limit = int.parse(query['Limit'] ?? '250');
        final count = (total - start).clamp(0, limit);
        payload = {
          'Items': List.generate(count, (index) {
            final id = start + index;
            return entries
                ? {'Id': 'same-track', 'PlaylistItemId': 'entry$id'}
                : {
                    'Id': 'item$id',
                    'Name': 'Item $id',
                    'Container': 'flac',
                    'MediaStreams': [
                      {
                        'Type': 'Audio',
                        'SampleRate': 96000,
                        'BitRate': 2000000,
                      },
                    ],
                  };
          }),
          if (playlists || entries) 'TotalRecordCount': total,
        };
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(payload));
      await request.response.close();
    });
    adapter = EmbyAdapter(
      SourceProfile(
        id: 's',
        name: 'Fixture',
        kind: SourceKind.emby,
        url: 'http://127.0.0.1:${server.port}/emby',
        username: 'fixture',
      ),
      MemoryVault(),
    );
    await adapter.login('fixture-password');
  });
  tearDown(() async {
    adapter.close();
    await server.close(force: true);
  });
  test('library without TotalRecordCount fetches until empty and reads source properties', () async {
    final tracks = await adapter.fetchLibrary();
    expect(tracks.length, 260);
    expect(tracks.last.ref.id, 'item259');
    expect(tracks.first.remote['sampleRate'], 96000);
  });
  test('playlist index and repeated entries are fully paged', () async {
    expect((await adapter.fetchPlaylists()).length, 505);
    final playlist = await adapter.fetchPlaylist('p');
    expect(playlist.tracks.length, 520);
    expect(playlist.tracks.toSet().length, 1);
    expect(playlist.entryIds.toSet().length, 520);
  });
  test(
    'malformed success payload is rejected instead of replacing the old index',
    () async {
      malformed = true;
      await expectLater(adapter.fetchLibrary(), throwsStateError);
    },
  );
}
