import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';

// The live player used to blur a window-sized layer (sigma 48). On HiDPI
// desktops that allocated large intermediate render targets. Blur a bounded
// 256px cover *once* instead, then let Image scale it to the viewport.
const _previewSide = 256;
const _previewSigma = 12.0;
const _maxCachedPreviews = 6;

// Values are encoded PNGs, not ui.Image handles: image ownership remains with
// Flutter's ImageCache, and evicting this LRU does not invalidate an on-screen
// image. In-flight requests for the same file are shared.
final _blurredPreviews = <String, Future<Uint8List?>>{};

Future<Uint8List?> _blurredPreview(File file) async {
  try {
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) return null;
    final key =
        '${file.path}/${stat.modified.microsecondsSinceEpoch}/${stat.size}';
    final existing = _blurredPreviews.remove(key);
    if (existing != null) {
      _blurredPreviews[key] = existing;
      return existing;
    }
    final pending = _createBlurredPreview(file);
    _blurredPreviews[key] = pending;
    while (_blurredPreviews.length > _maxCachedPreviews) {
      _blurredPreviews.remove(_blurredPreviews.keys.first);
    }
    final result = await pending;
    if (result == null && identical(_blurredPreviews[key], pending)) {
      _blurredPreviews.remove(key);
    }
    return result;
  } catch (_) {
    // An invalid or disappearing cover must never break the playback page.
    return null;
  }
}

Future<Uint8List?> _createBlurredPreview(File file) async {
  try {
    final encoded = await file.readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        // Decode to the small target size, not to the cover's source size.
        final scale = math.min(
          1.0,
          _previewSide / math.max(descriptor.width, descriptor.height),
        );
        final codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (descriptor.width * scale).round()),
          targetHeight: math.max(1, (descriptor.height * scale).round()),
        );
        try {
          final decoded = (await codec.getNextFrame()).image;
          try {
            // CoverArt uses BoxFit.cover inside a square; preserve its
            // centered crop before generating the blurred background.
            final side = math.min(decoded.width, decoded.height).toDouble();
            final source = ui.Rect.fromLTWH(
              (decoded.width - side) / 2,
              (decoded.height - side) / 2,
              side,
              side,
            );
            final target = ui.Rect.fromLTWH(
              0,
              0,
              _previewSide.toDouble(),
              _previewSide.toDouble(),
            );
            final recorder = ui.PictureRecorder();
            final canvas = ui.Canvas(recorder);
            // This is the only blur operation. Its layer is always 256x256,
            // irrespective of the device's logical size or pixel ratio.
            canvas.saveLayer(
              target,
              ui.Paint()
                ..imageFilter = ui.ImageFilter.blur(
                  sigmaX: _previewSigma,
                  sigmaY: _previewSigma,
                  tileMode: ui.TileMode.clamp,
                ),
            );
            canvas.drawImageRect(
              decoded,
              source,
              target,
              ui.Paint()..filterQuality = ui.FilterQuality.medium,
            );
            canvas.restore();
            final picture = recorder.endRecording();
            try {
              final blurred = await picture.toImage(_previewSide, _previewSide);
              try {
                final data = await blurred.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                if (data == null) return null;
                return Uint8List.fromList(
                  data.buffer.asUint8List(
                    data.offsetInBytes,
                    data.lengthInBytes,
                  ),
                );
              } finally {
                blurred.dispose();
              }
            } finally {
              picture.dispose();
            }
          } finally {
            decoded.dispose();
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

/// Loads a thumbnail only when the artwork identity or asset revision changes.
/// Playback position notifications can rebuild the parent without decoding or
/// starting another blur operation.
class BlurredCoverBackdrop extends StatefulWidget {
  const BlurredCoverBackdrop({
    super.key,
    required this.app,
    required this.track,
    required this.opacity,
  });

  final SylphyApp app;
  final Track track;
  final double opacity;

  @override
  State<BlurredCoverBackdrop> createState() => _BlurredCoverBackdropState();
}

class _BlurredCoverBackdropState extends State<BlurredCoverBackdrop> {
  late Future<Uint8List?> _image;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _opacity = AlwaysStoppedAnimation<double>(widget.opacity);
    widget.app.artwork.retain(widget.track);
    widget.app.assets.addListener(_assetChanged);
    _load();
  }

  void _load() {
    final app = widget.app;
    final track = widget.track;
    _image = () async {
      final file = await app.artwork.load(track);
      return file == null ? null : _blurredPreview(file);
    }();
  }

  void _assetChanged() {
    final change = widget.app.assets.lastChange;
    if (change != null &&
        (change.sourceId != widget.track.ref.sourceId ||
            change.key != widget.app.artwork.key(widget.track))) {
      return;
    }
    if (mounted) setState(_load);
  }

  @override
  void didUpdateWidget(covariant BlurredCoverBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.opacity != widget.opacity) {
      _opacity = AlwaysStoppedAnimation<double>(widget.opacity);
    }
    if (!identical(oldWidget.app, widget.app) ||
        oldWidget.track.ref != widget.track.ref ||
        oldWidget.track.artworkVersion != widget.track.artworkVersion) {
      oldWidget.app.assets.removeListener(_assetChanged);
      oldWidget.app.artwork.release(oldWidget.track);
      widget.app.artwork.retain(widget.track);
      widget.app.assets.addListener(_assetChanged);
      _load();
    }
  }

  @override
  void dispose() {
    widget.app.assets.removeListener(_assetChanged);
    widget.app.artwork.release(widget.track);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: FutureBuilder<Uint8List?>(
      future: _image,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          child: bytes == null
              ? const SizedBox.expand(key: ValueKey('empty-blur-cover'))
              : SizedBox.expand(
                  key: ValueKey(bytes),
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    opacity: _opacity,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.expand(),
                  ),
                ),
        );
      },
    ),
  );
}
