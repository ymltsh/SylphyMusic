import 'package:flutter/material.dart';

import '../core/appearance.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({
    super.key,
    required this.appearance,
    required this.child,
  });
  final Appearance? appearance;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final solid = appearance?.solidBackground ?? false;
    final file = solid ? null : appearance?.backgroundFile;
    final solidColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.black
        : Colors.white;
    final themedSurface = Theme.of(context).colorScheme.surface;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: solid ? solidColor : themedSurface),
        if (file != null) ...[
          Image.file(
            file,
            key: ValueKey(file.path),
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => ColoredBox(color: themedSurface),
          ),
          ColoredBox(
            color: themedSurface.withValues(
              alpha: 1 - appearance!.backgroundVisibility,
            ),
          ),
        ],
        child,
      ],
    );
  }
}
