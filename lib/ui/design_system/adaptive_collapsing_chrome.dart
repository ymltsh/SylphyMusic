import 'dart:math' as math;

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

/// Tints the status bar and fades into the content below the toolbar.
class SylphyGradientHeader extends StatelessWidget {
  const SylphyGradientHeader({super.key, this.solidBackground = false});

  final bool solidBackground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final surface = solidBackground && !dark ? Colors.white : scheme.surface;
    final tint = Color.alphaBlend(
      scheme.primary.withValues(alpha: dark ? .10 : .075),
      surface,
    );
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              tint,
              tint.withValues(alpha: .92),
              tint.withValues(alpha: .62),
              tint.withValues(alpha: 0),
            ],
            stops: const [0, .42, .72, 1],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Gives standalone pages the same title gradient as the main tabs.
AppBar sylphyGradientAppBar({
  Widget? leading,
  Widget? title,
  List<Widget>? actions,
  PreferredSizeWidget? bottom,
}) => AppBar(
  leading: leading,
  title: title,
  actions: actions,
  bottom: bottom,
  flexibleSpace: const SylphyGradientHeader(),
  scrolledUnderElevation: 0,
);

Color _headerControlColor(Color surface, Color accent, bool dark) =>
    Color.alphaBlend(
      accent.withValues(alpha: dark ? .10 : .025),
      surface,
    ).withValues(alpha: dark ? .92 : .98);

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
    final surface = _headerControlColor(
      palette?.surface ?? scheme.surface,
      palette?.primary ?? scheme.primary,
      dark,
    );
    final foreground = palette?.onSurface ?? scheme.onSurface;
    final shape = CircleBorder(
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .45)),
    );
    if (miuix) {
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
                decoration: ShapeDecoration(shape: shape, color: surface),
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
            decoration: ShapeDecoration(shape: shape, color: surface),
            child: InkWell(
              onTap: onPressed,
              customBorder: shape,
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

/// Search and Settings share a pill with two independent hit targets.
class SylphyHeaderActionCapsule extends StatelessWidget {
  const SylphyHeaderActionCapsule({
    super.key,
    required this.onSearch,
    required this.onSettings,
  });

  final VoidCallback onSearch;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final miuix = SylphyMiuixStyle.enabled(context);
    final scheme = Theme.of(context).colorScheme;
    final colors = miuix ? MiuixTheme.of(context).colors : null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = _headerControlColor(
      colors?.surface ?? scheme.surface,
      colors?.primary ?? scheme.primary,
      dark,
    );
    final inkColor = colors?.onSurface ?? scheme.onSurface;
    final outline = scheme.outlineVariant.withValues(alpha: .45);
    final shape = StadiumBorder(side: BorderSide(color: outline));

    Widget action(IconData icon, String label, VoidCallback callback) {
      final glyph = Center(
        child: miuix
            ? MiuixIcon(icon: icon, tint: inkColor, size: 24)
            : Icon(icon, color: inkColor, size: 24),
      );
      return Tooltip(
        message: label,
        child: Semantics(
          label: label,
          button: true,
          child: miuix
              ? MiuixPressable(
                  onPressed: callback,
                  feedbackType: MiuixPressFeedbackType.sink,
                  sinkAmount: .98,
                  shape: const MiuixSquircleBorder(cornerRadius: 22),
                  child: SizedBox.square(dimension: 44, child: glyph),
                )
              : Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: callback,
                    customBorder: const CircleBorder(),
                    child: SizedBox.square(dimension: 44, child: glyph),
                  ),
                ),
        ),
      );
    }

    return DecoratedBox(
      key: const ValueKey('sylphy-header-action-capsule'),
      decoration: ShapeDecoration(shape: shape, color: surface),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          action(Icons.search_rounded, '搜索', onSearch),
          action(Icons.settings_rounded, '设置', onSettings),
        ],
      ),
    );
  }
}

/// Reserves width as More appears while keeping the toolbar height fixed.
class SylphyFoldedHeaderSlot extends StatelessWidget {
  const SylphyFoldedHeaderSlot({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0, end: visible ? 1 : 0),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240),
    curve: Curves.easeOutCubic,
    child: visible
        ? Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: child,
          )
        : null,
    builder: (context, progress, child) {
      // Unmounting the anchor dismisses any open menu when the toolbar expands.
      if (child == null || progress == 0) {
        return SizedBox(width: 52 * progress);
      }
      return ClipRect(
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: progress,
          heightFactor: 1,
          child: Opacity(
            opacity: progress,
            child: Transform.scale(scale: .8 + .2 * progress, child: child),
          ),
        ),
      );
    },
  );
}

/// Both themes use the same size/cross-fade animation; only child surfaces
/// differ. AnimatedCrossFade animates the toolbar height, not just its alpha.
class SylphyAnimatedToolbar extends StatelessWidget {
  const SylphyAnimatedToolbar({
    super.key,
    required this.collapsed,
    required this.expanded,
    required this.compact,
  });

  final bool collapsed;
  final Widget expanded;
  final Widget compact;

  @override
  Widget build(BuildContext context) => AnimatedCrossFade(
    firstChild: expanded,
    secondChild: compact,
    crossFadeState: collapsed
        ? CrossFadeState.showSecond
        : CrossFadeState.showFirst,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 320),
    firstCurve: Curves.easeInOutCubic,
    secondCurve: Curves.easeInOutCubic,
    sizeCurve: Curves.easeInOutCubic,
    alignment: Alignment.topCenter,
    excludeBottomFocus: true,
  );
}

/// Hysteresis smooths short reversals and avoids flicker near the threshold.
/// This is owned by SylphyShell, never by a song row or ScrollController.
class SylphyToolbarScrollTracker {
  double _run = 0;
  int _direction = 0;

  void reset() {
    _run = 0;
    _direction = 0;
  }

  bool? observe({
    required bool folded,
    required double scrollOffset,
    required double scrollDelta,
  }) {
    if (scrollOffset <= 12) {
      reset();
      return folded ? false : null;
    }
    if (!folded && scrollOffset < 56) {
      reset();
      return null;
    }
    if (scrollDelta == 0) return null;
    final direction = scrollDelta > 0 ? 1 : -1;
    if (direction != _direction) {
      _direction = direction;
      _run = 0;
    }
    _run += scrollDelta.abs();
    final threshold = folded ? 28.0 : 24.0;
    if (_run < threshold || (folded ? direction > 0 : direction < 0)) {
      return null;
    }
    reset();
    return !folded;
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
    final media = MediaQuery.of(context);
    const screenMargin = 16.0;
    final availableWidth =
        media.size.width - media.viewPadding.horizontal - 2 * screenMargin;
    final menuWidth = math.min(
      64 + 10 * media.textScaler.scale(14),
      math.max(0.0, availableWidth),
    );
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
          animated: !media.disableAnimations,
          crossAxisUnconstrained: false,
          reservedPadding: const EdgeInsets.symmetric(
            horizontal: screenMargin,
            vertical: 8,
          ),
          // Offset the full panel width from the anchor's trailing edge.
          alignmentOffset: Offset(-menuWidth, 6),
          style: menuStyle.copyWith(
            alignment: AlignmentDirectional.bottomEnd,
            fixedSize: WidgetStatePropertyAll(Size.fromWidth(menuWidth)),
          ),
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
