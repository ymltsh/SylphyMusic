import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import 'miuix_iconography.dart';

/// KSU-inspired Miuix dock. Only paints navigation chrome; SylphyShell owns
/// selectedIndex and the page state. Do not add a second Navigator or SafeArea.
///
/// The native GlassNavigationBar handles spring-driven indicator edges,
/// quick successive taps, cross-tab dragging, RTL, and reduced motion.
class MiuixDockNavigation extends StatelessWidget {
  const MiuixDockNavigation({
    super.key,
    required this.selectedIndex,
    required this.labels,
    required this.icons,
    required this.onSelected,
    this.backdrop,
    this.fullWidthInset,
  }) : assert(labels.length == icons.length),
       assert(labels.length >= 2 && labels.length <= 5),
       assert(selectedIndex >= 0 && selectedIndex < labels.length);

  static const double barHeight = 56;
  static const double topGap = 6;
  static const double bottomGap = 4;
  static const double horizontalInset = 28;
  static final _frostBlur = ImageFilter.blur(sigmaX: 14, sigmaY: 14);

  /// The native component uses a larger label at accessibility text scales.
  /// Keep its height and the mini-player's reserved space in sync.
  static double effectiveBarHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(1) >= 1.6 ? 64 : barHeight;

  /// Fixed layout reserve + precisely one system navigation inset.
  static double reserveHeight(BuildContext context) =>
      effectiveBarHeight(context) +
      topGap +
      bottomGap +
      MediaQuery.viewPaddingOf(context).bottom;

  final int selectedIndex;
  final List<String> labels;
  final List<IconData> icons;
  final ValueChanged<int> onSelected;
  final MiuixBackdrop? backdrop;

  /// Horizontal inset for the full-width dock. The short dock has its own
  /// fixed margins and maximum width.
  final double? fullWidthInset;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final dark = theme.brightness == Brightness.dark;
    final liquidGlass = backdrop != null;
    const shape = MiuixGlassShape(cornerRadius: 999);
    // Keep the native tab gestures and indicator in both surface styles.
    final navigation = MiuixGlassNavigationBar(
      key: const ValueKey('miuix-bottom-navigation'),
      backdrop: backdrop,
      alpha: liquidGlass ? 1 : 0,
      selectedIndex: selectedIndex,
      onSelect: onSelected,
      height: effectiveBarHeight(context),
      shape: shape,
      material: MiuixGlassMaterials.puredThinGlass(dark),
      // In dark mode KSU has a charcoal, not cyan, selected capsule.
      indicatorColor: dark
          ? Colors.white.withValues(alpha: .12)
          : colors.primary.withValues(alpha: .12),
      indicatorPressedColor: dark
          ? Colors.white.withValues(alpha: .22)
          : colors.primary.withValues(alpha: .20),
      // KSU uses a theme accent for the active icon + label. Inactive
      // glyphs stay fully opaque instead of Material's 40% alpha.
      selectedColor: colors.primary,
      unselectedColor: colors.onSurface,
      items: [
        for (var i = 0; i < labels.length; i++)
          MiuixGlassNavigationItem(
            label: labels[i],
            contentDescription: labels[i],
            icon: MiuixIcon(
              icon: SylphyMiuixIconography.dock(labels[i], icons[i]),
              size: 28,
            ),
          ),
      ],
    );

    // KSU's own floating bar also reserves the real navigation-bar inset.
    // The GlassNavigationBar does not add a second inset internally.
    final inset = fullWidthInset ?? horizontalInset;
    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(inset, topGap, inset, bottomGap),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: fullWidthInset == null ? 440 : double.infinity,
            ),
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                if (!liquidGlass)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipPath(
                        clipper: const ShapeBorderClipper(shape: shape),
                        child: BackdropFilter(
                          filter: _frostBlur,
                          child: ColoredBox(
                            color: colors.surfaceContainer.withValues(
                              alpha: dark ? .82 : .78,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                navigation,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
