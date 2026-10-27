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
  final scheme = generated.copyWith(
    primary: seed,
    onPrimary: whiteContrast >= 4.5 ? Colors.white : const Color(0xff101214),
  );
  final dark = brightness == Brightness.dark;
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
