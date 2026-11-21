import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// Miuix floating pill navigation. The caller owns tab and route state.
///
/// One indicator travels between tabs; rendering four separately animated
/// backgrounds would make the highlight disappear and reappear on each tap.
/// Scaffold should use `extendBody: true` so its content is visible through
/// the transparent margin around this dock.
class MiuixDockNavigation extends StatelessWidget {
  const MiuixDockNavigation({
    super.key,
    required this.selectedIndex,
    required this.labels,
    required this.icons,
    required this.onSelected,
  }) : assert(labels.length == icons.length),
       assert(labels.length >= 2 && labels.length <= 5),
       assert(selectedIndex >= 0 && selectedIndex < labels.length);

  static const double barHeight = 58;
  static const double topGap = 6;
  static const double bottomGap = 2;
  static const double _horizontalInset = 22;
  static const double _cornerRadius = 34;
  static const double _selectionRadius = 30;

  /// Space reserved by the pill plus the single system gesture inset.
  static double reserveHeight(BuildContext context) =>
      barHeight + topGap + bottomGap + MediaQuery.viewPaddingOf(context).bottom;

  final int selectedIndex;
  final List<String> labels;
  final List<IconData> icons;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final dark = theme.brightness == Brightness.dark;
    final base = colors.surfaceContainer.withValues(alpha: dark ? .78 : .74);
    final selected = Color.alphaBlend(
      colors.primaryContainer.withValues(alpha: dark ? .70 : .60),
      base,
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // SafeArea owns the *only* bottom gesture inset; the library navigation
    // widget (which adds its own inset and dims unselected icons) is not used.
    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          _horizontalInset,
          topGap,
          _horizontalInset,
          bottomGap,
        ),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: const MiuixSquircleBorder(cornerRadius: _cornerRadius),
                shadows: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? .22 : .10),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipPath(
                clipper: const ShapeBorderClipper(
                  shape: MiuixSquircleBorder(cornerRadius: _cornerRadius),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.alphaBlend(
                            Colors.white.withValues(alpha: dark ? .12 : .35),
                            base,
                          ),
                          Color.alphaBlend(
                            Colors.white.withValues(alpha: dark ? .04 : .12),
                            base,
                          ),
                        ],
                      ),
                      shape: MiuixSquircleBorder(
                        cornerRadius: _cornerRadius,
                        side: BorderSide(
                          color: Colors.white.withValues(
                            alpha: dark ? .18 : .72,
                          ),
                          width: 1,
                        ),
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final tabWidth = constraints.maxWidth / labels.length;
                        return SizedBox(
                          key: const ValueKey('miuix-bottom-navigation'),
                          height: barHeight,
                          child: Stack(
                            children: [
                              AnimatedPositionedDirectional(
                                key: const ValueKey(
                                  'miuix-selection-indicator',
                                ),
                                duration: reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 360),
                                curve: MiuixMotion.standardDecelerate,
                                top: 3,
                                bottom: 3,
                                start: tabWidth * selectedIndex + 3,
                                width: tabWidth - 6,
                                child: DecoratedBox(
                                  decoration: ShapeDecoration(
                                    color: selected,
                                    shape: const MiuixSquircleBorder(
                                      cornerRadius: _selectionRadius,
                                    ),
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  for (
                                    var index = 0;
                                    index < labels.length;
                                    index++
                                  )
                                    Expanded(
                                      child: _tab(
                                        index,
                                        colors: colors,
                                        selected: index == selectedIndex,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(
    int index, {
    required MiuixColors colors,
    required bool selected,
  }) {
    final foreground = selected ? colors.onPrimaryContainer : colors.onSurface;
    return Semantics(
      selected: selected,
      child: MiuixPressable(
        key: ValueKey('miuix-tab-$index'),
        onPressed: () => onSelected(index),
        semanticLabel: labels[index],
        feedbackType: MiuixPressFeedbackType.none,
        shape: const MiuixSquircleBorder(cornerRadius: _selectionRadius),
        child: ExcludeSemantics(
          child: SizedBox(
            height: barHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icons[index], size: 23, color: foreground),
                const SizedBox(height: 2),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      labels[index],
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
