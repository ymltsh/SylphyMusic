import 'dart:async';

import '../core/models.dart';
import '../data/app_db.dart';
import 'webdav_tags.dart';

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
  final Set<String> _visible = {};
  final Set<Future<void>> _visibleTasks = {};
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
      unawaited(task.whenComplete(() => _visibleTasks.remove(task)));
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
  }) async {
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
    }
  }

  Future<void> _walk(SourceProfile source, int epoch) async {
    var cursor = '';
    var processed = 0;
    try {
      final counts = await db.db.rawQuery(
        'SELECT COUNT(*) AS n FROM tracks WHERE source_id=? AND missing=0',
        [source.id],
      );
      final total = counts.single['n'] as int;
      _totals[source.id] = total;
      _progressObservers[source.id]?.call(processed, total);
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
          try {
            await _enrich(track);
          } catch (_) {
            // Retry next application session, without blocking other songs.
          }
          processed++;
          _processed[source.id] = processed;
          _progressObservers[source.id]?.call(processed, total);
          // Keep bulk scans behind user-driven playback and cover requests.
          if (!_closed) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        }
      }
    } catch (_) {
      // Source may have been deleted, the database closed or network failed.
    } finally {
      _processed.remove(source.id);
      _totals.remove(source.id);
    }
  }

  void cancel(String sourceId) {
    _epochs[sourceId] = (_epochs[sourceId] ?? 0) + 1;
    tags.suspendSource(sourceId);
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
