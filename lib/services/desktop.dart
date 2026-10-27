import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'playback.dart';

class DesktopControls {
  DesktopControls(this.playback, this.onQuit);
  final PlaybackCoordinator playback;
  final Future<void> Function() onQuit;
  static const _channel = MethodChannel('music.sylphy/desktop');
  String _published = '';
  Future<void> initialize() async {
    if (!Platform.isWindows) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'play':
          await playback.play();
        case 'pause':
          await playback.pause();
        case 'toggle':
          await playback.toggle();
        case 'next':
          await playback.next();
        case 'previous':
          await playback.previous();
        case 'quit':
          await onQuit();
          exit(0);
      }
    });
    playback.addListener(_update);
    _update();
  }

  void _update() {
    final track = playback.current;
    final key = '${track?.ref.key}/${playback.playing}';
    if (_published == key) return;
    _published = key;
    unawaited(
      _channel
          .invokeMethod<void>('update', {
            'title': track?.title ?? 'Sylphy Music',
            'artist': track?.artist ?? '',
            'album': track?.album ?? '',
            'state': playback.playing ? 'playing' : 'paused',
          })
          .catchError((Object _) {}),
    );
  }

  void dispose() {
    if (!Platform.isWindows) return;
    playback.removeListener(_update);
    _channel.setMethodCallHandler(null);
  }
}
