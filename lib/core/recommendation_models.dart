import 'dart:math';

import 'models.dart';

/// A complete, dated, locally reproducible set of recommendations.
class DailyMix {
  const DailyMix(this.day, this.generation, this.items);
  final String day;
  final int generation;
  final List<RecommendedTrack> items;
  List<TrackRef> get refs => items.map((item) => item.track.ref).toList();
}

class RecommendedTrack {
  const RecommendedTrack(this.track, this.reason, this.score);
  final Track track;
  final String reason;
  final double score;
}

class RecommendedAlbum {
  const RecommendedAlbum({
    required this.representative,
    required this.groupKey,
    required this.trackCount,
    required this.reason,
    required this.score,
  });
  final Track representative;
  final String groupKey;
  final int trackCount;
  final String reason;
  final double score;
}

class TrackCandidate {
  const TrackCandidate({
    required this.track,
    required this.plays,
    required this.completions,
    required this.skips,
    required this.lastPlayedAt,
  });
  final Track track;
  final int plays, completions, skips;
  final int? lastPlayedAt;
}

class AlbumCandidate {
  const AlbumCandidate({
    required this.representative,
    required this.groupKey,
    required this.trackCount,
    required this.unplayedCount,
    required this.plays,
  });
  final Track representative;
  final String groupKey;
  final int trackCount, unplayedCount, plays;
}

/// Strict title + artist matching: do not remove live, remaster or remix suffixes.
String trendIdentity(String title, String artist) {
  String clean(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return '${clean(artist)}\u0000${clean(title)}';
}

String localDay(DateTime time) =>
    '${time.year.toString().padLeft(4, '0')}-'
    '${time.month.toString().padLeft(2, '0')}-'
    '${time.day.toString().padLeft(2, '0')}';

int stableSeed(String value) {
  var hash = 2166136261;
  for (final rune in value.runes) {
    hash = ((hash ^ rune) * 16777619) & 0x7fffffff;
  }
  return hash;
}

double bounded(double number) => max(0.0, min(1.0, number));
