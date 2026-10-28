import 'package:flutter/material.dart';

/// One entry of a [CapsuleToggle].
class CapsuleOption<T> {
  const CapsuleOption({
    required this.value,
    required this.label,
    required this.icon,
  });

  final T value;
  final String label;
  final IconData icon;
}

/// Single-choice chip bar shared by the library and search views.
///
/// The bar scrolls horizontally on narrow screens and keeps the state in the
/// caller so both pages present the same 8 dp rounded "capsule" tags.
class CapsuleToggle<T> extends StatelessWidget {
  const CapsuleToggle({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.keyPrefix,
  });

  final List<CapsuleOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Builds each chip key as `<keyPrefix>-<value>` for widget tests.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey('$keyPrefix-${option.value}'),
                selected: option.value == selected,
                onSelected: (_) => onChanged(option.value),
                showCheckmark: false,
                avatar: Icon(
                  option.icon,
                  size: 16,
                  color: option.value == selected
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant,
                ),
                label: Text(option.label),
                labelStyle: TextStyle(
                  color: option.value == selected
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant,
                  fontWeight: option.value == selected
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
                backgroundColor: scheme.surfaceContainerHighest.withValues(
                  alpha: .72,
                ),
                selectedColor: scheme.primary,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}
