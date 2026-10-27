import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';

class TrackLookup extends StatefulWidget {
  const TrackLookup({
    super.key,
    required this.app,
    required this.ref,
    required this.builder,
  });
  final SylphyApp app;
  final TrackRef ref;
  final Widget Function(BuildContext, Track?) builder;
  @override
  State<TrackLookup> createState() => _TrackLookupState();
}

class _TrackLookupState extends State<TrackLookup> {
  late Future<Track?> track = widget.app.db.track(widget.ref);
  late int revision = widget.app.catalogRevision;
  @override
  void didUpdateWidget(covariant TrackLookup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ref != widget.ref || revision != widget.app.catalogRevision) {
      revision = widget.app.catalogRevision;
      track = widget.app.db.track(widget.ref);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Track?>(
    future: track,
    builder: (context, snapshot) => widget.builder(context, snapshot.data),
  );
}
