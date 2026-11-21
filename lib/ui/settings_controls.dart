import 'package:flutter/material.dart';

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, this.title, required this.children});

  final String? title;
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
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
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
        leading: icon == null ? null : Icon(icon),
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
    leading: icon == null ? null : Icon(icon),
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
