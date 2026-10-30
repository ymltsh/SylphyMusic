import 'dart:io';

import 'package:flutter/services.dart';

/// Android-only embedded OpenList. Other platforms never call the channel.
/// A fixed localhost WebDAV URL is deliberately a different source from a
/// remote OpenList instance: only localhost:10486/dav is managed by us.
class OpenListLite {
  OpenListLite._();
  static const String baseUrl = 'http://127.0.0.1:10486';
  static const String webDavUsername = 'sylphy';
  static const String webDavPassword = 'sylphy';
  static const String webDavUrl = '$baseUrl/dav/';
  static const MethodChannel _channel = MethodChannel(
    'music.sylphy/openlist_lite',
  );

  static bool manages(Uri uri) =>
      Platform.isAndroid &&
      uri.scheme == 'http' &&
      uri.host == '127.0.0.1' &&
      uri.port == 10486 &&
      (uri.path == '/dav' || uri.path.startsWith('/dav/'));

  /// Preserve source/track identity when upgrading the embedded server port.
  static String? upgradedLegacyUrl(String text) {
    if (!Platform.isAndroid) return null;
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.host != '127.0.0.1' ||
        uri.port != 5244 ||
        uri.userInfo.isNotEmpty ||
        (uri.path != '/dav' && !uri.path.startsWith('/dav/')))
      return null;
    return uri.replace(port: 10486).toString();
  }

  static bool managesUrl(String text) {
    final uri = Uri.tryParse(text);
    return uri != null && manages(uri);
  }

  static Future<void> ensureFor(Uri uri) async {
    if (manages(uri)) await _channel.invokeMethod<String>('ensure');
  }

  static Future<void> acquirePlayback(String sourceUrl) async {
    if (!managesUrl(sourceUrl)) return;
    await _channel.invokeMethod<String>('acquire', {'key': 'playback'});
  }

  static Future<void> releasePlayback() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('release', {'key': 'playback'});
  }

  static Future<void> acquireTask(String sourceUrl, String key) async {
    if (!managesUrl(sourceUrl)) return;
    await _channel.invokeMethod<String>('acquire', {'key': key});
  }

  static Future<void> releaseTask(String sourceUrl, String key) async {
    if (!managesUrl(sourceUrl)) return;
    await _channel.invokeMethod<void>('release', {'key': key});
  }

  static Future<void> acquireScan(String sourceUrl, String id) async {
    if (!managesUrl(sourceUrl)) return;
    await _channel.invokeMethod<String>('acquire', {'key': 'scan:$id'});
  }

  static Future<void> releaseScan(String sourceUrl, String id) async {
    if (!managesUrl(sourceUrl)) return;
    await _channel.invokeMethod<void>('release', {'key': 'scan:$id'});
  }

  static Future<Map<String, dynamic>> status() async {
    if (!Platform.isAndroid) return {'running': false, 'mode': 'smart'};
    final values = await _channel.invokeMapMethod<String, dynamic>('status');
    return values ?? {'running': false, 'mode': 'smart'};
  }

  static Future<void> shutdown() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('shutdown');
  }

  static Future<void> setEnabled(bool enabled) async {
    await _channel.invokeMethod<void>('enabled', {'value': enabled});
  }

  static Future<void> setMode(String mode) async {
    if (!{'smart', 'continuous'}.contains(mode))
      throw ArgumentError.value(mode);
    await _channel.invokeMethod<String>('mode', {'value': mode});
  }

  static Future<void> openUi() async {
    await _channel.invokeMethod<void>('openUi');
  }

  static Future<String> adminPassword() async =>
      await _channel.invokeMethod<String>('adminPassword') ?? '';
}
