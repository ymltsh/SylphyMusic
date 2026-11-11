import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/app_db.dart';
import '../services/playback.dart';
import 'models.dart';

/// Bounded personal history; stores identities only and follows actual playback.
class ListeningHistory extends ChangeNotifier {
  static const maxEntries = 1000;
  ListeningHistory(this.db, this.playback);
  final AppDb db;
  final PlaybackCoordinator playback;
  List<TrackRef> refs = [];
  Future<void> _pending = Future.value();
  String? _last;

  Future<void> initialize() async {
    try {
      refs = (jsonDecode(await db.setting('listening_history') ?? '[]') as List)
          .whereType<String>()
          .take(maxEntries)
          .map(TrackRef.parse)
          .toList();
    } catch (_) {
      refs = [];
    }
    playback.addListener(_changed);
  }

  void _changed() {
    final ref = playback.currentRef;
    if (!playback.playing ||
        playback.position <= Duration.zero ||
        playback.error != null ||
        ref == null ||
        _last == ref.key) {
      return;
    }
    _last = ref.key;
    refs = [ref, ...refs.where((r) => r != ref)].take(maxEntries).toList();
    final value = jsonEncode(refs.map((r) => r.key).toList());
    _pending = _pending
        .then((_) => db.setSetting('listening_history', value))
        .catchError((Object _) {
          // History persistence must never interrupt audio playback.
        });
    notifyListeners();
  }

  Future<List<Track>> tracks() async {
    // Bulk-resolve up to 1000 identities without 2000 source/track queries.
    final snapshot = [...refs];
    final byKey = <String, Track>{};
    for (var i = 0; i < snapshot.length; i += 150) {
      final end = i + 150 < snapshot.length ? i + 150 : snapshot.length;
      final part = snapshot.sublist(i, end);
      if (part.isEmpty) continue;
      final clauses = List.filled(
        part.length,
        '(t.source_id=? AND t.id=?)',
      ).join(' OR ');
      final args = <Object?>[];
      for (final ref in part) {
        args.addAll([ref.sourceId, ref.id]);
      }
      final rows = await db.db.rawQuery('''
        SELECT t.* FROM tracks t JOIN sources s ON s.id=t.source_id
        WHERE s.enabled=1 AND ($clauses)
      ''', args);
      for (final row in rows) {
        final track = Track.fromRow(row);
        byKey[track.ref.key] = track;
      }
    }
    return [
      for (final ref in snapshot)
        if (byKey[ref.key] != null) byKey[ref.key]!,
    ];
  }

  Future<void> forgetSource(String sourceId) async {
    refs = refs.where((r) => r.sourceId != sourceId).toList();
    _last = null;
    final value = jsonEncode(refs.map((r) => r.key).toList());
    _pending = _pending
        .then((_) => db.setSetting('listening_history', value))
        .catchError((Object _) {});
    notifyListeners();
    await _pending;
  }

  Future<void> shutdown() async {
    playback.removeListener(_changed);
    await _pending;
    dispose();
  }
}
