import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../miuix/miuix_iconography.dart';

/// Reports the effective selection while the theme bridge stays mounted.
class SylphyMiuixStyle extends InheritedWidget {
  const SylphyMiuixStyle({
    super.key,
    required this.active,
    required super.child,
  });

  final bool active;

  static bool enabled(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SylphyMiuixStyle>()?.active ??
      false;

  @override
  bool updateShouldNotify(SylphyMiuixStyle oldWidget) =>
      active != oldWidget.active;

  static ShapeBorder cardShape(
    BuildContext context, {
    required double cornerRadius,
  }) => enabled(context)
      ? MiuixSquircleBorder(cornerRadius: cornerRadius)
      : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
        );

  /// An InputDecoration compatible with the existing TextField and its
  /// controller, debounce and submit callbacks. No new search state is created.
  static InputDecoration searchDecoration(
    BuildContext context, {
    required String hintText,
    Widget? suffixIcon,
  }) {
    if (!enabled(context)) {
      return InputDecoration(
        hintText: hintText,
        border: InputBorder.none,
        suffixIcon: suffixIcon,
      );
    }
    final colors = MiuixTheme.of(context).colors;
    const pillBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(999)),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      hintText: hintText,
      prefixIcon: Icon(
        Icons.search_rounded,
        color: colors.onSurfaceVariantSummary,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: colors.surfaceContainer,
      border: pillBorder,
      enabledBorder: pillBorder,
      focusedBorder: pillBorder,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    );
  }
}

/// A tinted squircle icon with the caller's existing Material treatment.
class SylphyAdaptiveQuickIcon extends StatelessWidget {
  const SylphyAdaptiveQuickIcon({
    super.key,
    required this.icon,
    required this.materialIcon,
    this.compact = false,
  });

  final IconData icon;
  final Widget materialIcon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!SylphyMiuixStyle.enabled(context)) return materialIcon;

    final primary = MiuixTheme.of(context).colors.primary;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: primary.withValues(alpha: .10),
        shape: const MiuixSquircleBorder(cornerRadius: 14),
      ),
      child: SizedBox.square(
        dimension: compact ? 38 : 46,
        child: MiuixIcon(
          icon: SylphyMiuixIconography.rounded(icon),
          tint: primary,
          size: compact ? 20 : 24,
        ),
      ),
    );
  }
}

/// Use native MiuixCard to restyle a section without changing its children,
/// their callbacks, or the original page's grid/list arrangement.
class SylphyAdaptiveCard extends StatelessWidget {
  const SylphyAdaptiveCard({
    super.key,
    required this.child,
    this.cornerRadius = 24,
    this.materialFilled = false,
    this.materialOutlined = false,
  }) : assert(!(materialFilled && materialOutlined));

  final Widget child;
  final double cornerRadius;
  final bool materialFilled;
  final bool materialOutlined;

  @override
  Widget build(BuildContext context) {
    if (!SylphyMiuixStyle.enabled(context)) {
      if (materialFilled) {
        return Card.filled(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: child,
        );
      }
      if (materialOutlined) {
        return Card.outlined(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: child,
        );
      }
      return Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: child,
      );
    }
    final shape = MiuixSquircleBorder(cornerRadius: cornerRadius);
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: MiuixCard(
        cornerRadius: cornerRadius,
        // Put settings tiles' ink above the Miuix surface.
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}

/// Replacement for a plain InkWell whose child owns no tap or long press.
/// Keeps the supplied child layout unchanged in both styles.
class SylphyAdaptivePressable extends StatelessWidget {
  const SylphyAdaptivePressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.cornerRadius = 16,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    if (!SylphyMiuixStyle.enabled(context) || onTap == null) {
      return InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(cornerRadius),
        child: child,
      );
    }
    return MiuixPressable(
      onPressed: onTap,
      onLongPress: onLongPress,
      feedbackType: MiuixPressFeedbackType.sink,
      // Song rows and grid cards must not shrink by the library's default 6%.
      sinkAmount: 0.98,
      shape: MiuixSquircleBorder(cornerRadius: cornerRadius),
      child: child,
    );
  }
}

/// Only adds a gesture in Miuix mode. Use this when the Material child
/// (e.g. ListTile) already handles taps and must keep its original InkWell.
class SylphyMiuixPressable extends StatelessWidget {
  const SylphyMiuixPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.cornerRadius = 16,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    if (!SylphyMiuixStyle.enabled(context) || onTap == null) return child;
    return MiuixPressable(
      onPressed: onTap,
      onLongPress: onLongPress,
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.99,
      shape: MiuixSquircleBorder(cornerRadius: cornerRadius),
      child: child,
    );
  }
}
