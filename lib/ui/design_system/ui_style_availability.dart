import 'package:flutter/foundation.dart';

import '../../core/appearance.dart';

/// Platform support for selecting Miuix in Settings.
class UiStyleAvailability {
  const UiStyleAvailability._();

  static bool get miuixAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Stored preferences are intentionally never overwritten by this fallback.
  static UiStyle effective(
    UiStyle selected, {
    bool? web,
    TargetPlatform? platform,
  }) {
    final isWeb = web ?? kIsWeb;
    final target = platform ?? defaultTargetPlatform;
    return selected == UiStyle.miuix &&
            !isWeb &&
            target == TargetPlatform.android
        ? UiStyle.miuix
        : UiStyle.material3;
  }
}
