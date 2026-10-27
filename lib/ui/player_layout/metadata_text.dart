import 'package:flutter/material.dart';

/// Fits complete lines inside the frame shared by playback and the editor.
class PlayerMetadataText extends StatelessWidget {
  const PlayerMetadataText({
    super.key,
    required this.text,
    required this.style,
    required this.alignment,
    required this.textAlign,
    this.maxLines = 1,
  });

  final String text;
  final TextStyle style;
  final Alignment alignment;
  final TextAlign textAlign;
  final int maxLines;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      final locale = Localizations.maybeLocaleOf(context);
      final painter = TextPainter(
        text: TextSpan(text: text, style: effectiveStyle),
        textDirection: direction,
        textAlign: textAlign,
        textScaler: scaler,
        locale: locale,
        ellipsis: '…',
      );
      var lines = maxLines;
      // Measure the actual font and accessibility scale rather than assuming
      // that fontSize is the line height. Never leave a partial second line.
      while (true) {
        painter.maxLines = lines;
        painter.layout(maxWidth: constraints.maxWidth);
        if (painter.height <= constraints.maxHeight || lines == 1) break;
        lines--;
      }
      painter.dispose();
      return Tooltip(
        message: text,
        excludeFromSemantics: true,
        child: ClipRect(
          child: Align(
            alignment: alignment,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: alignment,
              child: SizedBox(
                width: constraints.maxWidth,
                child: Text(
                  text,
                  maxLines: lines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: textAlign,
                  textScaler: scaler,
                  locale: locale,
                  style: effectiveStyle,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
