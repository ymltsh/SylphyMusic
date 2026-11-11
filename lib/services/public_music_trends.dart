import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../core/recommendation_models.dart';
import '../data/app_db.dart';

/// Downloads public charts only. Never uploads listening history, track lists,
/// source addresses, credentials or personal identifiers.
class PublicMusicTrends {
  PublicMusicTrends(this.db);
  final AppDb db;
  static const _cacheKey = 'recommendation_public_charts_v1';
  static const _appleRegionKey = 'recommendation_apple_region';
  static const _enabledKey = 'recommendation_public_charts_enabled';

  Future<Map<String, double>> load() async {
    if (await db.setting(_enabledKey) == 'false') return {};
    final cached = await db.setting(_cacheKey);
    Map<String, dynamic>? entry;
    if (cached != null) {
      try {
        entry = jsonDecode(cached) as Map<String, dynamic>;
      } catch (_) {
        /* Ignore a corrupt cache. */
      }
    }
    final previous = <String, double>{};
    final scores = entry?['scores'];
    if (scores is Map) {
      for (final item in scores.entries) {
        if (item.key is String && item.value is num) {
          previous[item.key as String] = bounded(
            (item.value as num).toDouble(),
          );
        }
      }
    }
    final updated = (entry?['updated'] as num?)?.toInt() ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - updated < 24 * 3600000) {
      return previous;
    }
    try {
      final fresh = await _fetch();
      if (fresh.isEmpty) return previous;
      await db.setSetting(
        _cacheKey,
        jsonEncode({
          'updated': DateTime.now().millisecondsSinceEpoch,
          'scores': fresh,
        }),
      );
      return fresh;
    } catch (_) {
      return previous;
    }
  }

  Future<Map<String, double>> _fetch() async {
    final regionCandidate = (await db.setting(_appleRegionKey) ?? 'cn')
        .toLowerCase();
    final region = RegExp(r'^[a-z]{2}$').hasMatch(regionCandidate)
        ? regionCandidate
        : 'cn';
    final responses = await Future.wait([
      _fetchJson(
        Uri.https('api.listenbrainz.org', '/1/stats/sitewide/recordings', {
          'range': 'week',
          'count': '100',
        }),
      ).catchError((Object _) => <String, dynamic>{}),
      _fetchJson(
        Uri.https(
          'rss.marketingtools.apple.com',
          '/api/v2/$region/music/most-played/100/songs.json',
        ),
      ).catchError((Object _) => <String, dynamic>{}),
    ]);
    final scores = <String, double>{};
    void remember(String title, String artist, double score) {
      if (title.trim().isEmpty || artist.trim().isEmpty) return;
      final id = trendIdentity(title, artist);
      scores[id] = max(scores[id] ?? 0, bounded(score));
    }

    final listenPayload = responses[0]['payload'];
    final listenRows = listenPayload is Map
        ? listenPayload['recordings']
        : null;
    if (listenRows is List) {
      for (var i = 0; i < min(listenRows.length, 100); i++) {
        final row = listenRows[i];
        if (row is! Map) continue;
        remember(
          '${row['track_name'] ?? ''}',
          '${row['artist_name'] ?? ''}',
          1 - i / 120,
        );
      }
    }
    final feed = responses[1]['feed'];
    final appleRows = feed is Map ? feed['results'] : null;
    if (appleRows is List) {
      for (var i = 0; i < min(appleRows.length, 100); i++) {
        final row = appleRows[i];
        if (row is! Map) continue;
        remember(
          '${row['name'] ?? ''}',
          '${row['artistName'] ?? ''}',
          .9 * (1 - i / 120),
        );
      }
    }
    return scores;
  }

  Future<Map<String, dynamic>> _fetchJson(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 4));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'SylphyMusic/1.0 (+https://github.com/ymltsh/SylphyMusic)',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      if (response.statusCode != HttpStatus.ok) return {};
      final buffer = BytesBuilder(copy: false);
      var bytes = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 4))) {
        bytes += chunk.length;
        if (bytes > 1024 * 1024) throw const FormatException('Chart too large');
        buffer.add(chunk);
      }
      final parsed = jsonDecode(utf8.decode(buffer.takeBytes()));
      return parsed is Map<String, dynamic> ? parsed : {};
    } finally {
      client.close(force: true);
    }
  }
}
