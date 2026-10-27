import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';

void main() {
  test('the three modes cycle without combining shuffle and repeat-one', () {
    var mode = PlaybackMode.listLoop;
    mode = mode.next;
    expect(mode, PlaybackMode.singleLoop);
    mode = mode.next;
    expect(mode, PlaybackMode.shuffle);
    mode = mode.next;
    expect(mode, PlaybackMode.listLoop);
    expect(const QueueSnapshot().playbackMode, PlaybackMode.listLoop);
  });
  test('old sequential queues upgrade without changing the current song or progress', () {
    final queue = QueueSnapshot.fromJson({
      'tracks': ['a', 'b', 'c'],
      'index': 1,
      'positionMs': 2345,
      'repeat': 'off',
      'shuffle': false,
      'order': [0, 1, 2],
      'history': [0],
    });
    expect(queue.playbackMode, PlaybackMode.listLoop);
    expect(queue.repeat, RepeatKind.all);
    expect(queue.index, 1);
    expect(queue.positionMs, 2345);
    expect(queue.history, [0]);
  });
  test('old combined shuffle / repeat-one becomes single repeat and restores ordered navigation', () {
    final queue = QueueSnapshot.fromJson({
      'tracks': ['a', 'b', 'c'],
      'index': 1,
      'repeat': 'one',
      'shuffle': true,
      'order': [1, 2, 0],
    });
    expect(queue.playbackMode, PlaybackMode.singleLoop);
    expect(queue.shuffle, isFalse);
    expect(queue.order, [0, 1, 2]);
  });
  test('saved random permutations survive a restart and loop the queue', () {
    final queue = QueueSnapshot.fromJson({
      'tracks': ['a', 'b', 'c'],
      'index': 1,
      'repeat': 'off',
      'shuffle': true,
      'order': [1, 2, 0],
    });
    expect(queue.playbackMode, PlaybackMode.shuffle);
    expect(queue.repeat, RepeatKind.all);
    expect(queue.order, [1, 2, 0]);
    final restored = QueueSnapshot.fromJson(queue.toJson());
    expect(restored.order, queue.order);
    expect(restored.playbackMode, PlaybackMode.shuffle);
  });
}
