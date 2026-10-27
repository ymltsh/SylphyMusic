import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';

void main() {
  test('different source profiles never share track identity', () {
    expect(TrackRef('emby-a', '1'), isNot(TrackRef('emby-b', '1')));
  });
  test('track key safely round trips unusual ids', () {
    const ref = TrackRef('server:"x', 'slash/a?=b');
    expect(TrackRef.parse(ref.key), ref);
  });
  test('queue serialization preserves shuffle history', () {
    const q = QueueSnapshot(
      tracks: ['A', 'B'],
      index: 1,
      positionMs: 20355,
      shuffle: true,
      order: [1, 0],
      history: [0],
    );
    final restored = QueueSnapshot.fromJson(q.toJson());
    expect(restored.positionMs, 20355);
    expect(restored.order, [1, 0]);
    expect(restored.history, [0]);
  });
}
