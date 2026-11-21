# Stage 8 — Dense Miuix music lists, not per-track cards

Source baseline: current public `ymltsh/SylphyMusic` `main` at preparation time.
This patch only touches song rows and the library browser, so it is also
intended to apply over Stage 7 if the user's local branch has that patch.

## Design choice

- KSU's separate rounded cards suit distinct apps/modules. They are **not** a
  universal Miuix rule for high-density song collections.
- Songs, search results, favorites, history and queues retain a **continuous**
  list. No card margins or new scrolling layers are inserted per song.
- `PlayingSongTile` keeps its original 48dp artwork slot, `ListTile`, item
  geometry and playback listener. The Miuix cover radius becomes 12dp (MD3
  stays at the previous 10dp). Ordinary rows are transparent, current track is
  softly tinted, batch selection is visibly stronger.
- Title, subtitle, equalizer and scrollbar use the active Miuix semantic color
  scheme, including light/dark modes. MD3 styling stays unchanged.
- The existing track `PopupMenuButton` retains its callback and menu items;
  only its shape/surface/text theme is adapted to Miuix. This is intentionally
  *not* a migration to the more complex glass popup controller.
- The existing SQL paging, fixed item extents and `ListView.builder` remain
  unchanged. The bottom padding formula is refactored without changing its
  result, making dock clearance independently testable. Do not add another
  SafeArea or duplicate the dock's bottom inset.
- Non-song **compact album/artist grids** use SylphyAdaptiveCard in Miuix mode,
  and continue using Card.outlined under MD3.

## Verification

```sh
flutter analyze
flutter test test/miuix_music_list_test.dart
flutter test test/miuix_adaptive_components_test.dart
flutter build apk --debug --dart-define=SYLPHY_EXPERIMENTAL_MIUIX=true
```

On device, scroll to the **last** song and verify it can be fully revealed
above the floating dock and mini player, with no double bottom inset. Check
batch-select, current track, long-press, popup actions, light/dark contrast,
search/favorites list, and 10k+ music library scroll performance.

Design references:
- https://github.com/ChuxinNeko/flutter_miuix/blob/main/doc/.api_frag/20_buttons.zh.md
- https://github.com/ChuxinNeko/flutter_miuix/blob/main/doc/.api_frag/70_foundation.zh.md
