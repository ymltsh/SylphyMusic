import 'dart:io';
import 'dart:collection';

import 'package:flutter/material.dart';

final _palettes = LinkedHashMap<String, Future<ColorScheme?>>();

/// Extracts an M3 palette from locally cached cover artwork. The playback page
/// uses the current app brightness so a system light theme gets a light
/// palette instead of a forced dark one.
Future<ColorScheme?> coverColorScheme(
  File file, {
  Brightness brightness = Brightness.dark,
}) async {
  final stat = await file.stat();
  final key =
      '${file.path}/${stat.modified.microsecondsSinceEpoch}/${stat.size}/${brightness.name}';
  final cached = _palettes.remove(key);
  if (cached != null) {
    _palettes[key] = cached;
    return cached;
  }
  final pending = _extractPalette(file, brightness);
  _palettes[key] = pending;
  while (_palettes.length > 12) {
    _palettes.remove(_palettes.keys.first);
  }
  final result = await pending;
  if (result == null && identical(_palettes[key], pending))
    _palettes.remove(key);
  return result;
}

Future<ColorScheme?> _extractPalette(File file, Brightness brightness) async {
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
