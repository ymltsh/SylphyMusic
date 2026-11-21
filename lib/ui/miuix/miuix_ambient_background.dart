import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/appearance.dart';
import '../app_background.dart';

/// A subtle HyperOS-inspired atmosphere behind the *existing* content.
/// User-supplied wallpaper always wins, and this widget never decodes artwork.
class MiuixAmbientBackground extends StatelessWidget {
  const MiuixAmbientBackground({
    super.key,
    required this.appearance,
    this.enabled = true,
    required this.child,
  });

  final Appearance appearance;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Keep the Scaffold at the same depth while the background changes.
    final showGradient =
        enabled &&
        !appearance.solidBackground &&
        appearance.backgroundFile == null;
    final dark =
        showGradient && Theme.of(context).brightness == Brightness.dark;
    final primary = showGradient ? MiuixTheme.of(context).colors.primary : null;

    return AppBackground(
      appearance: appearance,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (primary != null) ...[
            // Shader-only gradients: no full-screen blur or artwork caching.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: dark
                        ? const [
                            Color(0xFF111A30),
                            Color(0xFF1D2340),
                            Color(0xFF161C28),
                          ]
                        : const [
                            Color(0xFFF4F7FF),
                            Color(0xFFE0E9FF),
                            Color(0xFFECE8FB),
                          ],
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.88, 0.68),
                    radius: 1.0,
                    colors: [
                      primary.withValues(alpha: dark ? 0.21 : 0.23),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.92, -0.52),
                    radius: 0.95,
                    colors: [
                      const Color(0xFFB89BF6)
                          .withValues(alpha: dark ? 0.16 : 0.27),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
          child,
        ],
      ),
    );
  }
}
