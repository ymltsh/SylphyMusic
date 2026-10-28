import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sylphy_music/data/app_db.dart';
import 'package:sylphy_music/services/api_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('quote API supports hitokoto and custom JSON formats', () {
    expect(ApiSettings.parseQuote('{"hitokoto":"你好","from":"测试"}'), '你好');
    expect(ApiSettings.parseQuote('{"data":{"content":"今天天气很好"}}'), '今天天气很好');
    expect(ApiSettings.parseQuote('"一句话"'), '一句话');
    expect(() => ApiSettings.parseQuote('{}'), throwsFormatException);
  });
  test('API URLs validate HTTPS and handle defaults', () {
    expect(ApiSettings.validateQuoteUrl(''), ApiSettings.defaultQuoteUrl);
    expect(
      ApiSettings.validateGitHubMirror(''),
      ApiSettings.defaultGitHubMirror,
    );
    expect(
      ApiSettings.validateGitHubMirror('https://mirror.example/proxy'),
      'https://mirror.example/proxy/',
    );
    expect(
      () => ApiSettings.validateQuoteUrl('http://example.com'),
      throwsFormatException,
    );
    expect(
      () =>
          ApiSettings.validateGitHubMirror('https://user:pass@mirror.example'),
      throwsFormatException,
    );
    expect(
      () => ApiSettings.validateGitHubMirror('https://mirror.example/?url=x'),
      throwsFormatException,
    );
  });
  test(
    'custom endpoints and quotes are persisted, without credentials',
    () async {
      final root = await Directory.systemTemp.createTemp('sylphy-api-');
      final db = AppDb(root);
      await db.open();
      var requests = 0;
      http.Client createClient() => MockClient((request) async {
        requests++;
        return http.Response.bytes(
          utf8.encode('{"hitokoto":"每一天都值得歌唱"}'),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final api = ApiSettings(db, clientFactory: createClient);
      try {
        await api.initialize();
        await api.setQuoteUrl('https://quotes.example/api');
        await api.setGitHubMirror('https://mirror.example/prefix');
        expect(api.lrcApiEnabled, isFalse);
        await api.setLrcApiUrl('http://127.0.0.1:28883/prefix');
        await api.setLrcApiEnabled(true);
        expect(api.quote, '每一天都值得歌唱');
        expect(api.quoteUrl, 'https://quotes.example/api');
        expect(api.githubMirror, 'https://mirror.example/prefix/');
        final previous = requests;
        await api.refreshQuote();
        expect(requests, previous); // Same calendar day: no re-fetch.
        final restored = ApiSettings(db, clientFactory: createClient);
        await restored.initialize();
        expect(restored.lrcApiEnabled, isTrue);
        expect(restored.lrcApiUrl, 'http://127.0.0.1:28883/prefix/lyrics');
        expect(restored.quote, '每一天都值得歌唱');
        expect(restored.quoteUrl, api.quoteUrl);
        expect(restored.githubMirror, api.githubMirror);
        restored.dispose();
      } finally {
        api.dispose();
        await db.close();
        await root.delete(recursive: true);
      }
    },
  );
}
