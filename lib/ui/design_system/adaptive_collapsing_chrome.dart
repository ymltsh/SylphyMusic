import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import 'miuix_adaptive.dart';

/// Shared MD3/Miuix toolbar interaction. Positive delta means moving down
/// through the list; negative delta means scrolling back toward the top.
/// This never owns a ScrollController or modifies the library's SQL paging.
bool? sylphyToolbarFoldDecision({
  required bool folded,
  required double scrollOffset,
  required double scrollDelta,
}) {
  if (scrollOffset <= 12) return folded ? false : null;
  if (!folded && scrollOffset >= 56 && scrollDelta >= 3) return true;
  if (folded && scrollDelta <= -4) return false;
  return null;
}

/// The same subtle header wash applies to MD3 and Miuix, but the color tokens
/// come from the current style. The shell avoids drawing over user wallpaper.
class SylphyGradientHeader extends StatelessWidget {
  const SylphyGradientHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final miuix = SylphyMiuixStyle.enabled(context);
    final scheme = Theme.of(context).colorScheme;
    final palette = miuix ? MiuixTheme.of(context).colors : null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = palette?.primary ?? scheme.primary;
    final surface = palette?.surface ?? scheme.surface;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [
              accent.withValues(alpha: dark ? .15 : .11),
              surface.withValues(alpha: dark ? .09 : .06),
              Colors.transparent,
            ],
            stops: const [0, .52, 1],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Same hit target and action semantics in both styles. Only the surface,
/// icon renderer and press response differ.
class SylphyHeaderAction extends StatelessWidget {
  const SylphyHeaderAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final miuix = SylphyMiuixStyle.enabled(context);
    final scheme = Theme.of(context).colorScheme;
    final palette = miuix ? MiuixTheme.of(context).colors : null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = palette?.surfaceContainer ?? scheme.surfaceContainer;
    final accent = palette?.primaryContainer ?? scheme.primaryContainer;
    final foreground = palette?.onSurface ?? scheme.onSurface;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        surface.withValues(alpha: dark ? .75 : .86),
        accent.withValues(alpha: dark ? .37 : .28),
      ],
    );
    if (miuix) {
      const shape = MiuixSquircleBorder(cornerRadius: 22);
      return Tooltip(
        message: tooltip,
        child: Semantics(
          label: tooltip,
          button: true,
          child: MiuixPressable(
            onPressed: onPressed,
            shape: shape,
            feedbackType: MiuixPressFeedbackType.sink,
            sinkAmount: .97,
            child: SizedBox.square(
              dimension: 44,
              child: DecoratedBox(
                decoration: ShapeDecoration(shape: shape, gradient: gradient),
                child: Center(
                  child: MiuixIcon(icon: icon, tint: foreground, size: 24),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        button: true,
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(22),
            ),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(22),
              child: SizedBox.square(
                dimension: 44,
                child: Icon(icon, color: foreground, size: 24),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One More menu with the same actions for both styles. The shell and
/// LibraryBrowser supply callbacks, so it never owns business state.
class SylphyFoldedMoreMenu extends StatelessWidget {
  const SylphyFoldedMoreMenu({
    super.key,
    required this.items,
    this.tooltip = '更多操作',
  });

  final List<Widget> items;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final miuix = SylphyMiuixStyle.enabled(context);
    final palette = miuix ? MiuixTheme.of(context).colors : null;
    final scheme = Theme.of(context).colorScheme;
    final surface = palette?.surfaceContainer ?? scheme.surfaceContainer;
    final foreground = palette?.onSurface ?? scheme.onSurface;
    // Flutter MenuAnchor requires an OutlinedBorder, not Miuix's
    // ShapeBorder-only squircle; use the same rounded popup geometry in both.
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
    );
    final menuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(surface),
      shape: WidgetStatePropertyAll(shape),
      elevation: const WidgetStatePropertyAll(10),
    );
    final inheritedButtonStyle = MenuButtonTheme.of(context).style;
    final buttonStyle = ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? null : foreground,
      ),
    );
    return MenuButtonTheme(
      data: MenuButtonThemeData(
        style: inheritedButtonStyle?.merge(buttonStyle) ?? buttonStyle,
      ),
      child: MenuTheme(
        data: MenuThemeData(style: menuStyle),
        child: MenuAnchor(
          style: menuStyle,
          menuChildren: items,
          builder: (context, controller, _) => KeyedSubtree(
            key: const ValueKey('sylphy-folded-more'),
            child: SylphyHeaderAction(
              icon: Icons.more_horiz_rounded,
              tooltip: tooltip,
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
          ),
        ),
      ),
    );
  }
}
