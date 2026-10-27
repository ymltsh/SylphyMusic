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
  });
  final SylphyApp app;
  final Track track;
  final double size;
  @override
  State<CoverArt> createState() => _CoverArtState();
}

class _CoverArtState extends State<CoverArt> {
  late Future<File?> cover = widget.app.artwork.load(widget.track);
  @override
  void didUpdateWidget(CoverArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.ref != widget.track.ref ||
        oldWidget.track.coverId != widget.track.coverId) {
      cover = widget.app.artwork.load(widget.track);
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: SizedBox.square(
      dimension: widget.size,
      child: FutureBuilder<File?>(
        future: cover,
        builder: (context, snapshot) {
          final fallback = ColoredBox(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: const Icon(Icons.music_note_rounded),
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
