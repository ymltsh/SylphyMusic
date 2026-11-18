import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/player_layout.dart';

/// Changes only the track painting; Slider owns gestures, focus and semantics.
class PlayerProgressTrackShape extends RoundedRectSliderTrackShape {
  const PlayerProgressTrackShape({
    required this.style,
    required this.amplitude,
    required this.waveLength,
  });

  final PlayerProgressStyle style;
  final double amplitude, waveLength;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (rect.width <= 0 || rect.height <= 0) return;
    final active = Color.lerp(
      sliderTheme.disabledActiveTrackColor,
      sliderTheme.activeTrackColor,
      enableAnimation.value,
    )!;
    final inactive = Color.lerp(
      sliderTheme.disabledInactiveTrackColor,
      sliderTheme.inactiveTrackColor,
      enableAnimation.value,
    )!;
    final thumbX = thumbCenter.dx.clamp(rect.left, rect.right).toDouble();
    final canvas = context.canvas;
    final paint = Paint()
      ..strokeWidth = rect.height
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path();
    if (style == PlayerProgressStyle.wave) {
      for (double x = 0; x < rect.width; x += 1) {
        final absoluteX = rect.left + x;
        // Meet the thumb and track ends on the centre line.
        final taper = math.min(
          1.0,
          math.min(
            x / 10,
            math.min((rect.width - x) / 10, (absoluteX - thumbX).abs() / 10),
          ),
        );
        final y =
            rect.center.dy +
            math.sin(x / waveLength * 2 * math.pi) * amplitude * taper;
        if (x == 0) {
          path.moveTo(absoluteX, y);
        } else {
          path.lineTo(absoluteX, y);
        }
      }
      path.lineTo(rect.right, rect.center.dy);
    } else {
      for (double x = rect.left; x < rect.right; x += 14) {
        path.moveTo(x, rect.center.dy);
        path.lineTo(math.min(x + 8, rect.right), rect.center.dy);
      }
    }
    canvas.drawPath(path, paint..color = inactive);
    canvas.save();
    final activeRect = textDirection == TextDirection.ltr
        ? Rect.fromLTRB(
            rect.left - rect.height,
            rect.top - amplitude - rect.height,
            thumbX,
            rect.bottom + amplitude + rect.height,
          )
        : Rect.fromLTRB(
            thumbX,
            rect.top - amplitude - rect.height,
            rect.right + rect.height,
            rect.bottom + amplitude + rect.height,
          );
    canvas.clipRect(activeRect);
    canvas.drawPath(path, paint..color = active);
    canvas.restore();
  }
}
