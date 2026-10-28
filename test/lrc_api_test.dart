import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/data/app_db.dart';
import 'package:sylphy_music/services/api_settings.dart';
import 'package:sylphy_music/services/lrc_api.dart';
import 'package:sylphy_music/services/sources.dart' show AuthVault;

class _MemoryVault extends AuthVault {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String id, String name) async => values['$id.$name'];

  @override
  Future<void> write(String id, String name, String value) async {
    values['$id.$name'] = value;
  }

  @override
  Future<void> delete(String id) async {
    values.removeWhere((key, _) => key.startsWith('$id.'));
  }
}

void main() {
  const track = Track(
    ref: TrackRef('local', 'song'),
    title: 'A & B',
    artist: 'Artist',
    album: 'Album',
  );

  test('disabled provider does not create a request', () async {
    final settings = ApiSettings(AppDb(Directory.systemTemp));
    final api = LrcApiClient(
      settings,
      _MemoryVault(),
      clientFactory: () => throw StateError('unexpected network'),
    );
    addTearDown(api.dispose);
    expect(await api.fetch(track), isNull);
  });

  test('rejects insecure auth, redirects and oversized responses', () async {
    final settings = ApiSettings(AppDb(Directory.systemTemp))
      ..lrcApiEnabled = true
      ..lrcApiUrl = 'http://lyrics.example/lyrics';
    final vault = _MemoryVault()..values['lrcapi.token'] = 'synthetic-token';
    var hits = 0;
    var status = 302;
    final api = LrcApiClient(
      settings,
      vault,
      clientFactory: () => MockClient((request) async {
        hits++;
        expect(request.followRedirects, isFalse);
        return http.Response(
          status == 200 ? 'x' * (1024 * 1024 + 1) : '',
          status,
        );
      }),
    );
    addTearDown(api.dispose);
    await expectLater(api.fetch(track), throwsStateError);
    expect(hits, 0);
    settings.lrcApiUrl = 'https://lyrics.example/lyrics';
    await expectLater(api.fetch(track), throwsStateError);
    expect(hits, 1);
    status = 200;
    await expectLater(api.fetch(track), throwsStateError);
    status = 404;
    expect(await api.fetch(track), isNull);
  });

  test('source cancellation and disposal finish pending requests', () async {
    final settings = ApiSettings(AppDb(Directory.systemTemp))
      ..lrcApiEnabled = true
      ..lrcApiUrl = 'https://lyrics.example/lyrics';
    var started = Completer<void>();
    final response = Completer<http.Response>();
    final api = LrcApiClient(
      settings,
      _MemoryVault(),
      clientFactory: () => MockClient((request) {
        started.complete();
        return response.future;
      }),
    );
    addTearDown(api.dispose);
    final first = api.fetch(track);
    await started.future;
    api.suspendSource('other');
    api.suspendSource(track.ref.sourceId);
    expect(await first.timeout(const Duration(seconds: 1)), isNull);
    started = Completer<void>();
    final second = api.fetch(track);
    await started.future;
    api.dispose();
    expect(await second.timeout(const Duration(seconds: 1)), isNull);
    response.complete(http.Response('[00:01]Late response', 200));
    expect(await api.fetch(track), isNull);
  });

  test('empty JSON is no match and normal LRC remains plain text', () {
    expect(LrcApiClient.parseResponse('[]'), isNull);
    expect(LrcApiClient.parseResponse('{ "data": [] }'), isNull);
    expect(LrcApiClient.parseResponse('\uFEFF [00:01]Line'), '[00:01]Line');
  });

  test('validates and normalizes LrcApi endpoint URLs', () {
    expect(ApiSettings.validateLrcApiUrl(''), ApiSettings.defaultLrcApiUrl);
    expect(
      ApiSettings.validateLrcApiUrl('http://127.0.0.1:28883'),
      'http://127.0.0.1:28883/lyrics',
    );
    expect(
      ApiSettings.validateLrcApiUrl('https://lyrics.example/jsonapi'),
      'https://lyrics.example/jsonapi',
    );
    expect(
      () => ApiSettings.validateLrcApiUrl('https://user:pass@lyrics.example'),
      throwsFormatException,
    );
    expect(
      () => ApiSettings.validateLrcApiUrl('https://lyrics.example/?token=x'),
      throwsFormatException,
    );
  });

  test('requests LRC text with encoded metadata and optional auth', () async {
    final settings = ApiSettings(AppDb(Directory.systemTemp))
      ..lrcApiEnabled = true
      ..lrcApiUrl = 'https://lyrics.example/lyrics';
    final vault = _MemoryVault()..values['lrcapi.token'] = 'secret';
    final api = LrcApiClient(
      settings,
      vault,
      clientFactory: () => MockClient((request) async {
        expect(request.url.queryParameters['title'], 'A & B');
        expect(request.url.queryParameters['artist'], 'Artist');
        expect(request.url.queryParameters['album'], 'Album');
        expect(request.headers['Authorization'], 'secret');
        return http.Response(
          '[00:01.00]Line',
          200,
          headers: const {'content-type': 'text/plain; charset=utf-8'},
        );
      }),
    );

    expect(await api.fetch(track), '[00:01.00]Line');
  });

  test('extracts lyrics from the LrcApi JSON API result list', () async {
    final settings = ApiSettings(AppDb(Directory.systemTemp))
      ..lrcApiEnabled = true
      ..lrcApiUrl = 'https://lyrics.example/jsonapi';
    final api = LrcApiClient(
      settings,
      _MemoryVault(),
      clientFactory: () => MockClient(
        (request) async => http.Response(
          '[{"title":"A & B","lyrics":"[00:01.00]Line"}]',
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    expect(await api.fetch(track), '[00:01.00]Line');
  });
}
