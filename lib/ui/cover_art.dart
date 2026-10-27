import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';

class CoverArt extends StatefulWidget {
  const CoverArt({
    super.key,
    required this.app,
    required this.track,
    this.size = 48,
    this.borderRadius = 10,
  });
  final SylphyApp app;
  final Track track;
  final double size;
  final double borderRadius;
  @override
  State<CoverArt> createState() => _CoverArtState();
}

class _CoverArtState extends State<CoverArt> {
  late Future<File?> cover = widget.app.artwork.load(widget.track);
  @override
  void initState() {
    super.initState();
    widget.app.artwork.retain(widget.track);
    widget.app.assets.addListener(_assetChanged);
  }

  void _assetChanged() {
    final change = widget.app.assets.lastChange;
    if (change != null &&
        (change.sourceId != widget.track.ref.sourceId ||
            change.key != widget.app.artwork.key(widget.track))) {
      return;
    }
    if (mounted) {
      setState(() {
        cover = widget.app.artwork.load(widget.track);
      });
    }
  }

  @override
  void dispose() {
    widget.app.assets.removeListener(_assetChanged);
    widget.app.artwork.release(widget.track);
    super.dispose();
  }

  @override
  void didUpdateWidget(CoverArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.ref != widget.track.ref ||
        oldWidget.track.artworkVersion != widget.track.artworkVersion) {
      widget.app.artwork.release(oldWidget.track);
      widget.app.artwork.retain(widget.track);
      cover = widget.app.artwork.load(widget.track);
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(widget.borderRadius),
    child: SizedBox.square(
      dimension: widget.size,
      child: FutureBuilder<File?>(
        future: cover,
        builder: (context, snapshot) {
          final fallback = ColoredBox(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Icon(
              Icons.music_note_rounded,
              size: (widget.size * .32).clamp(20, 80),
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          );
          return snapshot.data == null
              ? fallback
              : Image.file(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  cacheWidth:
                      (widget.size * MediaQuery.devicePixelRatioOf(context))
                          .round()
                          .clamp(1, 1000),
                  errorBuilder: (_, _, _) => fallback,
                );
        },
      ),
    ),
  );
}
