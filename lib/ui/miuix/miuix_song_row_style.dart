import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// Miuix visual tokens for dense, virtualized music rows. They deliberately
/// change neither ListTile geometry nor scroll / playback behavior.
class MiuixSongRowStyle {
  const MiuixSongRowStyle._();

  static const double coverRadius = 12;

  static Color highlight(
    MiuixColors colors, {
    required bool current,
    required bool selectedInBatch,
  }) {
    if (selectedInBatch) {
      return colors.primaryContainer.withValues(alpha: .72);
    }
    if (current) {
      return colors.primaryContainer.withValues(alpha: .38);
    }
    return Colors.transparent;
  }
}

/// Retains existing PopupMenuButton callbacks and items but uses Miuix shape,
/// surface and text colors. This avoids creating per-row popup controllers.
class MiuixSongMenuTheme extends StatelessWidget {
  const MiuixSongMenuTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return PopupMenuTheme(
      data: PopupMenuThemeData(
        color: colors.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: colors.onSurface),
        shape: const MiuixSquircleBorder(cornerRadius: 20),
        elevation: 3,
      ),
      child: child,
    );
  }
}
