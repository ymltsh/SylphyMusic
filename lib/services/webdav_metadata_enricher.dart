import 'dart:async';

import '../core/models.dart';
import '../data/app_db.dart';
import 'webdav_tags.dart';

/// In-app progressive enrichment. One low-priority walk per WebDAV source;
/// high-priority visible rows reuse WebDavTags' bounded/de-duplicated reads.
/// This is not an Android persistent background service: exiting the app stops
/// the walk, and the next launch skips already-versioned rows.
class WebDavMetadataEnricher {
  WebDavMetadataEnricher(this.db, this.tags);

  final AppDb db;
  final WebDavTags tags;
  final Map<String, Future<void>> _walks = {};
  final Map<String, int> _epochs = {};
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
    _walks[source.id] = walk;
    unawaited(
      walk.whenComplete(() {
        _walks.remove(source.id);
      }),
    );
  }

  Future<void> _walk(SourceProfile source, int epoch) async {
    var cursor = '';
    try {
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
          // Keep bulk scans behind user-driven playback and cover requests.
          if (!_closed) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        }
      }
    } catch (_) {
      // Source may have been deleted, the database closed or network failed.
    }
  }

  void cancel(String sourceId) {
    _epochs[sourceId] = (_epochs[sourceId] ?? 0) + 1;
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
