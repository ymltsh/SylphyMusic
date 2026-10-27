import 'package:flutter/services.dart';

class LauncherIconOption {
  const LauncherIconOption({
    required this.id,
    required this.label,
    required this.preview,
  });

  final String id;
  final String label;
  final String preview;

  factory LauncherIconOption.fromMap(Map<dynamic, dynamic> value) =>
      LauncherIconOption(
        id: value['id'] as String,
        label: value['label'] as String,
        preview: value['preview'] as String,
      );
}

class LauncherIconSelection {
  const LauncherIconSelection(this.selected, this.options);

  final String selected;
  final List<LauncherIconOption> options;
}

class LauncherIconService {
  const LauncherIconService();

  static const MethodChannel _channel = MethodChannel(
    'music.sylphy/launcher_icons',
  );

  Future<LauncherIconSelection> load() async {
    final raw = await _channel.invokeMapMethod<dynamic, dynamic>('getOptions');
    if (raw == null) throw StateError('无法读取系统应用图标');
    final choices = (raw['options'] as List<dynamic>)
        .map(
          (item) => LauncherIconOption.fromMap(item as Map<dynamic, dynamic>),
        )
        .toList(growable: false);
    return LauncherIconSelection(raw['selected'] as String, choices);
  }

  Future<void> select(String id) =>
      _channel.invokeMethod<void>('setIcon', {'id': id});
}
