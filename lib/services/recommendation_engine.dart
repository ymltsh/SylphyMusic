import 'dart:math';

import '../core/recommendation_models.dart';

/// Pure, deterministic recommendation ranking. Never reads the network or DB.
class RecommendationEngine {
  const RecommendationEngine();

  double _popularity(int plays) => bounded(log(plays + 1) / log(32));

  double _noise(int seed, String identity) =>
      (stableSeed('$seed:$identity') % 10000) / 10000.0 * 0.035;

  List<RecommendedTrack> daily({
    required int seed,
    required DateTime now,
    required List<TrackCandidate> candidates,
    required Set<String> favorites,
    required Set<String> recent,
    required Map<String, int> timeArtists,
    required Map<String, double> trends,
  }) {
    final artistStrength = <String, double>{};
    final albumStrength = <String, double>{};
    final seen = <String, TrackCandidate>{};
    for (final candidate in candidates) {
      final t = candidate.track;
      if (t.title.trim().isEmpty || t.artist.trim().isEmpty) continue;
      seen[t.ref.key] = candidate;
      final strength =
          _popularity(candidate.plays) +
          (favorites.contains(t.ref.key) ? .75 : 0);
      final artist = t.artistGroup;
      artistStrength[artist] = max(artistStrength[artist] ?? 0, strength);
      albumStrength[t.albumGroup] = max(
        albumStrength[t.albumGroup] ?? 0,
        strength,
      );
    }
    final largestTimeAffinity = timeArtists.values.fold<int>(0, max);
    final preferred = <RecommendedTrack>[];
    final related = <RecommendedTrack>[];
    final rediscovery = <RecommendedTrack>[];

    for (final candidate in seen.values) {
      final track = candidate.track;
      final isFavorite = favorites.contains(track.ref.key);
      final song = _popularity(candidate.plays);
      final artist = bounded(artistStrength[track.artistGroup] ?? 0);
      final album = bounded(albumStrength[track.albumGroup] ?? 0);
      final preference = bounded(
        .50 * max(song, isFavorite ? 1 : 0) + .35 * artist + .15 * album,
      );
      final contextual = largestTimeAffinity > 0
          ? bounded((timeArtists[track.artistGroup] ?? 0) / largestTimeAffinity)
          : .5;
      final novelty = bounded(1 - _popularity(candidate.plays));
      final daysAgo = candidate.lastPlayedAt == null
          ? 999
          : now
                .difference(
                  DateTime.fromMillisecondsSinceEpoch(candidate.lastPlayedAt!),
                )
                .inDays;
      final freshness = daysAgo < 3
          ? .05
          : daysAgo < 14
          ? .4
          : 1.0;
      final quality =
          (track.album.isNotEmpty ? .5 : 0) +
          (track.year > 0 ? .25 : 0) +
          (track.durationMs > 0 ? .25 : 0);
      final trend = trends[trendIdentity(track.title, track.artist)] ?? 0;
      final penalty =
          (recent.contains(track.ref.key) ? .17 : 0) +
          (candidate.skips > candidate.completions + 2 ? .12 : 0);
      final score = bounded(
        .34 * preference +
            .15 * contextual +
            .20 * novelty +
            .10 * freshness +
            .10 * quality +
            .11 * trend -
            penalty +
            _noise(seed, track.ref.key),
      );
      final reason = trend > .65 && !isFavorite && candidate.plays == 0
          ? '近期热门 · 曲库已收录'
          : isFavorite
          ? '来自你的收藏'
          : candidate.plays >= 2
          ? '你经常听的旋律'
          : artist > .2
          ? '你喜欢的歌手 · 更多发现'
          : daysAgo > 90 && candidate.plays > 0
          ? '很久没听过'
          : '曲库中的宝藏';
      final recommended = RecommendedTrack(track, reason, score);
      if (isFavorite || candidate.plays >= 2) {
        preferred.add(recommended);
      } else if (artist > .2) {
        related.add(recommended);
      } else {
        rediscovery.add(recommended);
      }
    }
    for (final pool in [preferred, related, rediscovery]) {
      pool.sort((a, b) => b.score.compareTo(a.score));
    }
    final result = <RecommendedTrack>[];
    final used = <String>{};
    final artistCounts = <String, int>{};
    final albumCounts = <String, int>{};
    bool add(RecommendedTrack item, {bool relax = false}) {
      if (!used.add(item.track.ref.key)) return false;
      final artist = item.track.artistGroup;
      final album = item.track.albumGroup;
      if (!relax &&
          ((artistCounts[artist] ?? 0) >= 3 ||
              (albumCounts[album] ?? 0) >= 2)) {
        used.remove(item.track.ref.key);
        return false;
      }
      result.add(item);
      artistCounts[artist] = (artistCounts[artist] ?? 0) + 1;
      albumCounts[album] = (albumCounts[album] ?? 0) + 1;
      return true;
    }

    void take(List<RecommendedTrack> pool, int count) {
      var added = 0;
      for (final item in pool) {
        if (added >= count) return;
        if (add(item)) added++;
      }
    }

    take(preferred, 10);
    take(related, 8);
    take(rediscovery, 6);
    final rest = [...preferred, ...related, ...rediscovery]
      ..sort((a, b) => b.score.compareTo(a.score));
    for (final item in rest) {
      if (result.length >= 24) break;
      add(item);
    }
    for (final item in rest) {
      if (result.length >= 24) break;
      add(item, relax: true);
    }
    // Balance familiar and exploratory tracks throughout the sequence.
    final random = Random(seed);
    final ordered = <RecommendedTrack>[];
    final chunks = <List<RecommendedTrack>>[
      result.where((e) => preferred.contains(e)).toList()..shuffle(random),
      result.where((e) => related.contains(e)).toList()..shuffle(random),
      result.where((e) => rediscovery.contains(e)).toList()..shuffle(random),
    ];
    while (ordered.length < result.length) {
      var changed = false;
      for (final pool in chunks) {
        if (pool.isNotEmpty) {
          final element = pool.removeAt(0);
          if (!ordered.contains(element)) ordered.add(element);
          changed = true;
        }
      }
      if (!changed) break;
    }
    return ordered;
  }

  List<RecommendedAlbum> albums({
    required int seed,
    required List<AlbumCandidate> candidates,
    required List<TrackCandidate> listeningCandidates,
    required Set<String> favorites,
  }) {
    final artistAffinity = <String, double>{};
    for (final t in listeningCandidates) {
      final affinity =
          _popularity(t.plays) + (favorites.contains(t.track.ref.key) ? 1 : 0);
      final key = t.track.artistGroup;
      artistAffinity[key] = max(artistAffinity[key] ?? 0, affinity);
    }
    final ranked = <RecommendedAlbum>[];
    for (final candidate in candidates) {
      final track = candidate.representative;
      final artist =
          (track.albumArtist.isNotEmpty ? track.albumArtist : track.artist)
              .trim()
              .toLowerCase();
      final affinity = bounded(artistAffinity[artist] ?? 0);
      final unexplored = candidate.unplayedCount / candidate.trackCount;
      final listened = _popularity(candidate.plays);
      final quality = bounded(candidate.trackCount / 10);
      final score = bounded(
        .4 * affinity +
            .3 * unexplored +
            .15 * listened +
            .15 * quality +
            _noise(seed, '${track.ref.sourceId}/${candidate.groupKey}'),
      );
      final reason = affinity > .25 && unexplored > .5
          ? '喜欢的歌手 · 尚未完整探索'
          : listened > .3
          ? '值得重新聆听'
          : '发现一张新专辑';
      ranked.add(
        RecommendedAlbum(
          representative: track,
          groupKey: candidate.groupKey,
          trackCount: candidate.trackCount,
          reason: reason,
          score: score,
        ),
      );
    }
    ranked.sort((a, b) => b.score.compareTo(a.score));
    final artistCount = <String, int>{};
    final selected = <RecommendedAlbum>[];
    for (final a in ranked) {
      final key =
          (a.representative.albumArtist.isNotEmpty
                  ? a.representative.albumArtist
                  : a.representative.artist)
              .trim()
              .toLowerCase();
      if ((artistCount[key] ?? 0) >= 2) continue;
      selected.add(a);
      artistCount[key] = (artistCount[key] ?? 0) + 1;
      if (selected.length == 8) break;
    }
    return selected;
  }
}
