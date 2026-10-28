import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Heartbeats report Dart event-loop activity, never source or song content.
class NativeHeartbeat {
  NativeHeartbeat(this.channel);
  final MethodChannel channel;
  Timer? _timer;
  void start() {
    stop();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(
        channel.invokeMethod<void>('heartbeat').catchError((Object _) {}),
      );
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

Future<void> recordDartStartup() async {
  if (!Platform.isAndroid) return;
  const channel = MethodChannel('music.sylphy/engine_lifecycle');
  for (var i = 0; i < 20; i++) {
    try {
      await channel.invokeMethod<void>('dart_started');
      return;
    } on MissingPluginException {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    } on PlatformException {
      return;
    }
  }
}
