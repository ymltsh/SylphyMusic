import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import '../core/models.dart';
import '../data/app_db.dart';
import 'cache.dart';
import 'media_proxy.dart';

class PlaybackCoordinator extends ChangeNotifier {
  PlaybackCoordinator(this.db, this.proxy, this.cache);
  final AppDb db;
  final MediaProxy proxy;
  final CacheManager cache;
  final Player player = Player();
  QueueSnapshot snapshot = const QueueSnapshot();
  Track? current;
  bool playing = false, buffering = false;
  Duration position = Duration.zero, duration = Duration.zero;
  String? error;
  int failures = 0;
  double speed = 1.0;
  double volume = 100;
  bool _opening = false, _userPaused = false, _interrupted = false;
  bool _handlingFailure = false;
  int _lastSaved = 0;
  int _reconnects = 0;
  TrackRef? _recoveryRef;
  AudioSession? _session;
  TrackRef? _leased;
  final Set<String> _reloadSources = {};
  void invalidateSource(String id) => _reloadSources.add(id);
  SylphyAudioHandler? handler;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  Future<void> initialize() async {
    snapshot = await db.queue();
    speed = double.tryParse(await db.setting('speed') ?? '1') ?? 1;
    volume = double.tryParse(await db.setting('volume') ?? '100') ?? 100;
    await player.setRate(speed);
    await player.setVolume(volume);
    await _setMpvOption('gapless-audio', 'weak');
    await _setMpvOption('replaygain', await db.setting('replaygain') ?? 'no');
    await _setMpvOption('audio-pitch-correction', 'yes');
    // Lyrics are resolved by SylphyApp, not mpv's external subtitle loader.
    // Autoloading a sidecar LRC can emit a fatal stream error on Windows
    // extended-length paths even though the audio itself is playable.
    await _setMpvOption('sub-auto', 'no');
    _subscriptions.add(
      player.stream.playing.listen((v) {
        playing = v;
        cache.updatePlaybackPriority(active: v, buffering: buffering);
        notifyListeners();
        _publish();
      }),
    );
    _subscriptions.add(
      player.stream.buffering.listen((v) {
        buffering = v;
        if (v && !_opening) cache.invalidatePreview();
        cache.updatePlaybackPriority(active: playing, buffering: v);
        notifyListeners();
        _publish();
      }),
    );
    _subscriptions.add(
      player.stream.position.listen((v) {
        if (error != null && playing && !buffering && v > position) {
          error = null;
        }
        position = v;
        if (v >= const Duration(seconds: 5)) failures = 0;
        notifyListeners();
        _publish();
        final now = DateTime.now().millisecondsSinceEpoch;
        if (playing &&
            !buffering &&
            duration > Duration.zero &&
            duration - position <= const Duration(seconds: 30) &&
            (player.state.buffer - position >= const Duration(seconds: 8) ||
                player.state.buffer >= duration)) {
          unawaited(_prefetchNext());
        }
        if (!_opening && now - _lastSaved > 5000) {
          _lastSaved = now;
          unawaited(save());
        }
      }),
    );
    _subscriptions.add(
      player.stream.duration.listen((v) {
        duration = v;
        notifyListeners();
        _publish();
      }),
    );
    _subscriptions.add(
      player.stream.completed.listen((done) {
        if (done && !_opening) {
          unawaited(_finished());
        }
      }),
    );
    _subscriptions.add(
      player.stream.error.listen((e) {
        error = e;
        notifyListeners();
        if (!_opening && !_handlingFailure) {
          _handlingFailure = true;
          unawaited(_failed(e).whenComplete(() => _handlingFailure = false));
        }
      }),
    );
    await _prepareCurrent(); // Restore metadata only, never autoplay after process restart.
    if (Platform.isAndroid) {
      _session = await AudioSession.instance;
      await _session!.configure(const AudioSessionConfiguration.music());
      _subscriptions.add(
        _session!.interruptionEventStream.listen((event) {
          if (event.begin) {
            if (event.type == AudioInterruptionType.duck) {
              unawaited(player.setVolume(volume * 0.25));
            } else if (playing) {
              _interrupted = true;
              unawaited(pause(system: true));
            }
          } else {
            if (event.type == AudioInterruptionType.duck) {
              unawaited(player.setVolume(volume));
            } else if (_interrupted && !_userPaused) {
              _interrupted = false;
              unawaited(play());
            }
          }
        }),
      );
      _subscriptions.add(
        _session!.becomingNoisyEventStream.listen((_) {
          _interrupted = false;
          unawaited(pause(system: true));
        }),
      );
    }
  }

  Future<void> _setMpvOption(String key, String value) async {
    final native = player.platform;
    if (native is NativePlayer) {
      try {
        await native.setProperty('options/$key', value);
      } catch (_) {
        // Some libmpv builds expose this option only at initialization time.
      }
    }
  }

  Future<void> setReplayGain(String mode) async {
    if (!const ['no', 'track', 'album'].contains(mode)) return;
    await _setMpvOption('replaygain', mode);
    await db.setSetting('replaygain', mode);
    notifyListeners();
  }

  Future<void> attachHandler() async {
    if (!Platform.isAndroid) return;
    handler = await AudioService.init(
      builder: () => SylphyAudioHandler(this),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'music.sylphy.playback',
        androidNotificationChannelName: 'Sylphy Music',
        androidNotificationOngoing: true,
      ),
    );
    _publish();
  }

  TrackRef? get currentRef =>
      snapshot.tracks.isEmpty ||
          snapshot.index < 0 ||
          snapshot.index >= snapshot.tracks.length
      ? null
      : TrackRef.parse(snapshot.tracks[snapshot.index]);
  Future<void> _prepareCurrent() async {
    final ref = currentRef;
    current = ref == null ? null : await db.track(ref);
    position = Duration(milliseconds: snapshot.positionMs);
    notifyListeners();
    _publish();
  }

  Future<void> setQueue(
    List<TrackRef> tracks, {
    int start = 0,
    bool autoplay = true,
  }) async {
    if (tracks.isEmpty) return;
    final previousRef = currentRef;
    if (previousRef != null) {
      await cache.cancel(previousRef, automaticOnly: true);
    }
    final safe = start.clamp(0, tracks.length - 1);
    final order = List.generate(tracks.length, (i) => i);
    if (snapshot.shuffle) {
      order.remove(safe);
      order.shuffle(Random());
      order.insert(0, safe);
    }
    snapshot = QueueSnapshot(
      tracks: tracks.map((e) => e.key).toList(),
      index: safe,
      order: order,
      shuffle: snapshot.shuffle,
      repeat: snapshot.repeat,
    );
    position = Duration.zero;
    duration = Duration.zero;
    cache.beginQueueSession();
    failures = 0;
    await save();
    await _loadCurrent(autoplay: autoplay, manual: true);
  }

  Future<void> _loadCurrent({bool autoplay = true, bool manual = false}) async {
    _opening = true;
    final resumeMs = snapshot.positionMs;
    error = null;
    try {
      if (_leased != null) {
        cache.release(_leased!);
        _leased = null;
      }
      final ref = currentRef;
      if (ref == null) return;
      position = Duration(milliseconds: snapshot.positionMs);
      duration = Duration.zero;
      current = await db.track(ref);
      if (current == null) throw StateError('歌曲索引不存在');
      if (current!.missing && !await cache.contains(ref)) {
        throw StateError('服务器歌曲已消失，且本机没有完整缓存');
      }
      final source = await db.source(ref.sourceId);
      if (source == null) throw StateError('来源已删除');
      if (!source.enabled) throw StateError('来源已停用');
      if (autoplay && _session != null && !await _session!.setActive(true)) {
        throw StateError('系统暂时未授予音频焦点');
      }
      cache.lease(ref);
      _leased = ref;
      if (source.kind == SourceKind.local) {
        final f = File(current!.remote['path']?.toString() ?? ref.id);
        if (!await f.exists()) throw StateError('本地原始音频文件不存在');
        await player.open(Media(f.uri.toString()), play: autoplay);
      } else {
        final cached = await cache.find(ref, touch: true);
        final uri = cached != null
            ? cached.file.uri
            : proxy.ticket(current!, source);
        await player.open(Media(uri.toString()), play: autoplay);
      }
      if (resumeMs > 0) {
        await player.seek(Duration(milliseconds: resumeMs));
      }
      if (!autoplay) await player.pause();
      _userPaused = !autoplay;
      _reloadSources.remove(source.id);
      notifyListeners();
      _publish();
      await save();
      unawaited(_prefetchNext());
    } catch (e) {
      error = e.toString();
      notifyListeners();
      if (autoplay) await _failed(error!, manual: manual);
    } finally {
      _opening = false;
    }
  }

  Future<void> enqueue(TrackRef ref, {bool next = false}) async {
    if (snapshot.tracks.isEmpty) {
      await setQueue([ref]);
      return;
    }
    final tracks = [...snapshot.tracks];
    var index = snapshot.index;
    var history = [...snapshot.history];
    List<int> order;
    if (next && !snapshot.shuffle) {
      final insertion = (index + 1).clamp(0, tracks.length);
      tracks.insert(insertion, ref.key);
      history = [for (final i in history) i >= insertion ? i + 1 : i];
      order = List.generate(tracks.length, (i) => i);
    } else {
      tracks.add(ref.key);
      order = snapshot.order.length == snapshot.tracks.length
          ? [...snapshot.order]
          : List.generate(snapshot.tracks.length, (i) => i);
      if (next) {
        final at = order.indexOf(index);
        order.insert(at < 0 ? order.length : at + 1, tracks.length - 1);
      } else {
        order.add(tracks.length - 1);
      }
    }
    snapshot = QueueSnapshot(
      tracks: tracks,
      index: index,
      positionMs: position.inMilliseconds,
      repeat: snapshot.repeat,
      shuffle: snapshot.shuffle,
      order: order,
      history: history,
    );
    await save();
    notifyListeners();
    cache.invalidatePreview();
    unawaited(_prefetchNext());
  }

  Future<void> _prefetchNext() async {
    if (!playing || buffering) return;
    if (duration <= Duration.zero ||
        duration - position > const Duration(seconds: 30) ||
        (player.state.buffer - position < const Duration(seconds: 8) &&
            player.state.buffer < duration)) {
      return;
    }
    final i = _nextIndex();
    if (i == null) return;
    try {
      final t = await db.track(TrackRef.parse(snapshot.tracks[i]));
      if (t == null) return;
      final source = await db.source(t.ref.sourceId);
      if (source == null) return;
      await cache.prefetchNext(
        t,
        source,
        planId: '${snapshot.index}/$i/${t.ref.key}',
      );
    } catch (_) {}
  }

  Future<void> play() async {
    _userPaused = false;
    if (current == null) await _prepareCurrent();
    if (current == null) return;
    final source = await db.source(current!.ref.sourceId);
    if (source == null || !source.enabled) {
      error = '来源已停用或移除';
      await pause();
      notifyListeners();
      return;
    }
    if (player.state.playlist.medias.isEmpty ||
        _reloadSources.contains(source.id) ||
        error != null) {
      await _loadCurrent(autoplay: true, manual: true);
      return;
    }
    if (_session != null && !await _session!.setActive(true)) {
      error = '系统暂时未授予音频焦点';
      notifyListeners();
      return;
    }
    await player.play();
  }

  Future<void> pause({bool system = false}) async {
    if (!system) _userPaused = true;
    await player.pause();
    await save();
  }

  Future<void> toggle() async {
    if (playing) {
      await pause();
    } else {
      await play();
    }
  }

  int? _nextIndex() {
    if (snapshot.tracks.isEmpty) return null;
    final seq = snapshot.order.length == snapshot.tracks.length
        ? snapshot.order
        : List.generate(snapshot.tracks.length, (i) => i);
    final at = seq.indexOf(snapshot.index);
    if (at >= 0 && at < seq.length - 1) return seq[at + 1];
    if (snapshot.repeat != RepeatKind.all) return null;
    return seq.isNotEmpty ? seq.first : null;
  }

  Future<void> next({bool manual = true}) async {
    var next = _nextIndex();
    if (next == null) {
      await pause();
      return;
    }
    final old = currentRef;
    final newHistory = [...snapshot.history, snapshot.index];
    var order = snapshot.order;
    if (snapshot.shuffle &&
        snapshot.repeat == RepeatKind.all &&
        snapshot.order.isNotEmpty &&
        next == snapshot.order.first) {
      order = List.generate(snapshot.tracks.length, (i) => i)
        ..shuffle(Random());
      if (order.length > 1 && order.first == snapshot.index) {
        final first = order.removeAt(0);
        order.add(first);
      }
      next = order.first;
    }
    snapshot = QueueSnapshot(
      tracks: snapshot.tracks,
      index: next,
      repeat: snapshot.repeat,
      shuffle: snapshot.shuffle,
      order: order,
      history: newHistory,
    );
    if (old != null) await cache.cancel(old, automaticOnly: true);
    position = Duration.zero;
    await _loadCurrent(autoplay: true, manual: manual);
  }

  Future<void> previous() async {
    if (snapshot.tracks.isEmpty) return;
    int? index;
    var hist = [...snapshot.history];
    if (hist.isNotEmpty) {
      index = hist.removeLast();
    } else if (!snapshot.shuffle && snapshot.index > 0) {
      index = snapshot.index - 1;
    }
    if (index == null) return;
    final old = currentRef;
    snapshot = QueueSnapshot(
      tracks: snapshot.tracks,
      index: index,
      repeat: snapshot.repeat,
      shuffle: snapshot.shuffle,
      order: snapshot.order,
      history: hist,
    );
    if (old != null) await cache.cancel(old, automaticOnly: true);
    position = Duration.zero;
    cache.invalidatePreview();
    await _loadCurrent(autoplay: true, manual: true);
  }

  Future<void> _finished() async {
    if (snapshot.repeat == RepeatKind.one) {
      await player.seek(Duration.zero);
      await player.play();
      return;
    }
    if (_nextIndex() == null) {
      await pause();
      return;
    }
    await next(manual: false);
  }

  Future<void> _failed(String reason, {bool manual = false}) async {
    if (_userPaused) return;
    if (manual) {
      await pause();
      return;
    }
    final ref = currentRef;
    final proxyFailure = ref == null ? null : proxy.failureFor(ref);
    if (reason.contains('401') ||
        reason.contains('403') ||
        const ['401', '403', 'tls'].contains(proxyFailure) ||
        reason.toLowerCase().contains('certificate')) {
      await pause();
      return;
    }
    if (_recoveryRef != ref) {
      _recoveryRef = ref;
      _reconnects = 0;
    }
    final source = ref == null ? null : await db.source(ref.sourceId);
    final resumeMs = max(position.inMilliseconds, snapshot.positionMs);
    if (source != null &&
        source.enabled &&
        source.kind != SourceKind.local &&
        resumeMs > 0 &&
        _reconnects < 2 &&
        !_userPaused &&
        proxyFailure != '404') {
      _reconnects++;
      position = Duration(milliseconds: resumeMs);
      await save();
      await Future<void>.delayed(Duration(milliseconds: 400 * _reconnects));
      if (currentRef == ref && !_userPaused) {
        await _loadCurrent(autoplay: true, manual: false);
      }
      return;
    }
    failures++;
    if (failures >= 3) {
      error = '连续 3 首歌曲播放失败，已停止自动跳过。最后错误：$reason';
      await pause();
      return;
    }
    if (_nextIndex() == null) {
      await pause();
      return;
    }
    await next(manual: false);
  }

  Future<void> seek(Duration target) async {
    cache.invalidatePreview();
    await player.seek(target);
    position = target;
    await save();
    notifyListeners();
  }

  Future<void> cyclePlaybackMode() =>
      setPlaybackMode(snapshot.playbackMode.next);

  Future<void> setPlaybackMode(PlaybackMode mode) async {
    final shuffle = mode == PlaybackMode.shuffle;
    final indices = List.generate(snapshot.tracks.length, (i) => i);
    var order = indices;
    if (shuffle && snapshot.shuffle) {
      order = snapshot.order;
    } else if (shuffle && indices.isNotEmpty) {
      indices.remove(snapshot.index);
      indices.shuffle(Random());
      indices.insert(0, snapshot.index);
    }
    snapshot = QueueSnapshot(
      tracks: snapshot.tracks,
      index: snapshot.index,
      positionMs: snapshot.positionMs,
      repeat: mode == PlaybackMode.singleLoop ? RepeatKind.one : RepeatKind.all,
      shuffle: shuffle,
      order: order,
      history: snapshot.history,
    );
    cache.invalidatePreview();
    await save();
    notifyListeners();
  }

  Future<void> setRepeat(RepeatKind repeat) => setPlaybackMode(
    repeat == RepeatKind.one
        ? PlaybackMode.singleLoop
        : snapshot.shuffle
        ? PlaybackMode.shuffle
        : PlaybackMode.listLoop,
  );

  Future<void> setShuffle(bool active) => setPlaybackMode(
    active
        ? PlaybackMode.shuffle
        : snapshot.repeat == RepeatKind.one
        ? PlaybackMode.singleLoop
        : PlaybackMode.listLoop,
  );

  Future<void> setSpeed(double v) async {
    speed = v.clamp(0.5, 2);
    await player.setRate(speed);
    await db.setSetting('speed', '$speed');
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    volume = v.clamp(0, 100);
    await player.setVolume(volume);
    await db.setSetting('volume', '$volume');
    notifyListeners();
  }

  Future<void> save() async {
    final next = QueueSnapshot(
      tracks: snapshot.tracks,
      index: snapshot.index,
      positionMs: position.inMilliseconds,
      repeat: snapshot.repeat,
      shuffle: snapshot.shuffle,
      order: snapshot.order,
      history: snapshot.history,
    );
    snapshot = next;
    await db.saveQueue(next);
  }

  Future<void> retry() async {
    failures = 0;
    await save();
    await _loadCurrent(autoplay: true, manual: true);
  }

  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= snapshot.tracks.length) return;
    final old = currentRef;
    if (old != null) await cache.cancel(old, automaticOnly: true);
    snapshot = QueueSnapshot(
      tracks: snapshot.tracks,
      index: index,
      repeat: snapshot.repeat,
      shuffle: snapshot.shuffle,
      order: snapshot.order,
      history: [...snapshot.history, snapshot.index],
    );
    position = Duration.zero;
    failures = 0;
    await _loadCurrent(manual: true);
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= snapshot.tracks.length) return;
    final wasCurrent = index == snapshot.index;
    final wasPlaying = playing;
    final tracks = [...snapshot.tracks]..removeAt(index);
    if (tracks.isEmpty) {
      await clearQueue();
      return;
    }
    final currentIndex = index < snapshot.index
        ? snapshot.index - 1
        : snapshot.index.clamp(0, tracks.length - 1);
    List<int> remap(List<int> items) => [
      for (final i in items)
        if (i != index) i > index ? i - 1 : i,
    ];
    snapshot = QueueSnapshot(
      tracks: tracks,
      index: currentIndex,
      positionMs: wasCurrent ? 0 : position.inMilliseconds,
      repeat: snapshot.repeat,
      shuffle: snapshot.shuffle,
      order: remap(snapshot.order),
      history: remap(snapshot.history),
    );
    if (wasCurrent) {
      position = Duration.zero;
      await _loadCurrent(autoplay: wasPlaying, manual: true);
    }
    await save();
    notifyListeners();
  }

  Future<void> clearQueue() async {
    final ref = currentRef;
    if (ref != null) await cache.cancel(ref, automaticOnly: true);
    await player.stop();
    if (_leased != null) {
      cache.release(_leased!);
      _leased = null;
    }
    snapshot = const QueueSnapshot();
    current = null;
    position = Duration.zero;
    duration = Duration.zero;
    cache.invalidatePreview();
    await save();
    notifyListeners();
    _publish();
  }

  void _publish() {
    final h = handler;
    final t = current;
    if (h == null) return;
    h.mediaItem.add(
      t == null
          ? null
          : MediaItem(
              id: t.ref.key,
              title: t.title,
              artist: t.artist,
              album: t.album,
              duration: Duration(milliseconds: t.durationMs),
            ),
    );
    h.playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        processingState: buffering
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
        playing: playing,
        updatePosition: position,
        speed: speed,
      ),
    );
  }

  @override
  void dispose() {
    if (_leased != null) cache.release(_leased!);
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    unawaited(player.dispose());
    super.dispose();
  }

  Future<void> shutdown() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await save();
    if (_leased != null) {
      cache.release(_leased!);
      _leased = null;
    }
    await player.dispose();
    super.dispose();
  }
}

class SylphyAudioHandler extends BaseAudioHandler with SeekHandler {
  SylphyAudioHandler(this.controller);
  final PlaybackCoordinator controller;
  @override
  Future<void> play() => controller.play();
  @override
  Future<void> pause() => controller.pause();
  @override
  Future<void> stop() => controller.pause();
  @override
  Future<void> skipToNext() => controller.next();
  @override
  Future<void> skipToPrevious() => controller.previous();
  @override
  Future<void> seek(Duration position) => controller.seek(position);
}
