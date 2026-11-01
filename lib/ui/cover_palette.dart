import 'dart:isolate';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Only the roles the player overrides. Constructing these lightweight Colors
/// on the UI isolate does not invoke Material's synchronous HCT calculations.
class CoverPalette {
  const CoverPalette._(this._roles);

  final List<int> _roles;

  Color get primary => Color(_roles[0]);
  Color get onPrimary => Color(_roles[1]);
  Color get primaryContainer => Color(_roles[2]);
  Color get onPrimaryContainer => Color(_roles[3]);
  Color get secondary => Color(_roles[4]);
  Color get onSecondary => Color(_roles[5]);
  Color get secondaryContainer => Color(_roles[6]);
  Color get onSecondaryContainer => Color(_roles[7]);
  Color get tertiary => Color(_roles[8]);
  Color get onTertiary => Color(_roles[9]);
  Color get inversePrimary => Color(_roles[10]);
}

final _palettes = <String, Future<CoverPalette?>>{};

/// Single-flight, bounded LRU. The key includes the on-disk artwork revision,
/// so a new cover never inherits the previous cover's colors. Both prewarm and
/// the player page use this same cache.
Future<CoverPalette?> coverColorScheme(
  File file, {
  Brightness brightness = Brightness.dark,
}) async {
  try {
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
    if (result == null && identical(_palettes[key], pending)) {
      _palettes.remove(key);
    }
    return result;
  } catch (_) {
    // Missing or invalid covers must not interrupt navigation or playback.
    return null;
  }
}

Future<CoverPalette?> _extractPalette(File file, Brightness brightness) async {
  try {
    // Image decoding requires the Flutter engine on the UI/root isolate.
    // Restrict the decoded image to <= 112 px on its longest edge, matching
    // Flutter's ColorScheme.fromImageProvider sampling bound.
    final encoded = await file.readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        final scale = math.min(
          1.0,
          112.0 / math.max(descriptor.width, descriptor.height),
        );
        final width = math.max(1, (descriptor.width * scale).floor());
        final height = math.max(1, (descriptor.height * scale).floor());
        final codec = await descriptor.instantiateCodec(
          targetWidth: width,
          targetHeight: height,
        );
        try {
          final image = (await codec.getNextFrame()).image;
          try {
            final rgba = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            if (rgba == null) return null;
            // Only ~50 KiB crosses the isolate boundary; the large encoded
            // artwork and Flutter image handles are never sent to the worker.
            final pixels = TransferableTypedData.fromList([
              rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
            ]);
            final roles = await _quantizeInWorker(
              pixels,
              brightness == Brightness.dark,
            );
            return CoverPalette._(roles);
          } finally {
            image.dispose();
          }
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  } catch (_) {
    return null;
  }
}

// Keep the isolate closure out of the decoder's scope: otherwise it can
// accidentally capture non-sendable ui.Image / Codec objects.
Future<List<int>> _quantizeInWorker(TransferableTypedData pixels, bool dark) =>
    Isolate.run(
      () => _quantizeAndBuildRoles(pixels, dark),
      debugName: 'sylphy_cover_palette',
    );

/// Pure Dart: safe on a worker isolate. Use the same Celebi + Score +
/// Material 3 Fidelity algorithm as ColorScheme.fromImageProvider. Flutter's
/// rawRgba bytes become ABGR Uint32 pixels on Android/desktop (little endian).
/// Score expects ARGB, hence the explicit red/blue swap after quantization.
Future<List<int>> _quantizeAndBuildRoles(
  TransferableTypedData transferred,
  bool dark,
) async {
  final rgba = transferred.materialize().asUint8List();
  final pixels = rgba.buffer.asUint32List(
    rgba.offsetInBytes,
    rgba.lengthInBytes ~/ 4,
  );
  final quantized = await QuantizerCelebi().quantize(
    pixels,
    128,
    returnInputPixelToClusterPixel: true,
  );
  final populations = quantized.colorToCount.map(
    (abgr, count) => MapEntry<int, int>(
      (abgr & 0xff00ff00) | ((abgr & 0xff) << 16) | ((abgr >> 16) & 0xff),
      count,
    ),
  );
  final seed = Score.score(populations, desired: 1).first;
  final scheme = SchemeFidelity(
    sourceColorHct: Hct.fromInt(seed),
    isDark: dark,
    contrastLevel: 0.0,
  );
  return [
    MaterialDynamicColors.primary.getArgb(scheme),
    MaterialDynamicColors.onPrimary.getArgb(scheme),
    MaterialDynamicColors.primaryContainer.getArgb(scheme),
    MaterialDynamicColors.onPrimaryContainer.getArgb(scheme),
    MaterialDynamicColors.secondary.getArgb(scheme),
    MaterialDynamicColors.onSecondary.getArgb(scheme),
    MaterialDynamicColors.secondaryContainer.getArgb(scheme),
    MaterialDynamicColors.onSecondaryContainer.getArgb(scheme),
    MaterialDynamicColors.tertiary.getArgb(scheme),
    MaterialDynamicColors.onTertiary.getArgb(scheme),
    MaterialDynamicColors.inversePrimary.getArgb(scheme),
  ];
}
