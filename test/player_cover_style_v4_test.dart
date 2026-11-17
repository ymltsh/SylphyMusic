import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/player_layout.dart';

void main() {
  test('v4 per-cover styles round-trip and immersive is rectangular', () {
    const full = Rect.fromLTWH(0, 0, 1, 1);
    final cover = PlayerElement(
      id: 'art',
      type: PlayerPart.cover,
      frame: full,
      wideFrame: full,
      coverStyle: PlayerCoverStyle.immersive,
      coverFadeStart: .4,
      coverFadeDirection: CoverFadeDirection.bottom,
    );
    final layout = PlayerLayout(
      id: 'style-test',
      name: 'test',
      elements: [cover],
    );
    final decoded = PlayerLayout.decode(layout.encode());
    final actual = decoded.elements.single;
    expect(actual.coverStyle, PlayerCoverStyle.immersive);
    expect(actual.coverFadeStart, .4);
    expect(actual.coverFadeDirection, CoverFadeDirection.bottom);
    expect(
      decoded.bounds(actual, const Size(400, 200)),
      const Rect.fromLTWH(0, 0, 400, 200),
    );
    final vinyl = actual.copyWith(coverStyle: PlayerCoverStyle.vinyl);
    expect(decoded.bounds(vinyl, const Size(400, 200)).width, 200);
  });

  test('old layout documents are not accepted', () {
    final now = playerTemplate().encode();
    expect(
      () =>
          PlayerLayout.decode(now.replaceFirst('"version": 4', '"version": 3')),
      throwsFormatException,
    );
  });
}
