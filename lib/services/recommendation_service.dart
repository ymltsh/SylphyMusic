import 'dart:async';

import '../core/models.dart';
import '../core/recommendation_models.dart';
import '../data/app_db.dart';
import '../data/recommendation_repository.dart';
import 'public_music_trends.dart';
import 'recommendation_engine.dart';
import 'llm_recommendations.dart';
import 'diagnostic_logs.dart';

/// Two independent daily snapshots, both based on the user's own library.
class RecommendationService {
  RecommendationService(
    this.db,
    this.repository, {
    LlmRecommendationClient? llm,
    this.diagnostics,
  }) : llm = llm,
       _trends = PublicMusicTrends(db);
  final DiagnosticLogs? diagnostics;
  void _record(String event, String type, {int? count, String? reason}) {
    diagnostics?.record(
      'recommendation',
      event,
      details: {'type': type, 'result_count': count, 'reason': reason},
    );
  }

  final AppDb db;
  final RecommendationRepository repository;
  final LlmRecommendationClient? llm;
  final PublicMusicTrends _trends;
  final RecommendationEngine _engine = const RecommendationEngine();
  Future<DailyMix>? _dailyInFlight;
  Future<List<RecommendedAlbum>>? _albumsInFlight;
  bool _closed = false;

  Future<DailyMix> daily({bool regenerate = false}) {
    if (_closed)
      return Future.error(StateError('Recommendation service closed'));
    return _dailyInFlight ??= _makeDaily(regenerate)
        .catchError((Object error) {
          _record('generation_failed', 'daily', reason: 'generation_error');
          throw error;
        })
        .whenComplete(() {
          _dailyInFlight = null;
        });
  }

  Future<DailyMix> _makeDaily(bool regenerate) async {
    _record(
      'generation_started',
      'daily',
      reason: regenerate ? 'manual_refresh' : 'load',
    );
    final now = DateTime.now();
    final day = localDay(now);
    final previous = await repository.latestSnapshot('daily', day);
    final llmTag = llm?.configurationTag ?? 'local';
    if (previous != null && !regenerate && previous.llmTag == llmTag) {
      final ready = await repository.dailyItems(previous.id);
      if (ready.isNotEmpty &&
          ready.length >= (previous.itemCount * .75).ceil()) {
        _record('snapshot_reused', 'daily', count: ready.length);
        return DailyMix(
          day,
          previous.generation,
          ready,
          introduction: previous.introduction,
        );
      }
    }
    final generation = await repository.nextDailyGeneration(
      day,
      previous: previous?.generation ?? -1,
    );
    final seed = stableSeed('daily:$day:$generation:v1');
    final personal =
        await db.setting('recommendation_personalization_enabled') != 'false';
    final candidates = personal
        ? await repository.candidates(seed)
        : await repository.randomCandidates(seed);
    if (candidates.isEmpty) {
      _record('generation_empty', 'daily', count: 0, reason: 'no_candidates');
      return DailyMix(day, generation, const []);
    }
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
    var finalTracks = hydrated;
    var introduction = _localLetter(hydrated);
    var letterFromLlm = false;
    if (!_closed && llm?.enabled == true && hydrated.isNotEmpty) {
      final options = [...hydrated];
      if (llm!.settings.llmMode == 'lead') {
        final selected = options.map((item) => item.track.ref.key).toSet();
        final remainder = candidates
            .where(
              (item) =>
                  !selected.contains(item.track.ref.key) &&
                  item.track.title.trim().isNotEmpty &&
                  item.track.artist.trim().isNotEmpty,
            )
            .toList();
        remainder.sort(
          (a, b) =>
              stableSeed('$seed:${a.track.ref.key}')
                  .compareTo(stableSeed('$seed:${b.track.ref.key}')),
        );
        for (final option in remainder) {
          if (options.length >= 48) break;
          final full = await db.track(option.track.ref);
          if (full == null || full.missing) continue;
          options.add(RecommendedTrack(full, '曲库中的更多发现', .18));
        }
      }
      final selection = await llm!.daily(
        options,
        now: now,
        playCounts: {
          for (final candidate in candidates)
            candidate.track.ref.key: candidate.plays,
        },
        favorites: favorites,
        publicTrends: trends,
      );
      if (selection != null) {
        finalTracks = _mergeDailySelection(hydrated, options, selection);
        if (selection.introduction.trim().isNotEmpty) {
          introduction = selection.introduction;
          letterFromLlm = true;
        }
        _record('llm_applied', 'daily', count: finalTracks.length);
      } else {
        _record(
          'local_fallback',
          'daily',
          count: hydrated.length,
          reason: 'llm_failed',
        );
      }
    } else {
      _record(
        'local_selected',
        'daily',
        count: hydrated.length,
        reason: _closed
            ? 'closed'
            : llm?.enabled != true
            ? 'llm_disabled'
            : 'no_candidates',
      );
    }
    if (_closed)
      return DailyMix(day, generation, finalTracks, introduction: introduction);
    await repository.saveDaily(
      day,
      generation,
      seed,
      finalTracks,
      introduction: introduction,
      letterOrigin: letterFromLlm ? 'llm' : 'local',
      llmTag: llmTag,
    );
    _record('generation_completed', 'daily', count: finalTracks.length);
    return DailyMix(day, generation, finalTracks, introduction: introduction);
  }

  /// A deterministic private note, used if no model is configured or available.
  String _localLetter(List<RecommendedTrack> tracks) {
    if (tracks.isEmpty) return '';
    final titles = tracks
        .take(2)
        .map(
          (item) =>
              '《${String.fromCharCodes(item.track.title.runes.take(60))}》',
        )
        .toList();
    final songs = titles.join('和');
    return '你好：\n\n'
        '今天翻看你的曲库时，我留意到了$songs。'
        '我不知道此刻你最想听哪一种声音，也不想替你的心情下结论。'
        '只是觉得，熟悉与陌生的名字放在一起，或许会碰出新的趣味。\n\n'
        '所以我把这几首和另外一些曲子放在一起。'
        '不必急着听完，想起的时候再点开就好。\n\n'
        '你的音乐笔友';
  }

  Future<List<RecommendedAlbum>> albums({bool regenerate = false}) {
    if (_closed)
      return Future.error(StateError('Recommendation service closed'));
    return _albumsInFlight ??= _makeAlbums(regenerate)
        .catchError((Object error) {
          _record('generation_failed', 'albums', reason: 'generation_error');
          throw error;
        })
        .whenComplete(() {
          _albumsInFlight = null;
        });
  }

  Future<List<RecommendedAlbum>> _makeAlbums(bool regenerate) async {
    _record(
      'generation_started',
      'albums',
      reason: regenerate ? 'manual_refresh' : 'load',
    );
    final day = localDay(DateTime.now());
    final previous = await repository.latestSnapshot('albums', day);
    final llmTag = llm?.configurationTag ?? 'local';
    if (previous != null && !regenerate && previous.llmTag == llmTag) {
      final ready = await repository.albumItems(previous.id);
      if (ready.isNotEmpty &&
          ready.length >= (previous.itemCount * .75).ceil()) {
        _record('snapshot_reused', 'albums', count: ready.length);
        return ready;
      }
    }
    final generation = (previous?.generation ?? -1) + 1;
    final seed = stableSeed('albums:$day:$generation:v1');
    final candidates = await repository.albumCandidates();
    if (candidates.isEmpty) {
      _record('generation_empty', 'albums', count: 0, reason: 'no_candidates');
      return [];
    }
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
    var finalAlbums = hydrated;
    if (!_closed && llm?.enabled == true && hydrated.isNotEmpty) {
      final options = [...hydrated];
      if (llm!.settings.llmMode == 'lead') {
        final selected = options
            .map(
              (item) => '${item.representative.ref.sourceId}|${item.groupKey}',
            )
            .toSet();
        final remainder = candidates
            .where(
              (item) => !selected.contains(
                '${item.representative.ref.sourceId}|${item.groupKey}',
              ),
            )
            .toList();
        remainder.sort(
          (a, b) =>
              stableSeed('$seed:${a.groupKey}:${a.representative.ref.sourceId}')
                  .compareTo(
                    stableSeed(
                      '$seed:${b.groupKey}:${b.representative.ref.sourceId}',
                    ),
                  ),
        );
        for (final item in remainder) {
          if (options.length >= 16) break;
          final full = await db.track(item.representative.ref);
          if (full == null || full.missing) continue;
          options.add(
            RecommendedAlbum(
              representative: full,
              groupKey: item.groupKey,
              trackCount: item.trackCount,
              reason: '值得探索的专辑',
              score: .18,
            ),
          );
        }
      }
      final selection = await llm!.albums(options, now: DateTime.now());
      if (selection != null) {
        finalAlbums = _mergeAlbumSelection(hydrated, options, selection);
        _record('llm_applied', 'albums', count: finalAlbums.length);
      } else {
        _record(
          'local_fallback',
          'albums',
          count: hydrated.length,
          reason: 'llm_failed',
        );
      }
    } else {
      _record(
        'local_selected',
        'albums',
        count: hydrated.length,
        reason: _closed
            ? 'closed'
            : llm?.enabled != true
            ? 'llm_disabled'
            : 'no_candidates',
      );
    }
    if (_closed) return finalAlbums;
    await repository.saveAlbums(
      day,
      generation,
      seed,
      finalAlbums,
      llmTag: llmTag,
    );
    _record('generation_completed', 'albums', count: finalAlbums.length);
    return finalAlbums;
  }

  List<RecommendedTrack> _mergeDailySelection(
    List<RecommendedTrack> baseline,
    List<RecommendedTrack> options,
    LlmSelection selection,
  ) {
    final chosen = <RecommendedTrack>[];
    final used = <String>{};
    final artists = <String, int>{};
    final albums = <String, int>{};
    void append(RecommendedTrack item, String reason, {bool relax = false}) {
      if (chosen.length >= baseline.length) return;
      final track = item.track;
      if (used.contains(track.ref.key)) return;
      if (!relax &&
          ((artists[track.artistGroup] ?? 0) >= 3 ||
              (albums[track.albumGroup] ?? 0) >= 2))
        return;
      used.add(track.ref.key);
      artists[track.artistGroup] = (artists[track.artistGroup] ?? 0) + 1;
      albums[track.albumGroup] = (albums[track.albumGroup] ?? 0) + 1;
      chosen.add(RecommendedTrack(track, reason, item.score));
    }

    for (final id in selection.order) {
      final item = options[id];
      append(item, selection.reasons[id] ?? item.reason);
    }
    for (final item in baseline) {
      append(item, item.reason);
    }
    for (final item in baseline) {
      append(item, item.reason, relax: true);
    }
    return chosen;
  }

  List<RecommendedAlbum> _mergeAlbumSelection(
    List<RecommendedAlbum> baseline,
    List<RecommendedAlbum> options,
    LlmSelection selection,
  ) {
    final result = <RecommendedAlbum>[];
    final used = <String>{};
    void add(RecommendedAlbum item, String reason) {
      if (result.length >= baseline.length) return;
      final key = '${item.representative.ref.sourceId}|${item.groupKey}';
      if (!used.add(key)) return;
      result.add(
        RecommendedAlbum(
          representative: item.representative,
          groupKey: item.groupKey,
          trackCount: item.trackCount,
          reason: reason,
          score: item.score,
        ),
      );
    }

    for (final id in selection.order) {
      final item = options[id];
      add(item, selection.reasons[id] ?? item.reason);
    }
    for (final item in baseline) {
      add(item, item.reason);
    }
    return result;
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

  Future<LlmConnectionTestResult> checkLlmConnection() async =>
      await llm?.checkConnection() ??
      const LlmConnectionTestResult(success: false, error: 'LLM 服务尚未初始化');

  Future<void> shutdown() async {
    _closed = true;
    llm?.close();
    await _dailyInFlight?.catchError((Object _) => DailyMix('', 0, const []));
    await _albumsInFlight?.catchError((Object _) => <RecommendedAlbum>[]);
  }
}
