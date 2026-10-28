import 'dart:io';

import 'package:flutter/services.dart';

/// Notification-backed, user-triggered Android dataSync session.
/// The persistent FlutterEngine belongs to SylphyApplication, not MainActivity.
class SyncForeground {
  SyncForeground(this.onInterrupted, {bool? android})
    : _android = android ?? Platform.isAndroid {
    if (_android) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'pause' ||
            call.method == 'timeout' ||
            call.method == 'unavailable') {
          _interrupted = true;
          onInterrupted();
        }
      });
    }
  }

  static const _channel = MethodChannel('music.sylphy/sync_lifecycle');
  static const _permission = MethodChannel(
    'music.sylphy/notification_permission',
  );
  final void Function() onInterrupted;
  final bool _android;
  bool _interrupted = false;
  bool _running = false;
  DateTime? _lastUpdate;
  String? _lastMessage;

  Future<void> start() async {
    if (!_android) return;
    if (_running) throw StateError('已有一项前台同步任务');
    _interrupted = false;
    // Android 13+ notification permission is optional for an FGS, but prompt
    // while the user is in-app so the progress notification can be visible.
    try {
      await _permission.invokeMethod<void>('request');
    } on MissingPluginException {
      // No Activity attached: start may still be rejected by Android.
    }
    _running = true;
    try {
      await _channel.invokeMethod<void>('start');
      var ready = false;
      for (var i = 0; i < 60 && !_interrupted; i++) {
        ready = await _channel.invokeMethod<bool>('status') ?? false;
        if (ready) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (!ready || _interrupted) throw StateError('前台同步服务未能启动，请回到应用后重试');
    } catch (_) {
      await stop();
      rethrow;
    }
    _lastUpdate = null;
    _lastMessage = null;
  }

  Future<void> update(
    String title,
    String detail, {
    int done = 0,
    int total = 0,
    bool force = false,
  }) async {
    if (!_android || !_running) return;
    final now = DateTime.now();
    final message = '$title/$detail/$done/$total';
    if (!force &&
        _lastUpdate != null &&
        now.difference(_lastUpdate!) < const Duration(milliseconds: 700)) {
      return;
    }
    if (!force && message == _lastMessage) return;
    _lastUpdate = now;
    _lastMessage = message;
    try {
      await _channel.invokeMethod<void>('update', {
        'title': title,
        'detail': detail,
        'done': done,
        'total': total,
      });
    } on PlatformException {
      // A notification update failure must not corrupt an in-progress index.
    }
  }

  Future<void> stop() async {
    if (!_android || !_running) return;
    _running = false;
    try {
      await _channel.invokeMethod<void>('stop');
      for (var i = 0; i < 20; i++) {
        if (await _channel.invokeMethod<bool>('status') != true) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    } on PlatformException {
      // Timeout / user pause may already have removed the Service.
    }
  }

  void dispose() {
    if (_android) _channel.setMethodCallHandler(null);
  }
}
