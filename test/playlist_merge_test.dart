import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/services/cloud_sync.dart';

void main() {
  test('remote unchanged applies local edits', () {
    expect(mergePlaylist(['a'], ['a', 'b'], ['a']).keys, ['a', 'b']);
  });
  test('append-only concurrent edits preserve both additions', () {
    final m = mergePlaylist(['a'], ['a', 'l'], ['a', 'r']);
    expect(m.conflict, false);
    expect(m.keys, ['a', 'r', 'l']);
  });
  test('reorder conflict is not silently overwritten', () {
    final m = mergePlaylist(['a', 'b'], ['b', 'a'], ['a', 'b', 'c']);
    expect(m.conflict, true);
  });
  test('repeated song entries are retained', () {
    final m = mergePlaylist(['a'], ['a', 'a'], ['a', 'a']);
    expect(m.keys, ['a', 'a', 'a']);
  });
}
