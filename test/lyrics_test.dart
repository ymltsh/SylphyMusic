import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/services/lyrics.dart';

void main() {
  test('offset and active line handle preroll and seeks', () {
    final lines = parseLrc('[offset:100]\n[00:01.00]A\n[00:02.00]B');
    expect(lines.first.at.inMilliseconds, 1100);
    expect(activeLrcIndex(lines, Duration.zero), -1);
    expect(activeLrcIndex(lines, const Duration(milliseconds: 1100)), 0);
    expect(activeLrcIndex(lines, const Duration(seconds: 3)), 1);
    expect(activeLrcIndex(lines, const Duration(seconds: 1)), -1);
  });
  test('LRC tags sort and parse multiple timestamps', () {
    final lines = parseLrc('[00:02.50]B\n[00:01.005]A\n[00:04.3][00:05.3]C');
    expect(lines.length, 4);
    expect(lines.first.text, 'A');
    expect(lines.first.at.inMilliseconds, 1005);
    expect(lines[1].at.inMilliseconds, 2500);
  });
}
