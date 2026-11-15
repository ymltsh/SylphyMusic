import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/services/online_artwork.dart';

void main() {
  late HttpServer server;
  late OnlineArtworkProvider provider;
  late List<int> picture;
  final seen = <Uri>[];
  final credentials = <String?>[];
  var responseFor = <String, Object?>{};

  Track track({String artist = 'Daft Punk', String album = 'Homework'}) =>
      Track(
        ref: const TrackRef('test', 'song'),
        title: 'Da Funk',
        artist: artist,
        album: album,
      );

  setUp(() async {
    seen.clear();
    credentials.clear();
    responseFor = {};
    picture = await File('test/fixtures/cover.png').readAsBytes();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      seen.add(request.uri);
      credentials.add(request.headers.value(HttpHeaders.authorizationHeader));
      credentials.add(request.headers.value('X-Emby-Token'));
      final path = request.uri.path;
      final fixture = responseFor[path];
      if (fixture is Map<String, Object?>) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(fixture));
      } else if (fixture == 'redirect') {
        request.response.statusCode = 307;
        request.response.headers.set('Location', '/image.png');
      } else if (fixture == 'image') {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(picture);
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    final address = 'http://127.0.0.1:${server.port}';
    provider = OnlineArtworkProvider(
      audioDbBase: Uri.parse('$address/audiodb/'),
      musicBrainzBase: Uri.parse('$address/musicbrainz/'),
      coverArtBase: Uri.parse('$address/art/'),
    );
  });

  tearDown(() async {
    provider.close();
    await server.close(force: true);
  });

  test('fetches exact artist portrait; never forwards credentials', () async {
    final address = 'http://127.0.0.1:${server.port}';
    responseFor['/audiodb/search.php'] = {
      'artists': [
        {'strArtist': 'Daft Punk', 'strArtistThumb': '$address/image.png'},
      ],
    };
    responseFor['/image.png'] = 'image';
    final bytes = await provider.fetch(track(), artist: true);
    expect(bytes, picture);
    expect(seen.map((request) => request.path), [
      '/audiodb/search.php',
      '/image.png',
    ]);
    expect(credentials.every((value) => value == null), isTrue);
  });

  test('exact album fallback uses TheAudioDB first and coalesces', () async {
    final address = 'http://127.0.0.1:${server.port}';
    responseFor['/audiodb/searchalbum.php'] = {
      'album': [
        {
          'strArtist': 'Daft Punk',
          'strAlbum': 'Homework',
          'strAlbumThumb': '$address/image.png',
        },
      ],
    };
    responseFor['/image.png'] = 'image';
    final result = await Future.wait([
      provider.fetch(track(), artist: false),
      provider.fetch(track(), artist: false),
    ]);
    expect(result[0], picture);
    expect(result[1], picture);
    expect(seen.length, 2);
    expect(seen.first.queryParameters['a'], 'Homework');
    expect(credentials.every((value) => value == null), isTrue);
  });

  test('rejects mismatched artist/album and caches misses in memory', () async {
    final address = 'http://127.0.0.1:${server.port}';
    responseFor['/audiodb/searchalbum.php'] = {
      'album': [
        {
          'strArtist': 'Someone Else',
          'strAlbum': 'Homework',
          'strAlbumThumb': '$address/image.png',
        },
      ],
    };
    responseFor['/musicbrainz/release-group/'] = {'release-groups': []};
    expect(await provider.fetch(track(), artist: false), isNull);
    expect(await provider.fetch(track(), artist: false), isNull);
    expect(seen.length, 2);
    expect(seen.where((uri) => uri.path == '/image.png'), isEmpty);
  });

  test('uses MusicBrainz + Cover Art Archive when TheAudioDB misses', () async {
    const id = '48140466-cff6-3222-bd55-63c27e43190d';
    responseFor['/musicbrainz/release-group/'] = {
      'release-groups': [
        {
          'id': id,
          'title': 'Homework',
          'artist-credit': [
            {
              'name': 'Daft Punk',
              'artist': {'name': 'Daft Punk'},
            },
          ],
        },
      ],
    };
    responseFor['/art/release-group/$id/front-500'] = 'redirect';
    responseFor['/image.png'] = 'image';
    expect(await provider.fetch(track(), artist: false), picture);
    expect(seen.map((u) => u.path), [
      '/audiodb/searchalbum.php',
      '/musicbrainz/release-group/',
      '/art/release-group/$id/front-500',
      '/image.png',
    ]);
    expect(credentials.every((value) => value == null), isTrue);
  });

  test('skips unknown metadata without network traffic', () async {
    expect(await provider.fetch(track(artist: ''), artist: true), isNull);
    expect(await provider.fetch(track(album: ''), artist: false), isNull);
    expect(seen, isEmpty);
  });
}
