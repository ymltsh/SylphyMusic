import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/player_layout.dart';
import 'cover_art.dart';

/// Shared atmosphere for the live player and layout preview. It follows the
/// active light/dark theme and the global solid-background preference; the
/// blurred cover is deliberately opt-in through the ambient switch.
class PlayerBackdrop extends StatelessWidget {
  const PlayerBackdrop({
    super.key,
    required this.app,
    required this.track,
    this.background = PlayerBackground.album,
    this.opacity = .65,
  });
  final SylphyApp app;
  final Track? track;
  final PlayerBackground background;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final base = app.appearance.solidBackground
        ? (light ? Colors.white : Colors.black)
        : scheme.surface;
    final coverBlur =
        background == PlayerBackground.album &&
        app.appearance.ambient &&
        track != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: base),
        if (background == PlayerBackground.gradient)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.primaryContainer.withValues(alpha: .88),
                  scheme.surface,
                  scheme.secondaryContainer.withValues(alpha: .82),
                ],
                stops: const [0, .52, 1],
              ),
            ),
          ),
        if (coverBlur)
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 500),
                child: Opacity(
                  key: ValueKey('${track!.ref.key}/${track!.artworkVersion}'),
                  opacity: opacity,
                  child: SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: CoverArt(app: app, track: track!, size: 640),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (coverBlur)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: light
                    ? [
                        Colors.white.withValues(alpha: .42),
                        scheme.surface.withValues(alpha: .34),
                        Colors.white.withValues(alpha: .78),
                      ]
                    : [
                        Colors.black.withValues(alpha: .52),
                        scheme.surface.withValues(alpha: .46),
                        Colors.black.withValues(alpha: .86),
                      ],
                stops: const [0, .42, 1],
              ),
            ),
          ),
      ],
    );
  }
}
