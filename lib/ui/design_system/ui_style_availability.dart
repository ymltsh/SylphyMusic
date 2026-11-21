import 'package:flutter/foundation.dart';

import '../../core/appearance.dart';

/// Compile-time gate: released builds stay on the existing Material 3 UI.
/// Android experimental builds opt in with --dart-define.
class UiStyleAvailability {
  const UiStyleAvailability._();

  static const experimentalMiuix = bool.fromEnvironment(
    'SYLPHY_EXPERIMENTAL_MIUIX',
    defaultValue: false,
  );

  static bool get miuixAvailable =>
      experimentalMiuix &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;

  /// Stored preferences are intentionally never overwritten by this fallback.
  /// Optional inputs make the policy testable without changing the build mode.
  static UiStyle effective(
    UiStyle selected, {
    bool? experimentalEnabled,
    bool? web,
    TargetPlatform? platform,
  }) {
    final enabled = experimentalEnabled ?? experimentalMiuix;
    final isWeb = web ?? kIsWeb;
    final target = platform ?? defaultTargetPlatform;
    return selected == UiStyle.miuix &&
            enabled &&
            !isWeb &&
            target == TargetPlatform.android
        ? UiStyle.miuix
        : UiStyle.material3;
  }
}
