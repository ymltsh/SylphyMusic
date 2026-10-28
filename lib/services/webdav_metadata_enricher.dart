import 'dart:async';

import '../core/models.dart';
import '../data/app_db.dart';
import 'webdav_tags.dart';

class MetadataProgress {
  const MetadataProgress(this.total, this.succeeded, this.failed, this.skipped);
  final int total, succeeded, failed, skipped;
  int get processed => succeeded + failed + skipped;
}

/// Progressive enrichment. User-triggered syncs can hold a notification-backed
/// Android foreground service while awaiting this bounded, de-duplicated walk.
/// The versioned SQLite cache permits safe retry after a process kill.
class WebDavMetadataEnricher {
  WebDavMetadataEnricher(this.db, this.tags);

  final AppDb db;
  final WebDavTags tags;
  final Map<String, Future<void>> _walks = {};
  final Map<String, int> _epochs = {};
  final Map<String, int> _walkEpochs = {};
  final Map<String, void Function(int, int)> _progressObservers = {};
  final Map<String, int> _processed = {};
  final Map<String, int> _totals = {};
  final Map<String, MetadataProgress> _stats = {};
  final Map<String, void Function(MetadataProgress)> _statsObservers = {};
  final Set<String> _visible = {};
  final Set<Future<void>> _visibleTasks = {};
  final Map<Future<void>, String> _visibleSources = {};
  bool _closed = false;

  Future<void> _enrich(Track track) async {
    final epoch = _epochs[track.ref.sourceId] ?? 0;
    if (_closed || await db.hasWebDavTags(track)) return;
    if (_closed || epoch != (_epochs[track.ref.sourceId] ?? 0)) return;
    final source = await db.source(track.ref.sourceId);
    if (_closed ||
        epoch != (_epochs[track.ref.sourceId] ?? 0) ||
        source == null ||
        !source.enabled ||
        source.kind != SourceKind.webdav) {
      return;
    }
    await tags.load(source, track);
  }

  /// Called when SQL pages arrive, never directly inside build().
  void prioritize(Iterable<Track> tracks) {
    if (_closed) return;
    for (final track in tracks) {
      if (_visible.length >= 24) break;
      final key = track.ref.key;
      if (!_visible.add(key)) continue;
      final task = () async {
        try {
          await _enrich(track);
        } catch (_) {
          // A failed track must not break the currently displayed page.
        } finally {
          _visible.remove(key);
        }
      }();
      _visibleTasks.add(task);
      _visibleSources[task] = track.ref.sourceId;
      unawaited(
        task.whenComplete(() {
          _visibleTasks.remove(task);
          _visibleSources.remove(task);
        }),
      );
    }
  }

  /// Non-blocking, single-pass walk; bounded SQL pages avoid loading the entire
  /// library in Dart memory. Existing tags survive across launches and syncs.
  void start(SourceProfile source) {
    if (_closed ||
        !source.enabled ||
        source.kind != SourceKind.webdav ||
        _walks.containsKey(source.id)) {
      return;
    }
    final epoch = _epochs[source.id] ?? 0;
    final walk = _walk(source, epoch);
    _walkEpochs[source.id] = epoch;
    _walks[source.id] = walk;
    unawaited(
      walk.whenComplete(() {
        _walks.remove(source.id);
        _walkEpochs.remove(source.id);
      }),
    );
  }

  /// Joins any already-running automatic walk; no duplicate network reads.
  Future<void> complete(
    SourceProfile source, {
    void Function(int processed, int total)? onProgress,
    void Function(MetadataProgress)? onStats,
  }) async {
    if (onStats != null) {
      _statsObservers[source.id] = onStats;
      final previous = _stats[source.id];
      if (previous != null) onStats(previous);
    }
    if (onProgress != null) {
      _progressObservers[source.id] = onProgress;
      onProgress(_processed[source.id] ?? 0, _totals[source.id] ?? 0);
    }
    // A previous user pause may have invalidated the in-flight walk.
    // Let it unwind, then start a fresh pass (cached tags are skipped).
    final previous = _walks[source.id];
    if (previous != null &&
        _walkEpochs[source.id] != (_epochs[source.id] ?? 0)) {
      await previous;
    }
    start(source);
    try {
      await _walks[source.id];
    } finally {
      if (onProgress != null) _progressObservers.remove(source.id);
      if (onStats != null) _statsObservers.remove(source.id);
    }
  }

  Future<void> _walk(SourceProfile source, int epoch) async {
    var cursor = '';
    var succeeded = 0, failed = 0, skipped = 0;
    try {
      final counts = await db.db.rawQuery(
        'SELECT COUNT(*) AS n FROM tracks WHERE source_id=? AND missing=0',
        [source.id],
      );
      final total = counts.single['n'] as int;
      void report() {
        final stats = MetadataProgress(total, succeeded, failed, skipped);
        _stats[source.id] = stats;
        _processed[source.id] = stats.processed;
        _progressObservers[source.id]?.call(stats.processed, total);
        _statsObservers[source.id]?.call(stats);
      }

      _totals[source.id] = total;
      report();
      while (!_closed && epoch == (_epochs[source.id] ?? 0)) {
        final rows = await db.db.query(
          'tracks',
          where: 'source_id=? AND missing=0 AND id>?',
          whereArgs: [source.id, cursor],
          orderBy: 'id',
          limit: 50,
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          if (_closed || epoch != (_epochs[source.id] ?? 0)) return;
          final track = Track.fromRow(row);
          cursor = track.ref.id;
          final cached = await db.hasWebDavTags(track);
          try {
            if (!cached) await _enrich(track);
          } catch (_) {
            // Retry next application session, without blocking other songs.
          }
          if (_closed || epoch != (_epochs[source.id] ?? 0)) return;
          if (cached) {
            skipped++;
          } else if (await db.hasWebDavTags(track)) {
            succeeded++;
          } else {
            failed++;
          }
          report();
          // Keep bulk scans behind user-driven playback and cover requests.
          if (!_closed && !cached) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        }
      }
    } catch (_) {
      // Source may have been deleted, the database closed or network failed.
    } finally {
      _processed.remove(source.id);
      _totals.remove(source.id);
      _stats.remove(source.id);
    }
  }

  void cancel(String sourceId) {
    _epochs[sourceId] = (_epochs[sourceId] ?? 0) + 1;
    tags.suspendSource(sourceId);
  }

  Future<void> cancelAndWait(String sourceId) async {
    final pending = [
      if (_walks[sourceId] != null) _walks[sourceId]!,
      ..._visibleSources.entries
          .where((entry) => entry.value == sourceId)
          .map((entry) => entry.key),
    ];
    cancel(sourceId);
    await Future.wait(
      pending.map((future) => future.catchError((Object _) {})),
    );
  }

  Future<void> shutdown() async {
    _closed = true;
    for (final id in _walks.keys.toList()) {
      cancel(id);
    }
    await Future.wait(
      [
        ..._walks.values,
        ..._visibleTasks,
      ].map((f) => f.catchError((Object _) {})).toList(),
    );
  }
}
