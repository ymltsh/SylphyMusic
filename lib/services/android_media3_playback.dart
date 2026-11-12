import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

import '../core/models.dart';
import 'artwork.dart';
import 'listening_events.dart';
import 'playback.dart';
import 'sources.dart';

/// Android gateway. No media_kit Player, AudioHandler, focus owner or recovery
/// timer is created here. The native session owns the active queue and clock.
class AndroidMedia3Playback extends PlaybackCoordinator {
  AndroidMedia3Playback(
    super.db,
    super.proxy,
    super.cache, {
    super.diagnostics,
  });
  static const _control = MethodChannel('music.sylphy/media3');
  static const _sources = MethodChannel('music.sylphy/media3_sources');
  final _updates = Lock();
  final _queueEdits = Lock();
  final _sourceEpochs = <String, int>{};
  final _adapters = <MusicAdapter, String>{};
  final _resolving = <Future<Map<String, Object?>>>{};
  final _background = <Future<void>>{};
  List<Map<String, dynamic>> _entries = [];
  int _lastSequence = -1;
  String? _sessionId;
  int _acceptedRevision = -1;
  int _queueEpoch = 0;
  int _savedAt = 0;
  int _transition = -1;
  bool _intent = false;
  bool _closing = false;
  bool _initializing = true;
  bool _disposedGateway = false;
  bool _loadedOutput = false;
  ArtworkStore? _artwork;
  Track? _retainedArt;
  int _artEpoch = 0;
  int _aheadEpoch = 0;
  String? _warmingPlan;
  final _automaticDownloads = <TrackRef>{};
  Future<String?> Function(Track)? _lyrics;
  Future<File?> Function(Track)? _cover;
  @override
  bool get hasLoadedOutput => _loadedOutput;

  @override
  Future<void> initialize() async {
    final savedQueue = await db.queue();
    final savedSpeed = double.tryParse(await db.setting('speed') ?? '1') ?? 1;
    final savedVolume =
        double.tryParse(await db.setting('volume') ?? '100') ?? 100;
    final savedGain = await db.setting('replaygain') ?? 'no';
    _sources.setMethodCallHandler((call) async {
      if (call.method == 'released') {
        if (!_closing) cache.release(TrackRef.parse(call.arguments as String));
        return null;
      }
      if (call.method != 'resolve' || _closing) return null;
      final future = _resolve(TrackRef.parse(call.arguments as String));
      _resolving.add(future);
      try {
        return await future;
      } catch (_) {
        // Exception strings can contain authorized source URLs.
        return null;
      } finally {
        _resolving.remove(future);
      }
    });
    _control.setMethodCallHandler((call) async {
      if (call.method == 'snapshot' && !_closing) {
        await _accept(call.arguments as String?);
      }
    });
    await _sources.invokeMethod<void>('ready');
    final restored = await _control.invokeMethod<String>('connect');
    await _accept(restored);
    // A running/recreated native queue always wins over the Flutter database.
    if (_entries.isEmpty) {
      snapshot = savedQueue;
      speed = savedSpeed;
      volume = savedVolume;
      replayGain = savedGain;
      if (snapshot.tracks.isNotEmpty) {
        await _replaceQueue(
          snapshot.tracks.map(TrackRef.parse).toList(),
          start: snapshot.index,
          autoplay: false,
          positionMs: snapshot.positionMs,
        );
      }
      // The queue response already refreshed public fields with native defaults.
      // Apply the saved values, not those overwritten by that response.
      await _command('rate', {'value': savedSpeed.clamp(0.5, 2)});
      await _command('volume', {'value': savedVolume.clamp(0, 100)});
      await _command('gain', {'value': savedGain});
      await _command('mode', {
        'repeat': savedQueue.repeat == RepeatKind.one ? 1 : 2,
        'shuffle': savedQueue.shuffle,
      });
    }
    _initializing = false;
  }

  Future<void> _command(String name, [Map<String, Object?>? data]) async {
    if (_closing && name != 'shutdown' && name != 'detach') return;
    final response = await _control.invokeMethod<String>(name, data);
    if (!_closing) await _accept(response);
  }

  Future<void> _accept(String? json) => _updates.synchronized(() async {
    if (json == null || _closing) return;
    final data = jsonDecode(json) as Map<String, dynamic>;
    if (_sessionId != data['sessionId']) {
      _sessionId = data['sessionId'] as String?;
      _lastSequence = -1;
      _acceptedRevision = -1;
    }
    final sequence = (data['sequence'] as num?)?.toInt() ?? 0;
    if (sequence <= _lastSequence) return;
    _lastSequence = sequence;
    final old = current;
    final oldRef = currentRef;
    if (data['items'] is List) {
      _entries = (data['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _acceptedRevision = (data['revision'] as num).toInt();
    }
    final nextTransition = (data['transition'] as num?)?.toInt() ?? 0;
    final index = _entries.isEmpty
        ? 0
        : (data['index'] as int).clamp(0, _entries.length - 1);
    position = Duration(milliseconds: (data['position'] as num).toInt());
    snapshot = QueueSnapshot(
      tracks: _entries.map((e) => e['key'] as String).toList(),
      index: index,
      positionMs: position.inMilliseconds,
      repeat: data['repeat'] == 1 ? RepeatKind.one : RepeatKind.all,
      shuffle: data['shuffle'] == true,
      order: List<int>.from(data['order'] as List? ?? snapshot.order),
      history: List<int>.from(data['history'] as List? ?? snapshot.history),
    );
    _intent = data['playWhenReady'] == true;
    playing = data['playing'] == true;
    buffering = data['buffering'] == true;
    error = switch (data['error']) {
      null => null,
      'focus_denied' => '系统暂时未授予音频焦点，请稍后重试',
      _ => '音频播放失败，请重试或检查来源',
    };
    speed = (data['rate'] as num).toDouble();
    volume = (data['volume'] as num).toDouble();
    replayGain = data['gain'] as String? ?? 'no';
    _loadedOutput = data['loaded'] == true;
    final changed =
        oldRef != currentRef ||
        (_transition >= 0 && _transition != nextTransition);
    _transition = nextTransition;
    if (changed && oldRef != null) {
      emitListeningBoundary(oldRef, switch (data['boundary']) {
        'completed' => ListeningBoundaryKind.completed,
        'repeatOne' => ListeningBoundaryKind.repeatOne,
        'stopped' => ListeningBoundaryKind.stopped,
        _ => ListeningBoundaryKind.manualSkip,
      });
      cache.release(oldRef);
    }
    if (currentRef == null) {
      current = null;
    } else if (current?.ref != currentRef) {
      current = await db.track(currentRef!);
    }
    if (_closing) return;
    duration = Duration(
      milliseconds:
          (data['duration'] as num?)?.toInt() ??
          (_entries.isEmpty
              ? 0
              : (_entries[index]['duration'] as num?)?.toInt() ?? 0),
    );
    if (old?.ref != current?.ref || changed) {
      _warmCurrent();
    }
    _scheduleAhead();
    notifyListeners();
    await _control.invokeMethod<void>('ackSnapshot', {
      'sessionId': _sessionId,
      'revision': _acceptedRevision,
    });
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!_initializing && (changed || now - _savedAt >= 5000)) {
      _savedAt = now;
      await db.saveQueue(snapshot);
    }
  });

  Future<Map<String, Object?>> _resolve(TrackRef ref) async {
    final epoch = _sourceEpochs[ref.sourceId] ?? 0;
    bool valid() => !_closing && epoch == (_sourceEpochs[ref.sourceId] ?? 0);
    final track = await db.track(ref);
    final source = await db.source(ref.sourceId);
    if (!valid() || track == null || source == null || !source.enabled) {
      throw StateError('Source unavailable');
    }
    cache.lease(ref);
    File? marker;
    try {
      final cached = source.kind == SourceKind.local
          ? null
          : await cache.find(ref, touch: true);
      if (!valid()) throw StateError('Source changed');
      if (source.kind == SourceKind.local || cached != null) {
        final file =
            cached?.file ?? File(track.remote['path']?.toString() ?? ref.id);
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file)
          throw StateError('Missing audio');
        final directory = cache.nativeLeaseDirectory(ref.key);
        await directory.create(recursive: true);
        marker = File(p.join(directory.path, const Uuid().v4()));
        await marker.writeAsString('');
        if (!valid()) throw StateError('Source changed');
        return {
          'file': file.path,
          'bytes': stat.size,
          'lease': marker.path,
          'leaseRoot': p.join(cache.root.path, 'native-leases'),
          'leaseKey': sha256.convert(utf8.encode(ref.key)).toString(),
        };
      }
      if (track.missing) throw StateError('Missing remote audio');
      final adapter = proxy.factory.create(source);
      _adapters[adapter] = source.id;
      try {
        final uri = await adapter.mediaUrl(track);
        final headers = await adapter.mediaHeaders();
        if (!valid()) throw StateError('Source changed');
        return {'uri': uri.toString(), 'headers': headers};
      } finally {
        _adapters.remove(adapter);
        adapter.close();
      }
    } catch (_) {
      if (marker != null && await marker.exists()) await marker.delete();
      rethrow;
    } finally {
      cache.release(ref);
    }
  }

  Future<List<Map<String, dynamic>>> _metadata(
    List<TrackRef> refs,
    int epoch,
  ) async {
    final result = <Map<String, dynamic>>[];
    for (final ref in refs) {
      if (_closing || epoch != _queueEpoch)
        throw StateError('Queue superseded');
      final track = await db.track(ref);
      result.add({
        'entryId': const Uuid().v4(),
        'key': ref.key,
        'sourceId': ref.sourceId,
        'title': track?.title ?? '歌曲不可用',
        'artist': track?.artist ?? '',
        'album': track?.album ?? '',
        'duration': track?.durationMs ?? 0,
      });
    }
    return result;
  }

  Future<void> _replaceQueue(
    List<TrackRef> refs, {
    int start = 0,
    bool autoplay = true,
    int positionMs = 0,
  }) async {
    final epoch = ++_queueEpoch;
    final entries = await _metadata(refs, epoch);
    if (_closing || epoch != _queueEpoch) return;
    await _command('queue', {
      'items': entries,
      'index': start,
      'play': autoplay,
      'position': positionMs,
    });
  }

  @override
  Future<void> setQueue(
    List<TrackRef> tracks, {
    int start = 0,
    bool autoplay = true,
  }) async {
    if (tracks.isEmpty) return;
    emitListeningBoundary(currentRef, ListeningBoundaryKind.replaced);
    await _queueEdits.synchronized(
      () => _replaceQueue(tracks, start: start, autoplay: autoplay),
    );
  }

  @override
  Future<void> prepareRestoredQueue() async {}
  @override
  Future<void> attachHandler() async {}
  @override
  Future<void> play({bool automaticFocusResume = false}) => _command('play');
  @override
  Future<void> pause({bool system = false}) => _command('pause');
  @override
  Future<void> toggle() => _intent ? pause() : play();
  @override
  Future<void> next({bool manual = true}) => _command('next');
  @override
  Future<void> previous() => _command('previous');
  @override
  Future<void> seek(Duration target) =>
      _command('seek', {'position': max(0, target.inMilliseconds)});
  @override
  Future<void> jumpTo(int index) async {
    if (index >= 0 && index < _entries.length)
      await _command('jump', {'index': index});
  }

  @override
  Future<void> retry() => _command('retry');
  @override
  Future<void> setSpeed(double v) async {
    await _command('rate', {'value': v.clamp(0.5, 2)});
    await db.setSetting('speed', '$speed');
  }

  @override
  Future<void> setVolume(double v) async {
    await _command('volume', {'value': v.clamp(0, 100)});
    await db.setSetting('volume', '$volume');
  }

  @override
  Future<void> setReplayGain(String mode) async {
    if (!const ['no', 'track', 'album'].contains(mode)) return;
    await _command('gain', {'value': mode});
    await db.setSetting('replaygain', mode);
  }

  @override
  Future<void> setPlaybackMode(PlaybackMode mode) => _command('mode', {
    'repeat': mode == PlaybackMode.singleLoop ? 1 : 2,
    'shuffle': mode == PlaybackMode.shuffle,
  });
  @override
  Future<void> enqueueAll(List<TrackRef> refs) => _insert(refs, next: false);
  @override
  Future<void> enqueueNextAll(List<TrackRef> refs) => _insert(refs, next: true);
  @override
  Future<void> enqueue(TrackRef ref, {bool next = false}) =>
      _insert([ref], next: next);
  Future<void> _insert(List<TrackRef> refs, {required bool next}) =>
      _queueEdits.synchronized(() async {
        if (refs.isEmpty) return;
        final additions = await _metadata(refs, ++_queueEpoch);
        await _command('snapshot');
        final items = [..._entries];
        items.insertAll(
          next && items.isNotEmpty ? snapshot.index + 1 : items.length,
          additions,
        );
        await _command('queue', {
          'items': items,
          'index': snapshot.index,
          'keepOutput': true,
          'play': _intent,
          'position': position.inMilliseconds,
        });
      });
  @override
  Future<void> removeAt(int index) => _queueEdits.synchronized(() async {
    await _command('snapshot');
    if (index < 0 || index >= _entries.length) return;
    final items = [..._entries]..removeAt(index);
    await _command('queue', {
      'items': items,
      'index': (index < snapshot.index ? snapshot.index - 1 : snapshot.index)
          .clamp(0, max(0, items.length - 1)),
      'keepOutput': index != snapshot.index,
      'play': _intent,
      'position': index == snapshot.index ? 0 : position.inMilliseconds,
    });
  });
  @override
  Future<void> clearQueue() async {
    ++_queueEpoch;
    emitListeningBoundary(currentRef, ListeningBoundaryKind.stopped);
    await _command('queue', {'items': <Object>[], 'play': false});
  }

  @override
  void invalidateSource(String id) {
    ++_aheadEpoch;
    _warmingPlan = null;
    _sourceEpochs[id] = (_sourceEpochs[id] ?? 0) + 1;
    for (final entry in _adapters.entries.toList()) {
      if (entry.value == id) entry.key.close();
    }
    _runBackground(_command('invalidate', {'sourceId': id}));
  }

  @override
  Future<void> stopCurrentOutput({required String sourceId}) =>
      _command('invalidate', {'sourceId': sourceId});
  @override
  Future<void> save() => _updates.synchronized(
    () => db.saveQueue(
      QueueSnapshot(
        tracks: snapshot.tracks,
        index: snapshot.index,
        positionMs: position.inMilliseconds,
        repeat: snapshot.repeat,
        shuffle: snapshot.shuffle,
        order: snapshot.order,
        history: snapshot.history,
      ),
    ),
  );

  @override
  void setLyricsLoader(Future<String?> Function(Track) loader) {
    _lyrics = loader;
    _warmCurrent();
  }

  @override
  void setArtworkLoader(Future<File?> Function(Track) loader) {
    _cover = loader;
    _warmCurrent();
  }

  @override
  void attachNotificationArtwork(ArtworkStore artwork) {
    _artwork = artwork;
    artwork.assets.addListener(_artChanged);
    _warmCurrent();
  }

  void _artChanged() {
    final change = _artwork?.assets.lastChange;
    if (change != null &&
        current != null &&
        change.sourceId == current!.ref.sourceId &&
        change.key == _artwork!.key(current!)) {
      _runBackground(_publishArt(current!));
    }
  }

  void _warmCurrent() {
    final track = current;
    if (_closing || track == null) return;
    final old = _retainedArt;
    if (old?.ref != track.ref) {
      if (old != null) _artwork?.release(old);
      _retainedArt = track;
      _artwork?.retain(track);
    }
    final lyrics = _lyrics;
    if (lyrics != null) _runBackground(lyrics(track).then<void>((_) {}));
    if (_artwork != null) {
      _runBackground(_publishArt(track));
    } else if (_cover != null) {
      _runBackground(_cover!(track).then<void>((_) {}));
    }
  }

  void _scheduleAhead() {
    final order = snapshot.order;
    final at = order.indexOf(snapshot.index);
    final indices = <int>[];
    if (_intent && currentRef != null) indices.add(snapshot.index);
    if (_intent && snapshot.repeat != RepeatKind.one && at >= 0) {
      for (var step = 1; step <= 2 && step < order.length; step++) {
        final next = at + step;
        if (snapshot.shuffle && next >= order.length) break;
        indices.add(order[next % order.length]);
      }
    }
    final refs = indices
        .map((i) => TrackRef.parse(snapshot.tracks[i]))
        .toList();
    final plan = jsonEncode([
      _intent,
      snapshot.repeat.name,
      refs.map((r) => r.key).toList(),
    ]);
    if (_warmingPlan == plan) return;
    _warmingPlan = plan;
    final epoch = ++_aheadEpoch;
    for (final old in _automaticDownloads.toList()) {
      if (!refs.contains(old)) {
        _automaticDownloads.remove(old);
        _runBackground(cache.cancel(old, automaticOnly: true));
      }
    }
    _runBackground(_warmAhead(refs, epoch));
  }

  Future<void> _warmAhead(List<TrackRef> refs, int epoch) async {
    final candidates = <({Track track, SourceProfile source})>[];
    for (final ref in refs) {
      if (_closing || epoch != _aheadEpoch) return;
      final track = await db.track(ref);
      final source = await db.source(ref.sourceId);
      if (_closing || epoch != _aheadEpoch) return;
      if (track == null || source == null || !source.enabled) continue;
      if (ref != currentRef) {
        if (_lyrics != null) _runBackground(_lyrics!(track).then<void>((_) {}));
        if (_cover != null) _runBackground(_cover!(track).then<void>((_) {}));
      }
      if (source.kind != SourceKind.local && !track.missing)
        candidates.add((track: track, source: source));
    }
    // Keep verified whole-file caching, while the native transport remains the
    // playback reader. Only the existing cache pipeline can mark files READY.
    for (final item in candidates) {
      if (_closing || epoch != _aheadEpoch) return;
      _automaticDownloads.add(item.track.ref);
      try {
        await cache.fetchWhole(item.track, item.source, automatic: true);
      } catch (_) {
        // Optional caching never interrupts the native audio reader.
      }
    }
  }

  void _runBackground(Future<void> task) {
    final safe = task.catchError((Object _) {});
    _background.add(safe);
    unawaited(safe.whenComplete(() => _background.remove(safe)));
  }

  Future<void> _publishArt(Track track) async {
    final epoch = ++_artEpoch;
    final file = await _artwork?.load(track);
    if (_closing ||
        epoch != _artEpoch ||
        currentRef != track.ref ||
        file == null)
      return;
    final directory = Directory(
      p.join((await getTemporaryDirectory()).path, 'media_session_covers'),
    );
    await directory.create(recursive: true);
    final name =
        '${sha256.convert(utf8.encode('${track.ref.key}/${track.artworkVersion}'))}.image';
    final target = File(p.join(directory.path, name));
    final sourceStat = await file.stat();
    final targetStat = await target.stat();
    if (targetStat.type != FileSystemEntityType.file ||
        targetStat.size != sourceStat.size ||
        targetStat.modified.isBefore(sourceStat.modified)) {
      await file.copy(target.path);
    }
    if (_closing || epoch != _artEpoch || currentRef != track.ref) return;
    final package = (await PackageInfo.fromPlatform()).packageName;
    await _command('art', {
      'key': track.ref.key,
      'uri': Uri(
        scheme: 'content',
        host: '$package.mediaartwork',
        pathSegments: ['media_artwork', name],
      ).toString(),
    });
  }

  @override
  Future<void> shutdown() async {
    if (_closing) return;
    _closing = true;
    ++_aheadEpoch;
    for (final ref in _automaticDownloads) {
      await cache.cancel(ref, automaticOnly: true);
    }
    ++_queueEpoch;
    ++_artEpoch;
    for (final adapter in _adapters.keys.toList()) {
      adapter.close();
    }
    await _command('shutdown');
    await _sources.invokeMethod<void>('detach');
    while (_resolving.isNotEmpty) {
      await Future.wait(
        _resolving.toList().map(
          (f) => f.then<void>((_) {}, onError: (Object _) {}),
        ),
      );
    }
    while (_background.isNotEmpty) {
      await Future.wait(_background.toList());
    }
    await _updates.synchronized(() async {});
    await save();
    _sources.setMethodCallHandler(null);
    _control.setMethodCallHandler(null);
    _detachArt();
    if (!_disposedGateway) {
      _disposedGateway = true;
      disposeNativeGateway();
    }
  }

  void _detachArt() {
    _artwork?.assets.removeListener(_artChanged);
    if (_retainedArt != null) _artwork?.release(_retainedArt!);
    _retainedArt = null;
    _artwork = null;
  }

  @override
  void dispose() {
    if (_disposedGateway) return;
    _closing = true;
    _disposedGateway = true;
    ++_artEpoch;
    unawaited(_command('detach'));
    _sources.setMethodCallHandler(null);
    _control.setMethodCallHandler(null);
    _detachArt();
    disposeNativeGateway();
  }
}
