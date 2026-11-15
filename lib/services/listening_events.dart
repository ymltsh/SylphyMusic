import '../core/models.dart';

/// Published synchronously, before the queue mutates. Not a media-control API.
enum ListeningBoundaryKind {
  completed,
  manualSkip,
  replaced,
  repeatOne,
  stopped,
}

class ListeningBoundary {
  const ListeningBoundary(this.track, this.kind);
  final TrackRef track;
  final ListeningBoundaryKind kind;
}
