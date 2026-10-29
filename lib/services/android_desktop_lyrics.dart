import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/appearance.dart';
import '../core/models.dart';
import 'lyrics.dart';
import 'playback.dart';

/// Optional Android SYSTEM_ALERT_WINDOW overlay. Playback and lyrics stay in
/// the existing audio_service-owned Dart engine; no extra player is created.
class AndroidDesktopLyrics with WidgetsBindingObserver {
  AndroidDesktopLyrics({
    required this.playback,
    required this.appearance,
    required this.loadLyrics,
  });

  final PlaybackCoordinator playback;
  final Appearance appearance;
  final Future<String?> Function(Track) loadLyrics;
  static const _channel = MethodChannel('music.sylphy/desktop_lyrics');
  bool _initialized = false;
  bool _closed = false;
  bool _awaitingPermission = false;
  bool _shown = false;
  Timer? _throttle;
  TrackRef? _ref;
  int _generation = 0;
  List<LrcLine> _lines = [];
  bool _lyricsLoaded = false;
  String? _plainLyrics;
  String? _lastText;
  int? _lastColor;
  double? _lastFontSize;
  Future<void> _operations = Future.value();

  bool get supported => Platform.isAndroid;

  Future<void> initialize() async {
    if (!supported || _initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'dismissed') {
        _shown = false;
        await appearance.update(desktopLyricsEnabled: false);
      }
    });
    playback.addListener(_schedule);
    appearance.addListener(_schedule);
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  Future<bool> setEnabled(bool enabled) async {
    if (!supported) return false;
    if (enabled && await _channel.invokeMethod<bool>('permission') != true) {
      _awaitingPermission = true;
      await _channel.invokeMethod<void>('requestPermission');
      return false;
    }
    _awaitingPermission = false;
    await appearance.update(desktopLyricsEnabled: enabled);
    _schedule();
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingPermission) {
      unawaited(_grantAfterReturn());
    }
  }

  Future<void> _grantAfterReturn() async {
    try {
      if (await _channel.invokeMethod<bool>('permission') == true) {
        _awaitingPermission = false;
        if (!_closed) await setEnabled(true);
      }
    } catch (_) {
      // The user can retry from Settings if Android denies the permission.
    }
  }

  @override
  void didChangePlatformBrightness() => _schedule();

  void _schedule() {
    if (_closed || !_initialized || _throttle != null) return;
    _throttle = Timer(const Duration(milliseconds: 160), () {
      _throttle = null;
      _operations = _operations.then((_) => _sync()).catchError((Object _) {});
    });
  }

  Future<void> _sync() async {
    if (_closed) return;
    final track = playback.current;
    // A restored queue is not a request to show an overlay on app startup.
    if (!appearance.desktopLyricsEnabled ||
        track == null ||
        (!playback.playing && playback.player.state.playlist.medias.isEmpty)) {
      _generation++;
      _ref = null;
      _lines = [];
      _lyricsLoaded = false;
      _plainLyrics = null;
      await _hide();
      return;
    }
    if (_ref != track.ref) {
      _ref = track.ref;
      _lines = [];
      _lyricsLoaded = false;
      _plainLyrics = null;
      final generation = ++_generation;
      unawaited(_readLyrics(track, generation));
    }
    final active = activeLrcIndex(_lines, playback.position);
    final text = active >= 0 && _lines[active].text.trim().isNotEmpty
        ? _lines[active].text.trim()
        : (!_lyricsLoaded
              ? '正在读取歌词…'
              : (_lines.isEmpty ? (_plainLyrics ?? '暂无可同步歌词') : '♪'));
    final color = appearance.desktopLyricColorMode == LyricColorMode.fixed
        ? appearance.desktopLyricFixedColor
        : PlatformDispatcher.instance.platformBrightness == Brightness.dark
        ? const Color(0xffe9f0ef)
        : const Color(0xff17252a);
    // Android StandardMessageCodec must decode this as a signed Int, not Long.
    final argb = color.toARGB32().toSigned(32);
    final fontSize = appearance.desktopLyricFontSize;
    if (_shown &&
        _lastText == text &&
        _lastColor == argb &&
        _lastFontSize == fontSize)
      return;
    try {
      // Permission can have been revoked outside the app.
      if (await _channel.invokeMethod<bool>('permission') != true) {
        await appearance.update(desktopLyricsEnabled: false);
        await _hide();
        return;
      }
      if (_closed ||
          !appearance.desktopLyricsEnabled ||
          playback.currentRef != track.ref)
        return;
      await _channel.invokeMethod<void>('show', {
        'text': text,
        'color': argb,
        'fontSize': fontSize,
      });
      _shown = true;
      _lastText = text;
      _lastColor = argb;
      _lastFontSize = fontSize;
    } catch (_) {
      // Never interrupt media playback on an overlay/window-manager failure.
      await _hide();
    }
  }

  Future<void> _readLyrics(Track track, int generation) async {
    try {
      final text = await loadLyrics(track);
      if (_closed || generation != _generation || _ref != track.ref) return;
      _lines = parseLrc(text ?? '');
      _lyricsLoaded = true;
      final plain = (text ?? '').trim();
      _plainLyrics = _lines.isEmpty && plain.isNotEmpty
          ? plain.split(RegExp(r'\r?\n')).first.trim()
          : null;
      _schedule();
    } catch (_) {
      if (_closed || generation != _generation || _ref != track.ref) return;
      _lines = [];
      _lyricsLoaded = true;
      _plainLyrics = null;
      _schedule();
    }
  }

  Future<void> _hide() async {
    if (!_shown) return;
    _shown = false;
    _lastText = null;
    _lastColor = null;
    _lastFontSize = null;
    try {
      await _channel.invokeMethod<void>('hide');
    } catch (_) {}
  }

  Future<void> shutdown() async {
    _closed = true;
    _generation++;
    _throttle?.cancel();
    if (!_initialized) return;
    playback.removeListener(_schedule);
    appearance.removeListener(_schedule);
    WidgetsBinding.instance.removeObserver(this);
    await _operations;
    await _hide();
    _channel.setMethodCallHandler(null);
  }
}
