import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/appearance.dart';

ThemeData sylphyTheme(Appearance? appearance, Brightness brightness) {
  final seed = appearance?.seed ?? Appearance.defaultSeed;
  final generated = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );
  final whiteContrast = 1.05 / (seed.computeLuminance() + .05);
  final dark = brightness == Brightness.dark;
  // The dark palette follows the charcoal layers used by modern music apps.
  // Keep the user's seed as the accent, not as the background colour.
  final scheme = generated.copyWith(
    primary: seed,
    onPrimary: whiteContrast >= 4.5 ? Colors.white : const Color(0xff101214),
    surface: dark ? const Color(0xff0f1417) : null,
    surfaceDim: dark ? const Color(0xff0f1417) : null,
    surfaceBright: dark ? const Color(0xff343e43) : null,
    surfaceContainerLowest: dark ? const Color(0xff12191d) : null,
    surfaceContainerLow: dark ? const Color(0xff1c2023) : null,
    surfaceContainer: dark ? const Color(0xff22292d) : null,
    surfaceContainerHigh: dark ? const Color(0xff2b3135) : null,
    surfaceContainerHighest: dark ? const Color(0xff323b40) : null,
    onSurface: dark ? const Color(0xffe7ebee) : null,
    onSurfaceVariant: dark ? const Color(0xffb0bac0) : null,
    outlineVariant: dark ? const Color(0xff424c52) : null,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
