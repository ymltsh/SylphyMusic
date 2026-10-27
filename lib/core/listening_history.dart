import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/app_db.dart';
import '../services/playback.dart';
import 'models.dart';

/// Bounded personal history; stores identities only and follows actual playback.
class ListeningHistory extends ChangeNotifier {
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
          .take(50)
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
    refs = [ref, ...refs.where((r) => r != ref)].take(50).toList();
    final value = jsonEncode(refs.map((r) => r.key).toList());
    _pending = _pending
        .then((_) => db.setSetting('listening_history', value))
        .catchError((Object _) {
          // History persistence must never interrupt audio playback.
        });
    notifyListeners();
  }

  Future<List<Track>> tracks() async {
    final tracks = <Track>[];
    for (final ref in [...refs]) {
      final source = await db.source(ref.sourceId);
      if (source == null || !source.enabled) continue;
      final track = await db.track(ref);
      if (track != null) tracks.add(track);
    }
    return tracks;
  }

  Future<void> shutdown() async {
    playback.removeListener(_changed);
    await _pending;
    dispose();
  }
}
