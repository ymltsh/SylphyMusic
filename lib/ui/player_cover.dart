import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/player_layout.dart';
import 'cover_art.dart';
import 'rotating_cover.dart';

/// The single artwork renderer for the full player, the editor preview, the
/// lyrics page and the collapsed mini player. Full-player elements provide
/// their own style and rotation; compact thumbnails default to rounded covers.
class PlayerCover extends StatelessWidget {
  const PlayerCover({
    super.key,
    required this.app,
    required this.track,
    required this.size,
    this.height,
    this.style = PlayerCoverStyle.rounded,
    this.fadeStart = .5,
    this.fadeDirection = CoverFadeDirection.bottom,
    this.radius = 24,
    this.rotate = false,
    this.playing = false,
    this.preview = false,
    this.shadow = true,
  });
  final SylphyApp app;
  final Track? track;
  final double size;
  final double? height;
  final PlayerCoverStyle style;
  final double fadeStart;
  final CoverFadeDirection fadeDirection;
  final double radius;
  final bool rotate, playing, preview, shadow;

  Widget _art(BuildContext context, double side) {
    final current = track;
    if (current == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Center(
          child: Icon(
            Icons.album_outlined,
            size: (side * .28).clamp(16, 72),
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        ),
      );
    }
    return CoverArt(app: app, track: current, size: side, borderRadius: 0);
  }

  @override
  Widget build(BuildContext context) {
    final shadowStyle = shadow
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: .28),
              blurRadius: size * .12,
              offset: Offset(0, size * .05),
            ),
          ]
        : const <BoxShadow>[];
    if (style == PlayerCoverStyle.immersive) {
      final h = height ?? size;
      final side = math.max(size, h);
      final (begin, end) = switch (fadeDirection) {
        CoverFadeDirection.right => (
          Alignment.centerLeft,
          Alignment.centerRight,
        ),
        CoverFadeDirection.left => (
          Alignment.centerRight,
          Alignment.centerLeft,
        ),
        CoverFadeDirection.bottom => (
          Alignment.topCenter,
          Alignment.bottomCenter,
        ),
        CoverFadeDirection.top => (Alignment.bottomCenter, Alignment.topCenter),
      };
      return Semantics(
        container: true,
        label: '沉浸封面',
        child: SizedBox(
          width: size,
          height: h,
          child: ClipRect(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => LinearGradient(
                begin: begin,
                end: end,
                colors: const [Colors.white, Colors.white, Colors.transparent],
                stops: [0, fadeStart, 1],
              ).createShader(rect),
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox.square(
                    dimension: side,
                    child: _art(context, side),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (style == PlayerCoverStyle.rounded) {
      return Semantics(
        container: true,
        label: '专辑封面',
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: shadowStyle,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: _art(context, size),
          ),
        ),
      );
    }
    final artSize = size * .78;
    return Semantics(
      container: true,
      label: '唱片封面',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: shadowStyle,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            RotatingCover(
              key: ValueKey(track?.ref.key),
              enabled: track != null && rotate && !preview,
              playing: playing && !preview,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: size,
                    height: size,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xff111317),
                    ),
                  ),
                  for (final factor in const [.94, .88])
                    Container(
                      width: size * factor,
                      height: size * factor,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .055),
                          width: size * .0022,
                        ),
                      ),
                    ),
                  ClipOval(
                    child: SizedBox.square(
                      dimension: artSize,
                      child: _art(context, artSize),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: size * .08,
              left: size * .18,
              child: Container(
                width: size * .12,
                height: size * .018,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(size),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
