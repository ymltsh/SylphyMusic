import 'dart:io';

import 'package:flutter/services.dart';

class SystemNotifications {
  static const _android = MethodChannel('music.sylphy/system_notifications');
  static const _windows = MethodChannel('music.sylphy/desktop');
  static const _permission = MethodChannel(
    'music.sylphy/notification_permission',
  );

  static Future<void> requestPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _permission.invokeMethod<void>('request');
    } on PlatformException {
      // Notification permission must not block sync preferences.
    } on MissingPluginException {
      // No Activity attached.
    }
  }

  static Future<void> syncCompleted(String message) async {
    if (!Platform.isAndroid && !Platform.isWindows) return;
    try {
      await (Platform.isAndroid ? _android : _windows).invokeMethod<void>(
        'syncCompleted',
        {'message': message},
      );
    } on PlatformException {
      // System notification settings must not affect library synchronization.
    } on MissingPluginException {
      // Unsupported host; never fall back to an in-app notice.
    }
  }
}
