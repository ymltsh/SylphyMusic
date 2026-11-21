import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/ui/miuix/miuix_iconography.dart';

void main() {
  test('KSU-like rounded glyphs map the four Sylphy destinations', () {
    expect(
      SylphyMiuixIconography.dock('首页', Icons.home_outlined),
      Icons.cottage_rounded,
    );
    expect(
      SylphyMiuixIconography.dock('音乐库', Icons.library_music_outlined),
      Icons.library_music_rounded,
    );
    expect(
      SylphyMiuixIconography.dock('歌单', Icons.queue_music_outlined),
      Icons.queue_music_rounded,
    );
    expect(
      SylphyMiuixIconography.dock('我的', Icons.person_outline),
      Icons.person_rounded,
    );
  });

  test('common outlined actions use rounded filled glyphs in Miuix mode', () {
    expect(
      SylphyMiuixIconography.rounded(Icons.favorite_outline),
      Icons.favorite_rounded,
    );
    expect(
      SylphyMiuixIconography.rounded(Icons.settings_outlined),
      Icons.settings_rounded,
    );
    expect(
      SylphyMiuixIconography.rounded(Icons.download_outlined),
      Icons.download_rounded,
    );
  });
}
