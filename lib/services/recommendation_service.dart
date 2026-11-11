import 'dart:async';

import '../core/models.dart';
import '../core/recommendation_models.dart';
import '../data/app_db.dart';
import '../data/recommendation_repository.dart';
import 'public_music_trends.dart';
import 'recommendation_engine.dart';

/// Two independent daily snapshots, both based on the user's own library.
class RecommendationService {
  RecommendationService(this.db, this.repository)
    : _trends = PublicMusicTrends(db);
  final AppDb db;
  final RecommendationRepository repository;
  final PublicMusicTrends _trends;
  final RecommendationEngine _engine = const RecommendationEngine();
  Future<DailyMix>? _dailyInFlight;
  Future<List<RecommendedAlbum>>? _albumsInFlight;
  bool _closed = false;

  Future<DailyMix> daily({bool regenerate = false}) {
    if (_closed)
      return Future.error(StateError('Recommendation service closed'));
    return _dailyInFlight ??= _makeDaily(regenerate).whenComplete(() {
      _dailyInFlight = null;
    });
  }

  Future<DailyMix> _makeDaily(bool regenerate) async {
    final now = DateTime.now();
    final day = localDay(now);
    final previous = await repository.latestSnapshot('daily', day);
    if (previous != null && !regenerate) {
      final ready = await repository.dailyItems(previous.id);
      if (ready.isNotEmpty &&
          ready.length >= (previous.itemCount * .75).ceil()) {
        return DailyMix(day, previous.generation, ready);
      }
    }
    final generation = (previous?.generation ?? -1) + 1;
    final seed = stableSeed('daily:$day:$generation:v1');
    final personal =
        await db.setting('recommendation_personalization_enabled') != 'false';
    final candidates = personal
        ? await repository.candidates(seed)
        : await repository.randomCandidates(seed);
    if (candidates.isEmpty) return DailyMix(day, generation, const []);
    final favorites = personal ? await repository.favoriteKeys() : <String>{};
    final recent = await repository.recentTracks(now);
    final affinity = personal
        ? await repository.timeArtistAffinity(now)
        : <String, int>{};
    // Public charts are optional. Network errors fall back to the last chart
    // cache or to an entirely local recommendation.
    final trends = await _trends.load();
    final result = _engine.daily(
      seed: seed,
      now: now,
      candidates: candidates,
      favorites: favorites,
      recent: recent,
      timeArtists: affinity,
      trends: trends,
    );
    final hydrated = <RecommendedTrack>[];
    for (final item in result) {
      final full = await db.track(item.track.ref);
      if (full != null && !full.missing) {
        hydrated.add(RecommendedTrack(full, item.reason, item.score));
      }
    }
    if (_closed) return DailyMix(day, generation, hydrated);
    await repository.saveDaily(day, generation, seed, hydrated);
    return DailyMix(day, generation, hydrated);
  }

  Future<List<RecommendedAlbum>> albums({bool regenerate = false}) {
    if (_closed)
      return Future.error(StateError('Recommendation service closed'));
    return _albumsInFlight ??= _makeAlbums(regenerate).whenComplete(() {
      _albumsInFlight = null;
    });
  }

  Future<List<RecommendedAlbum>> _makeAlbums(bool regenerate) async {
    final day = localDay(DateTime.now());
    final previous = await repository.latestSnapshot('albums', day);
    if (previous != null && !regenerate) {
      final ready = await repository.albumItems(previous.id);
      if (ready.isNotEmpty && ready.length >= (previous.itemCount * .75).ceil())
        return ready;
    }
    final generation = (previous?.generation ?? -1) + 1;
    final seed = stableSeed('albums:$day:$generation:v1');
    final candidates = await repository.albumCandidates();
    if (candidates.isEmpty) return [];
    final personal =
        await db.setting('recommendation_personalization_enabled') != 'false';
    final listens = personal
        ? await repository.candidates(seed)
        : <TrackCandidate>[];
    final favorites = personal ? await repository.favoriteKeys() : <String>{};
    final result = _engine.albums(
      seed: seed,
      candidates: candidates,
      listeningCandidates: listens,
      favorites: favorites,
    );
    final hydrated = <RecommendedAlbum>[];
    for (final item in result) {
      final full = await db.track(item.representative.ref);
      if (full != null && !full.missing) {
        hydrated.add(
          RecommendedAlbum(
            representative: full,
            groupKey: item.groupKey,
            trackCount: item.trackCount,
            reason: item.reason,
            score: item.score,
          ),
        );
      }
    }
    if (_closed) return hydrated;
    await repository.saveAlbums(day, generation, seed, hydrated);
    return hydrated;
  }

  Future<DailyMix> hide(TrackRef ref) async {
    await repository.hideTrack(ref);
    return daily(regenerate: true);
  }

  Future<void> setOnlineChartsEnabled(bool enabled) => db.setSetting(
    'recommendation_public_charts_enabled',
    enabled ? 'true' : 'false',
  );

  Future<bool> get onlineChartsEnabled async =>
      await db.setting('recommendation_public_charts_enabled') != 'false';

  Future<void> clearStatistics() async {
    await repository.clearAnalytics();
  }

  Future<void> shutdown() async {
    _closed = true;
    await _dailyInFlight?.catchError((Object _) => DailyMix('', 0, const []));
    await _albumsInFlight?.catchError((Object _) => <RecommendedAlbum>[]);
  }
}
