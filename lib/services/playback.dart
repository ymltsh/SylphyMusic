import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import '../core/models.dart';
import '../data/app_db.dart';
import 'artwork.dart';
import 'cache.dart';
import 'diagnostic_logs.dart';
import 'media_proxy.dart';

/// Metadata sent to Android must include an actual artwork URI; the platform
/// cannot access Flutter's in-widget Image.file cache automatically.
MediaItem mediaItemForTrack(Track track, {Uri? artUri}) => MediaItem(
  id: track.ref.key,
  title: track.title,
  artist: track.artist,
  album: track.album,
  duration: Duration(milliseconds: track.durationMs),
  artUri: artUri,
);

class PlaybackCoordinator extends ChangeNotifier {
  PlaybackCoordinator(this.db, this.proxy, this.cache, {this.diagnostics});
  final AppDb db;
  final MediaProxy proxy;
  final CacheManager cache;
  final DiagnosticLogs? diagnostics;
  final Player player = Player();
  QueueSnapshot snapshot = const QueueSnapshot();
  Track? current;
  bool playing = false, buffering = false;
  // Play intent must survive the native player's between-track false events.
  // audio_service uses PlaybackState.playing to keep the Android FGS alive.
  bool _playRequested = false;
  Duration position = Duration.zero, duration = Duration.zero;
  String? error;
  int failures = 0;
  double speed = 1.0;
  double volume = 100;
  bool _opening = false, _userPaused = false;
  bool _handlingFailure = false;
  bool _finishingTrack = false;
  // GAIN is not permission to restart immediately: video feeds can briefly
  // release focus between clips. Keep resume eligibility separate from focus.
  bool _resumeOnFocusGain = false;
  bool _focusWasLost = false;
  bool _ducking = false;
  TrackRef? _focusResumeRef;
  Timer? _focusResumeTimer;
  int _focusResumeEpoch = 0;
  DateTime? _focusBurstStarted;
  int _focusLossCount = 0;
  static const _focusResumeDelay = Duration(seconds: 2);
  static const _focusChatterWindow = Duration(seconds: 12);
  static const _focusResumeMaxAge = Duration(seconds: 15);
  int _lastSaved = 0;
  int _reconnects = 0;
  TrackRef? _recoveryRef;
  AudioSession? _session;
  // Sample the actual mpv AO once per track, after audio advances.
  bool _androidAudioOutputProbed = false;
  TrackRef? _leased;
  final Set<String> _reloadSources = {};
  Future<String?> Function(Track)? _lyricsLoader;
  final Set<TrackRef> _lyricsWarmupRequested = {};
  Future<File?> Function(Track)? _artworkLoader;
  final Set<TrackRef> _artworkWarmupRequested = {};
  String? _aheadPlan;
  int _aheadGeneration = 0;
  final Set<TrackRef> _aheadDownloads = {};

  // Track *actual position advancement*, not just the player's playing flag.
  // A libmpv stream can remain buffering without ever emitting stream.error.
  final Stopwatch _progressWatch = Stopwatch()..start();
  Timer? _stallTimer;
  int? _lastWatchdogTickMs;
  int _playIntentGeneration = 0;
  int _watchdogPositionMs = -1;
  int _loadGeneration = 0;
  bool _stalledRecoveryRunning = false;
  bool _openStallLogged = false;
  bool _transitionStallLogged = false;

  void _checkForStall() {
    if (!_playRequested ||
        _userPaused ||
        currentRef == null ||
        _handlingFailure ||
        _stalledRecoveryRunning) {
      return;
    }
    if (_finishingTrack) {
      if (!_transitionStallLogged &&
          _progressWatch.elapsed >= const Duration(seconds: 50)) {
        _transitionStallLogged = true;
        diagnostics?.record('playback', 'transition_stalled');
      }
      return;
    }
    if (_opening) {
      // Diagnostics only: Future.timeout does NOT cancel a native player.open.
      // Opening recovery requires serializing/cancelling the native operation.
      if (!_openStallLogged &&
          _progressWatch.elapsed >= const Duration(seconds: 50)) {
        _openStallLogged = true;
        diagnostics?.record('playback', 'open_stalled');
      }
      return;
    }
    if (_progressWatch.elapsed < const Duration(seconds: 45)) return;

    final stuckRef = currentRef;
    final generation = _loadGeneration;
    final intentGeneration = _playIntentGeneration;
    _stalledRecoveryRunning = true;
    _handlingFailure = true;
    diagnostics?.record(
      'playback',
      'progress_stalled',
      details: {'index': snapshot.index},
    );
    error = '播放进度长时间没有变化，正在尝试恢复';
    notifyListeners();
    unawaited(_recoverStall(stuckRef, generation, intentGeneration));
  }

  bool _sameRecovery(TrackRef? ref, int generation, int intentGeneration) =>
      currentRef == ref &&
      _loadGeneration == generation &&
      _playIntentGeneration == intentGeneration &&
      _playRequested &&
      !_userPaused;

  Future<void> _recoverStall(
    TrackRef? stuckRef,
    int generation,
    int intentGeneration,
  ) async {
    try {
      if (!_sameRecovery(stuckRef, generation, intentGeneration)) return;
      // A responsive local listener does not imply the Emby upstream is
      // healthy. Never restart the proxy on every buffering event.
      diagnostics?.record('playback', 'local_proxy_probe_started');
      final healthy = await proxy.ping();
      diagnostics?.record(
        'playback',
        healthy ? 'local_proxy_healthy' : 'local_proxy_unresponsive',
      );
      if (!_sameRecovery(stuckRef, generation, intentGeneration)) return;
      if (!healthy) {
        try {
          await proxy.restart();
        } catch (_) {
          // _failed still applies the bounded retry/stop policy below.
        }
      }
      if (!_sameRecovery(stuckRef, generation, intentGeneration)) return;
      await _failed('播放进度超过 45 秒没有变化');
    } catch (_) {
      // The recovery attempt is best effort; never leave the guard latched.
      diagnostics?.record('playback', 'stall_recovery_failed');
    } finally {
      _handlingFailure = false;
      _stalledRecoveryRunning = false;
      _progressWatch.reset();
    }
  }

  /// Install the app-owned lyrics loader after its stores/settings are ready.
  /// The current track may already have been restored during initialization.
  void setLyricsLoader(Future<String?> Function(Track) loader) {
    _lyricsLoader = loader;
    final track = current;
    if (track != null) _warmLyrics(track);
  }

  /// Warm the same persistent artwork store used by widgets and SystemUI.
  void setArtworkLoader(Future<File?> Function(Track) loader) {
    _artworkLoader = loader;
    final track = current;
    if (track != null) _warmArtwork(track);
  }

  void _warmArtwork(Track track) {
    final loader = _artworkLoader;
    if (loader == null || !_artworkWarmupRequested.add(track.ref)) return;
    unawaited(
      Future<File?>.sync(() => loader(track))
          .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  void _warmLyrics(Track track) {
    final loader = _lyricsLoader;
    if (loader == null || !_lyricsWarmupRequested.add(track.ref)) return;
    // Lyrics are best-effort background work: a failed lookup must not affect
    // opening or playing the audio, and must not become an unhandled error.
    unawaited(
      Future<String?>.sync(() => loader(track))
          .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  void invalidateSource(String id) {
    _reloadSources.add(id);
    _lyricsWarmupRequested.removeWhere((ref) => ref.sourceId == id);
    _artworkWarmupRequested.removeWhere((ref) => ref.sourceId == id);
    // Source cancellation is owned by the app's source lifecycle.
    _aheadPlan = null;
    ++_aheadGeneration;
  }

  SylphyAudioHandler? handler;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  // The Android media session needs its own image URI in addition to the
  // Flutter UI's CoverArt widget. Keep the cached file leased while current.
  ArtworkStore? _notificationArtwork;
  Track? _notificationArtworkTrack;
  String? _notificationArtworkKey;
  Uri? _notificationArtUri;
  int _notificationArtworkRequest = 0;
  ({
    String id,
    String title,
    String artist,
    String album,
    int durationMs,
    Uri? artUri,
  })?
  _lastMediaItem;

  void _cancelFocusResume({
    bool keepEligibility = false,
    bool resetBurst = false,
  }) {
    ++_focusResumeEpoch;
    _focusResumeTimer?.cancel();
    _focusResumeTimer = null;
    if (!keepEligibility) {
      _resumeOnFocusGain = false;
      _focusResumeRef = null;
    }
    if (resetBurst) {
      _focusBurstStarted = null;
      _focusLossCount = 0;
    }
  }

  Future<void> _applyPlayerVolume() =>
      player.setVolume(volume * (_ducking ? 0.25 : 1.0));

  Future<void> _abandonAudioFocus() async {
    if (_session == null) return;
    try {
      await _session!.setActive(false);
    } catch (_) {
      // Cleanup must not fail if Android has already reclaimed the session.
      diagnostics?.record('audio_focus', 'release_failed');
    }
  }

  void _onAudioInterruption(AudioInterruptionEvent event) {
    diagnostics?.record(
      'audio_focus',
      'interruption',
      details: {
        'state': event.begin ? 'begin' : 'end',
        'type': event.type.name,
      },
    );
    if (event.begin) {
      // A new loss always cancels a pending timer. A second rapid loss also
      // cancels the right to auto-resume, preventing clip-to-clip oscillation.
      _cancelFocusResume(
        keepEligibility: event.type == AudioInterruptionType.pause,
      );
      if (event.type == AudioInterruptionType.duck) {
        _ducking = true;
        unawaited(_applyPlayerVolume());
        return;
      }
      if (_ducking) {
        _ducking = false;
        unawaited(_applyPlayerVolume());
      }

      _focusWasLost = true;
      final wasRequested = _playRequested; // Includes buffering and track open.
      if (event.type == AudioInterruptionType.pause) {
        if (wasRequested || _resumeOnFocusGain) {
          final now = DateTime.now();
          if (_focusBurstStarted == null ||
              now.difference(_focusBurstStarted!) > _focusChatterWindow) {
            _focusBurstStarted = now;
            _focusLossCount = 0;
          }
          ++_focusLossCount;
          if (_focusLossCount >= 2) {
            _cancelFocusResume();
            diagnostics?.record('audio_focus', 'resume_suppressed');
          } else if (wasRequested) {
            _resumeOnFocusGain = true;
            _focusResumeRef = currentRef;
          }
        }
      } else {
        // audio_session maps permanent AUDIOFOCUS_LOSS to `unknown`.
        // It must never create an automatic resume entitlement.
        _cancelFocusResume();
      }
      if (wasRequested) unawaited(pause(system: true));
      return;
    }

    if (event.type == AudioInterruptionType.duck) {
      _ducking = false;
      unawaited(_applyPlayerVolume());
      return;
    }
    _focusWasLost = false;
    if (event.type != AudioInterruptionType.pause ||
        !_resumeOnFocusGain ||
        _userPaused) {
      return;
    }
    final resumeRef = _focusResumeRef;
    if (resumeRef == null) {
      _cancelFocusResume();
      return;
    }
    final focusEpoch = _focusResumeEpoch;
    final intentGeneration = _playIntentGeneration;
    final loadGeneration = _loadGeneration;
    final gainTime = DateTime.now();
    _focusResumeTimer?.cancel();
    _focusResumeTimer = Timer(_focusResumeDelay, () {
      _focusResumeTimer = null;
      if (focusEpoch != _focusResumeEpoch ||
          _focusWasLost ||
          !_resumeOnFocusGain ||
          _userPaused ||
          _playRequested ||
          currentRef != resumeRef ||
          _playIntentGeneration != intentGeneration ||
          _loadGeneration != loadGeneration ||
          DateTime.now().difference(gainTime) > _focusResumeMaxAge) {
        _cancelFocusResume();
        return;
      }
      _cancelFocusResume();
      diagnostics?.record('audio_focus', 'resume_after_stable_gain');
      unawaited(play(automaticFocusResume: true));
    });
  }

  // Prefer Android AudioTrack with OpenSL ES
  // fallback. Do not change network caching, focus or the output buffer here.
  Future<void> _configureAndroidAudioOutput() async {
    if (!Platform.isAndroid) return;
    final native = player.platform;
    if (native is! NativePlayer) {
      diagnostics?.record('playback', 'audio_output_native_unavailable');
      return;
    }
    try {
      // media_kit may ignore mpv error codes: this records only the request.
      await native.setProperty('ao', 'audiotrack,opensles,');
      diagnostics?.record('playback', 'audio_output_override_requested');
    } catch (_) {
      // Keep the package's default output backend if the override fails.
      diagnostics?.record('playback', 'audio_output_override_failed');
    }
  }

  Future<void> _probeAndroidAudioOutput() async {
    if (!Platform.isAndroid || _androidAudioOutputProbed) return;
    _androidAudioOutputProbed = true;
    final native = player.platform;
    if (native is! NativePlayer) return;
    try {
      // Unlike the requested `ao`, `current-ao` reports the actual driver.
      final actual = await native.getProperty('current-ao');
      const known = {'audiotrack', 'aaudio', 'opensles', 'null'};
      final driver = known.contains(actual)
          ? actual
          : (actual.isEmpty ? 'unavailable' : 'other');
      diagnostics?.record(
        'playback',
        'audio_output_selected',
        details: {'type': driver},
      );
    } catch (_) {
      diagnostics?.record('playback', 'audio_output_probe_failed');
    }
  }

  Future<void> initialize() async {
    snapshot = await db.queue();
    speed = double.tryParse(await db.setting('speed') ?? '1') ?? 1;
    volume = double.tryParse(await db.setting('volume') ?? '100') ?? 100;
    await player.setRate(speed);
    await player.setVolume(volume);
    await _configureAndroidAudioOutput();
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
        diagnostics?.record(
          'playback',
          'playing_changed',
          details: {'playing': v},
        );
        cache.updatePlaybackPriority(active: v, buffering: buffering);
        notifyListeners();
        _publish();
      }),
    );
    _subscriptions.add(
      player.stream.buffering.listen((v) {
        buffering = v;
        diagnostics?.record(
          'playback',
          'buffering_changed',
          details: {'buffering': v},
        );
        // A temporary stall must not discard valid ahead-track preview data.
        cache.updatePlaybackPriority(active: playing, buffering: v);
        notifyListeners();
        _publish();
      }),
    );
    _subscriptions.add(
      player.stream.position.listen((v) {
        final nextMs = v.inMilliseconds;
        if (Platform.isAndroid &&
            playing &&
            !_androidAudioOutputProbed &&
            nextMs >= 500) {
          unawaited(_probeAndroidAudioOutput());
        }
        if (nextMs > _watchdogPositionMs + 400) {
          _watchdogPositionMs = nextMs;
          _progressWatch.reset();
        }
        if (error != null && playing && !buffering && v > position) {
          error = null;
        }
        position = v;
        if (v >= const Duration(seconds: 5)) failures = 0;
        notifyListeners();
        _publish();
        final now = DateTime.now().millisecondsSinceEpoch;
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
        if (done && !_opening && !_finishingTrack && !_stalledRecoveryRunning) {
          diagnostics?.record(
            'playback',
            'track_completed',
            details: {'index': snapshot.index},
          );
          _finishingTrack = true;
          _transitionStallLogged = false;
          _progressWatch.reset();
          _publish();
          unawaited(
            _finished().whenComplete(() {
              _finishingTrack = false;
              _publish();
            }),
          );
        }
      }),
    );
    _subscriptions.add(
      player.stream.error.listen((e) {
        diagnostics?.record('playback', 'player_error');
        error = e;
        notifyListeners();
        if (!_opening && !_handlingFailure) {
          _handlingFailure = true;
          unawaited(_failed(e).whenComplete(() => _handlingFailure = false));
        }
      }),
    );
    _stallTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final previous = _lastWatchdogTickMs;
      _lastWatchdogTickMs = now;
      if (previous != null && now - previous > 15000) {
        // A delayed Dart timer alone does not prove the process was killed.
        diagnostics?.record(
          'playback',
          'dart_timer_delayed',
          details: {'gap_ms': now - previous},
        );
      }
      _checkForStall();
    });
    await _prepareCurrent(); // Restore metadata only, never autoplay after process restart.
    if (Platform.isAndroid) {
      _session = await AudioSession.instance;
      await _session!.configure(const AudioSessionConfiguration.music());
      _subscriptions.add(
        _session!.interruptionEventStream.listen(_onAudioInterruption),
      );
      _subscriptions.add(
        _session!.becomingNoisyEventStream.listen((_) {
          _cancelFocusResume();
          _focusWasLost = false;
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
    diagnostics?.record('android', 'media_service_initializing');
    handler = await AudioService.init(
      builder: () => SylphyAudioHandler(this),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'music.sylphy.playback',
        androidNotificationChannelName: 'Sylphy Music',
        androidNotificationOngoing: true,
      ),
    );
    diagnostics?.record('android', 'media_service_ready');
    _publish();
  }

  /// Connect the same authenticated, on-disk artwork cache used by the UI.
  /// Network artwork URLs are intentionally not exposed to Android SystemUI.
  void attachNotificationArtwork(ArtworkStore artwork) {
    if (_notificationArtwork != null) {
      throw StateError('媒体通知封面已经初始化');
    }
    _notificationArtwork = artwork;
    artwork.assets.addListener(_onNotificationArtworkChanged);
    _publish();
  }

  void _onNotificationArtworkChanged() {
    final store = _notificationArtwork;
    final track = current;
    final change = store?.assets.lastChange;
    if (store == null ||
        track == null ||
        change == null ||
        change.sourceId != track.ref.sourceId ||
        change.key != store.key(track)) {
      return;
    }
    _requestNotificationArtwork(track);
  }

  void _syncNotificationArtwork(Track? track) {
    final key = track == null
        ? null
        : '${track.ref.key}/${track.artworkVersion}';
    if (_notificationArtworkKey == key) return;

    final previous = _notificationArtworkTrack;
    if (previous != null) _notificationArtwork?.release(previous);
    _notificationArtworkTrack = track;
    _notificationArtworkKey = key;
    _notificationArtUri = null;
    // Invalidate outstanding loads from the previous song.
    ++_notificationArtworkRequest;

    if (track != null && _notificationArtwork != null) {
      _notificationArtwork!.retain(track);
      _requestNotificationArtwork(track);
    }
  }

  void _requestNotificationArtwork(Track track) {
    final store = _notificationArtwork;
    if (store == null) return;
    final request = ++_notificationArtworkRequest;
    unawaited(_loadNotificationArtwork(store, track, request));
  }

  Future<void> _loadNotificationArtwork(
    ArtworkStore store,
    Track track,
    int request,
  ) async {
    try {
      final file = await store.load(track);
      if (request != _notificationArtworkRequest) return;
      final uri = file != null && await file.exists() ? file.uri : null;
      if (request != _notificationArtworkRequest) return;
      if (_notificationArtUri != uri) {
        _notificationArtUri = uri;
        _publish();
      }
    } catch (_) {
      // Missing/unavailable artwork must never interrupt audio playback.
    }
  }

  void _detachNotificationArtwork() {
    ++_notificationArtworkRequest;
    final store = _notificationArtwork;
    if (store != null) {
      store.assets.removeListener(_onNotificationArtworkChanged);
      final retained = _notificationArtworkTrack;
      if (retained != null) store.release(retained);
    }
    _notificationArtwork = null;
    _notificationArtworkTrack = null;
    _notificationArtworkKey = null;
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
    if (current != null) {
      _warmLyrics(current!);
      _warmArtwork(current!);
    }
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
    _cancelFocusResume(resetBurst: true);
    _focusWasLost = false;
    if (autoplay) _userPaused = false;
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
    _cancelAhead();
    cache.beginQueueSession();
    failures = 0;
    await save();
    await _loadCurrent(autoplay: autoplay, manual: true);
  }

  Future<void> _loadCurrent({bool autoplay = true, bool manual = false}) async {
    diagnostics?.record(
      'playback',
      'load_started',
      details: {
        'index': snapshot.index,
        'queue_size': snapshot.tracks.length,
        'autoplay': autoplay,
        'manual': manual,
      },
    );
    _opening = true;
    _playRequested = autoplay;
    _androidAudioOutputProbed = false;
    ++_loadGeneration;
    _watchdogPositionMs = -1;
    _openStallLogged = false;
    _progressWatch.reset();
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
      _warmLyrics(current!);
      _warmArtwork(current!);
      diagnostics?.record(
        'playback',
        'source_resolved',
        details: {'source_kind': source.kind.name},
      );
      // Start/retain the media playback foreground service *before* opening
      // the next URL or requesting audio focus in the background.
      _publish();
      if (autoplay &&
          _playRequested &&
          _session != null &&
          !await _session!.setActive(true)) {
        // Focus denial is not a broken media source. Do not skip tracks.
        _playRequested = false;
        error = '系统暂时未授予音频焦点';
        notifyListeners();
        _publish();
        return;
      }
      cache.lease(ref);
      _leased = ref;
      diagnostics?.record('playback', 'player_opening');
      final shouldPlay = autoplay && _playRequested;
      if (source.kind == SourceKind.local) {
        final f = File(current!.remote['path']?.toString() ?? ref.id);
        if (!await f.exists()) throw StateError('本地原始音频文件不存在');
        diagnostics?.record('playback', 'native_open_started');
        await player.open(Media(f.uri.toString()), play: shouldPlay);
      } else {
        final cached = await cache.find(ref, touch: true);
        final uri = cached != null
            ? cached.file.uri
            : proxy.ticket(current!, source);
        diagnostics?.record(
          'playback',
          cached == null ? 'remote_ticket_open' : 'cached_file_open',
        );
        diagnostics?.record('playback', 'native_open_started');
        await player.open(Media(uri.toString()), play: shouldPlay);
      }
      diagnostics?.record('playback', 'player_opened');
      _watchdogPositionMs = position.inMilliseconds;
      _progressWatch.reset();
      if (resumeMs > 0) {
        await player.seek(Duration(milliseconds: resumeMs));
      }
      // A pause can arrive while the async track opening was in flight.
      if (!_playRequested) await player.pause();
      // Never infer a USER pause from _playRequested: audio focus may have
      // paused us while player.open was still awaiting native preparation.
      diagnostics?.record('playback', 'load_finished');
      _reloadSources.remove(source.id);
      notifyListeners();
      _publish();
      await save();
      _scheduleAhead();
    } catch (e) {
      diagnostics?.record(
        'playback',
        'load_failed',
        details: {'type': e.runtimeType.toString()},
      );
      error = e.toString();
      notifyListeners();
      if (autoplay && _playRequested) {
        await _failed(error!, manual: manual);
      }
    } finally {
      _opening = false;
      _publish();
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
    _scheduleAhead();
  }

  /// Follow actual play order, including a deterministic list-loop wrap.
  /// Shuffle creates a new order at wrap time, so its future order is unknown.
  List<int> _aheadIndices() {
    if (snapshot.repeat == RepeatKind.one || snapshot.tracks.length < 2) {
      return const [];
    }
    final order = snapshot.order.length == snapshot.tracks.length
        ? snapshot.order
        : List.generate(snapshot.tracks.length, (i) => i);
    final at = order.indexOf(snapshot.index);
    if (at < 0) return const [];
    final indices = <int>[];
    for (var step = 1; step <= 2 && step < order.length; step++) {
      final offset = at + step;
      if (offset >= order.length &&
          (snapshot.repeat != RepeatKind.all || snapshot.shuffle)) {
        break;
      }
      indices.add(order[offset % order.length]);
    }
    return indices;
  }

  void _cancelAhead() {
    ++_aheadGeneration;
    _aheadPlan = null;
    for (final ref in _aheadDownloads.toList()) {
      unawaited(cache.cancel(ref, automaticOnly: true));
    }
    _aheadDownloads.clear();
  }

  void _scheduleAhead() {
    if (!_playRequested || currentRef == null) return;
    final indices = _aheadIndices();
    final targets = [
      for (final index in indices) TrackRef.parse(snapshot.tracks[index]),
    ];
    final key = '${currentRef!.key}/${targets.map((t) => t.key).join('/')}';
    if (_aheadPlan == key) return;
    _aheadPlan = key;
    final generation = ++_aheadGeneration;
    final keep = <TrackRef>{currentRef!, ...targets};
    for (final ref in _aheadDownloads.toList()) {
      if (keep.contains(ref)) continue;
      _aheadDownloads.remove(ref);
      unawaited(cache.cancel(ref, automaticOnly: true));
    }
    if (indices.isNotEmpty) unawaited(_warmAhead(indices, generation));
  }

  Future<void> _warmAhead(List<int> indices, int generation) async {
    final ready = <({Track track, SourceProfile source})>[];
    // Warm the first two covers and lyrics before downloading either audio.
    for (final index in indices) {
      if (generation != _aheadGeneration) return;
      try {
        final track = await db.track(TrackRef.parse(snapshot.tracks[index]));
        if (generation != _aheadGeneration) return;
        if (track == null) continue;
        final source = await db.source(track.ref.sourceId);
        if (generation != _aheadGeneration) return;
        if (source == null || !source.enabled) continue;
        _warmArtwork(track);
        _warmLyrics(track);
        if (source.kind != SourceKind.local && !track.missing) {
          ready.add((track: track, source: source));
        }
      } catch (_) {
        // Optional warming must never interrupt playback.
      }
    }
    // P1 is a verified whole-file cache. P2 only consumes bandwidth after P1.
    for (var rank = 0; rank < ready.length; rank++) {
      if (generation != _aheadGeneration || !_playRequested) return;
      final item = ready[rank];
      _aheadDownloads.add(item.track.ref);
      try {
        await cache.fetchWhole(item.track, item.source, automatic: true);
        diagnostics?.record(
          'playback',
          'ahead_audio_ready',
          details: {'rank': rank + 1},
        );
      } catch (_) {
        diagnostics?.record(
          'playback',
          'ahead_audio_failed',
          details: {'rank': rank + 1},
        );
        if (rank == 0 && generation == _aheadGeneration) {
          // Strict whole-file validation may fail on a Range-only server.
          unawaited(
            cache.prefetchNext(
              item.track,
              item.source,
              planId: '${_aheadPlan ?? ''}/${item.track.ref.key}',
            ),
          );
        }
      }
    }
  }

  Future<void> play({bool automaticFocusResume = false}) async {
    if (!automaticFocusResume) {
      _cancelFocusResume(resetBurst: true);
      _focusWasLost = false;
    }
    final focusEpoch = _focusResumeEpoch;
    final intentGeneration = ++_playIntentGeneration;
    diagnostics?.record('playback', 'play_requested');
    _userPaused = false;
    if (current == null) await _prepareCurrent();
    if (current == null) return;
    final requestedRef = currentRef;
    final source = await db.source(current!.ref.sourceId);
    if (intentGeneration != _playIntentGeneration ||
        currentRef != requestedRef ||
        (automaticFocusResume &&
            (focusEpoch != _focusResumeEpoch ||
                _focusWasLost ||
                _userPaused))) {
      return;
    }
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
    _playRequested = true;
    _progressWatch.reset();
    _publish();
    if (_session != null && !await _session!.setActive(true)) {
      _playRequested = false;
      _publish();
      error = '系统暂时未授予音频焦点';
      notifyListeners();
      return;
    }
    if (automaticFocusResume &&
        (focusEpoch != _focusResumeEpoch || _focusWasLost || _userPaused)) {
      _playRequested = false;
      _publish();
      return;
    }
    if (_playRequested && intentGeneration == _playIntentGeneration) {
      await player.play();
      // Reassert a focus pause if it arrived during the native play Future.
      if (automaticFocusResume && !_playRequested) await player.pause();
      if (_playRequested) _scheduleAhead();
    }
  }

  Future<void> pause({bool system = false}) async {
    if (!system) {
      _cancelFocusResume(resetBurst: true);
      _userPaused = true;
    }
    ++_playIntentGeneration;
    diagnostics?.record(
      'playback',
      'pause_requested',
      details: {'system': system},
    );
    _playRequested = false;
    // Allow a resume to continue unfinished ahead warming.
    _aheadPlan = null;
    ++_aheadGeneration;
    _publish();
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
    if (manual) {
      _cancelFocusResume(resetBurst: true);
      _focusWasLost = false;
      _userPaused = false;
    }
    diagnostics?.record(
      'playback',
      'next_requested',
      details: {'manual': manual, 'index': snapshot.index},
    );
    // Automatic continuation must not override a pause during a transition.
    if (!manual && !_playRequested) return;
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
    await _loadCurrent(autoplay: manual || _playRequested, manual: manual);
  }

  Future<void> previous() async {
    if (snapshot.tracks.isEmpty) return;
    _cancelFocusResume(resetBurst: true);
    _focusWasLost = false;
    _userPaused = false;
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
    diagnostics?.record('playback', 'finish_handler_started');
    if (!_playRequested) return;
    if (snapshot.repeat == RepeatKind.one) {
      await player.seek(Duration.zero);
      if (_playRequested) await player.play();
      return;
    }
    if (_nextIndex() == null) {
      await pause();
      return;
    }
    await next(manual: false);
  }

  Future<void> _failed(String reason, {bool manual = false}) async {
    diagnostics?.record(
      'playback',
      'recovery_started',
      details: {'manual': manual, 'attempt': _reconnects},
    );
    if (_userPaused || !_playRequested) return;
    if (manual) {
      await pause();
      return;
    }
    final ref = currentRef;
    final recoveryGeneration = _loadGeneration;
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
    if (_loadGeneration != recoveryGeneration ||
        currentRef != ref ||
        !_playRequested ||
        _userPaused) {
      return;
    }
    final resumeMs = max(position.inMilliseconds, snapshot.positionMs);
    if (source != null &&
        source.enabled &&
        source.kind != SourceKind.local &&
        resumeMs > 0 &&
        _reconnects < 2 &&
        !_userPaused &&
        _playRequested &&
        proxyFailure != '404') {
      _reconnects++;
      if (ref != null) await cache.cancel(ref, automaticOnly: true);
      diagnostics?.record(
        'playback',
        'reconnect_attempt',
        details: {'attempt': _reconnects},
      );
      position = Duration(milliseconds: resumeMs);
      await save();
      await Future<void>.delayed(Duration(milliseconds: 400 * _reconnects));
      if (currentRef == ref &&
          _loadGeneration == recoveryGeneration &&
          !_userPaused &&
          _playRequested) {
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
    ++_playIntentGeneration;
    _watchdogPositionMs = target.inMilliseconds;
    _progressWatch.reset();
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
    _scheduleAhead();
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
    await _applyPlayerVolume();
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
    _cancelFocusResume(resetBurst: true);
    _focusWasLost = false;
    _userPaused = false;
    failures = 0;
    await save();
    await _loadCurrent(autoplay: true, manual: true);
  }

  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= snapshot.tracks.length) return;
    _cancelFocusResume(resetBurst: true);
    _focusWasLost = false;
    _userPaused = false;
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
    if (wasCurrent) _cancelFocusResume(resetBurst: true);
    final wasPlaying = _playRequested;
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
    if (!wasCurrent) _scheduleAhead();
  }

  Future<void> clearQueue() async {
    _cancelFocusResume(resetBurst: true);
    _focusWasLost = false;
    ++_playIntentGeneration;
    diagnostics?.record('playback', 'queue_cleared');
    _playRequested = false;
    _cancelAhead();
    _publish();
    final ref = currentRef;
    if (ref != null) await cache.cancel(ref, automaticOnly: true);
    await player.stop();
    await _abandonAudioFocus();
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
    _syncNotificationArtwork(t);
    if (t == null) {
      if (_lastMediaItem != null) {
        h.mediaItem.add(null);
        _lastMediaItem = null;
      }
    } else {
      final metadata = (
        id: t.ref.key,
        title: t.title,
        artist: t.artist,
        album: t.album,
        durationMs: t.durationMs,
        artUri: _notificationArtUri,
      );
      // Don't resend metadata on every position tick; update only when the
      // song, its visible metadata, or its downloaded artwork changes.
      if (_lastMediaItem != metadata) {
        _lastMediaItem = metadata;
        h.mediaItem.add(mediaItemForTrack(t, artUri: _notificationArtUri));
      }
    }
    h.playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          _playRequested ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        processingState: buffering || _opening || _finishingTrack
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
        // The OS must not leave foreground service between two tracks.
        // Real user/system pause still sets this to false immediately.
        playing: _playRequested,
        updatePosition: position,
        speed: speed,
      ),
    );
  }

  @override
  void dispose() {
    _cancelFocusResume();
    _cancelAhead();
    _stallTimer?.cancel();
    _stallTimer = null;
    _detachNotificationArtwork();
    if (_leased != null) cache.release(_leased!);
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    unawaited(player.dispose());
    super.dispose();
  }

  Future<void> shutdown() async {
    _cancelFocusResume();
    _stallTimer?.cancel();
    _stallTimer = null;
    _playRequested = false;
    _cancelAhead();
    _lyricsLoader = null;
    _lyricsWarmupRequested.clear();
    _artworkLoader = null;
    _artworkWarmupRequested.clear();
    _publish();
    _detachNotificationArtwork();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _abandonAudioFocus();
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

  // Audio focus and noisy-device events use system:true and never come through
  // this gate. Only external MediaSession transport commands are rate-limited;
  // the in-app UI can always use PlaybackCoordinator directly.
  static const _transportQuietMs = 800;
  static const _transportBurstLimit = 6;
  final Stopwatch _transportClock = Stopwatch()..start();
  int? _lastTransportMs;
  int _transportBurstCount = 0;
  bool _transportStorm = false;

  bool _allowTransport(String type) {
    final now = _transportClock.elapsedMilliseconds;
    final last = _lastTransportMs;
    if (last == null || now - last > _transportQuietMs) {
      _transportBurstCount = 0;
      _transportStorm = false;
    }
    _lastTransportMs = now;
    if (_transportStorm) return false;
    if (++_transportBurstCount > _transportBurstLimit) {
      _transportStorm = true;
      controller.diagnostics?.record(
        'media_control',
        'transport_storm',
        details: {'type': type},
      );
      // Fail safe: stop the audible oscillation and keep ignoring repeated
      // commands until the accessory/OS has been quiet for 800 ms.
      unawaited(controller.pause().catchError((Object _) {}));
      return false;
    }
    controller.diagnostics?.record(
      'media_control',
      'transport_command',
      details: {'type': type},
    );
    return true;
  }

  @override
  Future<void> play() =>
      _allowTransport('play') ? controller.play() : Future<void>.value();

  @override
  Future<void> pause() =>
      _allowTransport('pause') ? controller.pause() : Future<void>.value();

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    if (button == MediaButton.media) {
      if (!_allowTransport('toggle')) return;
      // Play intent updates synchronously, while native `playing` can lag.
      if (controller._playRequested) {
        await controller.pause();
      } else {
        await controller.play();
      }
    } else if (button == MediaButton.next) {
      await controller.next();
    } else if (button == MediaButton.previous) {
      await controller.previous();
    }
  }

  // Stop must remain available even in a transport-command storm.
  @override
  Future<void> stop() => controller.pause();
  @override
  Future<void> skipToNext() => controller.next();
  @override
  Future<void> skipToPrevious() => controller.previous();
  @override
  Future<void> seek(Duration position) => controller.seek(position);
}
