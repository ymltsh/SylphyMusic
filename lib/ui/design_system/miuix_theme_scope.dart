import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/appearance.dart';
import 'miuix_adaptive.dart';
import 'ui_style_availability.dart';

/// Supplies a Miuix theme to the existing Navigator without creating another
/// MaterialApp. The nested Material theme provides compatible colors to pages
/// that have not yet been migrated to native Miuix widgets.
class MiuixThemeScope extends StatelessWidget {
  const MiuixThemeScope({
    super.key,
    required this.appearance,
    required this.child,
  });

  final Appearance appearance;
  final Widget child;

  static MiuixColorSchemeMode schemeMode(ThemeMode mode) => switch (mode) {
    ThemeMode.system => MiuixColorSchemeMode.monetSystem,
    ThemeMode.light => MiuixColorSchemeMode.monetLight,
    ThemeMode.dark => MiuixColorSchemeMode.monetDark,
  };

  @override
  Widget build(BuildContext context) {
    if (!UiStyleAvailability.miuixAvailable) return child;

    final useMiuix =
        UiStyleAvailability.effective(appearance.uiStyle) == UiStyle.miuix;
    final scopedChild = SylphyMiuixStyle(active: useMiuix, child: child);
    // Keep the Navigator and system bars mounted when the selection changes.
    return MiuixThemeController(
      colorSchemeMode: useMiuix
          ? schemeMode(appearance.mode)
          : MiuixColorSchemeMode.system,
      keyColor: appearance.seed,
      child: Builder(
        builder: (context) {
          final old = Theme.of(context);
          if (!useMiuix) return Theme(data: old, child: scopedChild);

          final colors = MiuixTheme.of(context).colors;
          final colorScheme = old.colorScheme.copyWith(
            primary: colors.primary,
            onPrimary: colors.onPrimary,
            primaryContainer: colors.primaryContainer,
            onPrimaryContainer: colors.onPrimaryContainer,
            secondary: colors.secondary,
            onSecondary: colors.onSecondary,
            surface: colors.surface,
            onSurface: colors.onSurface,
            surfaceContainer: colors.surfaceContainer,
            surfaceContainerHigh: colors.surfaceContainerHigh,
            surfaceContainerHighest: colors.surfaceContainerHighest,
            outline: colors.outline,
          );
          return Theme(
            data: old.copyWith(
              colorScheme: colorScheme,
              scaffoldBackgroundColor: colors.surface,
              // Temporary M3 compatibility while content migrates to Miuix.
              cardTheme: old.cardTheme.copyWith(
                color: colors.surfaceContainer.withValues(alpha: .92),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              appBarTheme: old.appBarTheme.copyWith(
                backgroundColor: colors.surface,
                foregroundColor: colors.onSurface,
              ),
            ),
            child: scopedChild,
          );
        },
      ),
    );
  }
}
