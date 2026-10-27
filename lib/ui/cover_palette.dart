import 'dart:io';

import 'package:flutter/material.dart';

/// Extracts an M3 palette from locally cached cover artwork. The playback page
/// uses the current app brightness so a system light theme gets a light
/// palette instead of a forced dark one.
Future<ColorScheme?> coverColorScheme(
  File file, {
  Brightness brightness = Brightness.dark,
}) async {
  try {
    return await ColorScheme.fromImageProvider(
      provider: ResizeImage(FileImage(file), width: 128, allowUpscaling: false),
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
  } catch (_) {
    return null;
  }
}
