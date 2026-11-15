import '../core/models.dart';

/// Shared geometric source for the in-app and exported cover-card arrangement.
/// Selection does not merge different music sources or recording identities.
class RecommendationCoverLayout {
  static const offsets = <({double x, double y})>[
    (x: .33, y: .03),
    (x: .04, y: .22),
    (x: .40, y: .25),
    (x: .18, y: .42),
  ];
  static const angles = <double>[.13, -.12, .10, -.06];
  static const coverRatio = .54;

  static List<Track> select(Iterable<Track> tracks) {
    final selected = <Track>[];
    final seenAlbums = <String>{};
    final all = tracks.toList();
    for (final track in all) {
      if (seenAlbums.add('${track.ref.sourceId}:${track.albumGroup}')) {
        selected.add(track);
      }
      if (selected.length == 4) return selected;
    }
    final seenRefs = selected.map((track) => track.ref.key).toSet();
    for (final track in all) {
      if (seenRefs.add(track.ref.key)) selected.add(track);
      if (selected.length == 4) break;
    }
    return selected;
  }
}
