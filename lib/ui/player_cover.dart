import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'cover_art.dart';
import 'rotating_cover.dart';

/// The single artwork renderer for the full player, the editor preview, the
/// lyrics page and the collapsed mini player. Shape and rotation are global
/// playback preferences, so every record on screen uses the same vocabulary.
class PlayerCover extends StatelessWidget {
  const PlayerCover({
    super.key,
    required this.app,
    required this.track,
    required this.size,
    required this.circle,
    this.radius = 24,
    this.rotate = false,
    this.playing = false,
    this.preview = false,
    this.shadow = true,
  });
  final SylphyApp app;
  final Track? track;
  final double size;
  final bool circle;
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
    return RotatingCover(
      key: ValueKey(current.ref.key),
      enabled: circle && rotate && !preview,
      playing: playing && !preview,
      child: CoverArt(app: app, track: current, size: side, borderRadius: 0),
    );
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
    if (!circle) {
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
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xff111317),
                boxShadow: shadowStyle,
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
            Container(
              width: size * .045,
              height: size * .045,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xcc111317),
                border: Border.all(
                  color: Colors.white.withValues(alpha: .16),
                  width: size * .0025,
                ),
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
