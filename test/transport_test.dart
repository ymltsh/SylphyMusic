import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/services/sources.dart';

import 'media_proxy_test.dart' show NetworkTestBinding;

void main() {
  NetworkTestBinding();
  late HttpServer server;
  late StrictTransport transport;
  var requests = 0, status = 503;
  setUp(() async {
    requests = 0;
    status = 503;
    transport = StrictTransport();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      request.response.statusCode = status;
      if (status == 302) {
        request.response.headers.set(
          'location',
          'http://127.0.0.1:1/credential-trap',
        );
      }
      request.response.write('sensitive-server-response');
      await request.response.close();
    });
  });
  tearDown(() async {
    transport.close();
    await server.close(force: true);
  });
  test(
    'safe reads use a finite retry budget; errors omit server payloads',
    () async {
      Object? failure;
      try {
        await transport.request(
          'GET',
          Uri.parse('http://127.0.0.1:${server.port}'),
          retrySafe: true,
        );
      } catch (error) {
        failure = error;
      }
      expect(requests, 3);
      expect('$failure', isNot(contains('sensitive-server-response')));
    },
  );
  test('writes never replay automatically', () async {
    await expectLater(
      transport.request(
        'POST',
        Uri.parse('http://127.0.0.1:${server.port}'),
        body: {},
      ),
      throwsA(isA<HttpFailure>()),
    );
    expect(requests, 1);
  });
  test('authentication rejection and redirects are not retried', () async {
    status = 401;
    await expectLater(
      transport.request(
        'GET',
        Uri.parse('http://127.0.0.1:${server.port}'),
        retrySafe: true,
      ),
      throwsA(isA<HttpFailure>()),
    );
    expect(requests, 1);
    status = 302;
    await expectLater(
      transport.request(
        'GET',
        Uri.parse('http://127.0.0.1:${server.port}'),
        retrySafe: true,
      ),
      throwsStateError,
    );
    expect(requests, 2);
  });
  test('base URL preserves reverse proxy prefixes and rejects credentials', () {
    SourceProfile profile(String url) => SourceProfile(
      id: 's',
      name: 'S',
      kind: SourceKind.emby,
      url: url,
      username: 'u',
    );
    expect(
      appendPath(profile('https://example.invalid/music/emby'), 'Users/1').path,
      '/music/emby/Users/1',
    );
    for (final url in [
      'https://u:secret@example.invalid',
      'https://example.invalid?token=secret',
      'file:///music',
      'https:///missing',
    ]) {
      expect(() => appendPath(profile(url), 'Items'), throwsFormatException);
    }
  });
}
