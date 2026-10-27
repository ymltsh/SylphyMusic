import 'package:flutter/widgets.dart';

/// Locale-aware product name used in the in-app title and MaterialApp title.
/// Keep this in sync with android/app/src/main/res/values*/strings.xml.
///
/// The app UI is currently Chinese-first and does not install a full
/// localizations delegate set, so use the platform locale rather than the
/// MaterialApp resolved locale.
String appDisplayName() =>
    WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'en'
    ? 'Sylphy Music'
    : '风灵音乐';
