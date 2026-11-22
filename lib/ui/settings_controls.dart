import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import 'design_system/miuix_adaptive.dart';
import 'miuix/miuix_iconography.dart';

class SettingsIcon extends StatelessWidget {
  const SettingsIcon(this.icon, {super.key, this.size, this.color});

  final IconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (!SylphyMiuixStyle.enabled(context)) {
      return Icon(icon, size: size, color: color);
    }

    final colors = MiuixTheme.of(context).colors;
    if (icon == Icons.chevron_right || icon == Icons.chevron_right_rounded) {
      return MiuixIcon(
        vector: MiuixIcons.basic.arrowRight,
        size: size ?? 11,
        tint: color ?? colors.onSurfaceVariantActions,
      );
    }

    final theme = IconTheme.of(context);
    return MiuixIcon(
      icon: SylphyMiuixIconography.rounded(icon),
      size: size ?? theme.size,
      tint: color ?? theme.color ?? colors.onSurfaceVariantActions,
    );
  }
}

Widget? settingsBackButton(BuildContext context) {
  if (!SylphyMiuixStyle.enabled(context)) return null;
  final route = ModalRoute.of(context);
  if (route?.impliesAppBarDismissal != true) return null;

  return ActionIconTheme(
    data: ActionIconThemeData(
      backButtonIconBuilder: (_) => const SettingsIcon(Icons.arrow_back),
      closeButtonIconBuilder: (_) => const SettingsIcon(Icons.close),
    ),
    child: route is PageRoute && route.fullscreenDialog
        ? const CloseButton()
        : const BackButton(),
  );
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    this.title,
    this.icon,
    required this.children,
  });

  final String? title;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title case final title?)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
              child: Row(
                children: [
                  if (icon case final icon?) ...[
                    SettingsIcon(
                      icon,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          SylphyAdaptiveCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsSelect<T> extends StatelessWidget {
  const SettingsSelect({
    super.key,
    required this.title,
    this.description,
    this.icon,
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  final String title;
  final String? description;
  final IconData? icon;
  final T value;
  final Map<T, String> labels;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final inline =
          constraints.maxWidth >= 440 &&
          MediaQuery.textScalerOf(context).scale(16) <= 20;
      final menu = DropdownButton<T>(
        icon: const SettingsIcon(Icons.arrow_drop_down),
        isExpanded: true,
        itemHeight: null,
        value: value,
        underline: const SizedBox.shrink(),
        items: [
          for (final entry in labels.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: onChanged == null
            ? null
            : (value) {
                if (value != null) onChanged!(value);
              },
      );
      final detail = description;
      return ListTile(
        leading: icon == null ? null : SettingsIcon(icon!),
        title: Text(title),
        enabled: onChanged != null,
        subtitle: inline
            ? (detail == null ? null : Text(detail))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [if (detail != null) Text(detail), menu],
              ),
        trailing: inline ? SizedBox(width: 144, child: menu) : null,
      );
    },
  );
}

class SettingsSlider extends StatelessWidget {
  const SettingsSlider({
    super.key,
    required this.title,
    required this.formatValue,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    this.icon,
    required this.onChanged,
  });

  final String title;
  final String Function(double) formatValue;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final IconData? icon;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: icon == null ? null : SettingsIcon(icon!),
    title: Text(title),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(formatValue(value)),
        Slider(
          min: min,
          max: max,
          divisions: divisions,
          value: value,
          label: formatValue(value),
          semanticFormatterCallback: formatValue,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}
