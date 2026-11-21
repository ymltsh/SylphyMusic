# Miuix stage 3 · Incremental component texture (Android experimental build)

## Upstream AI skill used

The implementation follows `flutter-miuix-skill` (upstream
`ChuxinNeko/flutter_miuix/skill/payload/flutter-miuix/SKILL.md`) and its
`references/20_buttons.zh.md`, `60_theme.zh.md`, `70_foundation.zh.md`.
This is developer guidance, **not an app runtime dependency**. Optional local
agent installation: `npx flutter-miuix-skill` at the Flutter repository root.
Keep the Flutter dependency fixed to the previously selected 1.3.0 until a
separate dependency review; the skill's API descriptions alone do not upgrade it.

## Rules for Sylphy

- Preserve HomePage, LibraryBrowser, PlaylistGridCard, the settings hierarchy,
  virtualized SQL paging, playlist menu callbacks, player session, and routes.
- The theme bridge publishes the effective style to adaptive controls. In
  Android experimental builds the Miuix theme scope stays mounted while the
  selection changes, preserving the existing navigation and page state.
- `SylphyAdaptivePressable`: replaces a single InkWell on plain cards;
  `SylphyMiuixPressable`: wraps a ListTile which already owns Material taps.
  Do not wire *both* handlers in Miuix mode. Long-press-only rows retain
  their original Material gesture handler.
- Use `MiuixSquircleBorder` and semantic `MiuixColors` from the actual public
  `package:flutter_miuix/miuix.dart` entrypoint. Do not import `src/` internals.
- `CapsuleToggle` preserves its public keys, parent-owned state and horizontal
  scrolling. Its Miuix chip uses `MiuixPressable`, not a new navigation model.
- `PlayingSongTile` keeps the same playback listener, equalizer, cover, menu,
  long press and current song selection. Only highlight shape/feedback changes.
- `MusicSpaceCard` preserves the rotating source-deck and gradients.
- `PlaylistGridCard` keeps its cover size, context menu and layout.
- Stage 2 already reduced Material NavigationBar's baseline to 64dp and kept a
  single gesture-safe bottom inset for Miuix. Measure both bars with gesture
  and 3-button navigation before changing bottom offsets again.
- No Glass components, new shaders or full-screen blur are added by this patch.

## Verification

`flutter test test/miuix_adaptive_components_test.dart`

Also run the earlier appearance/theme/UI tests, `flutter analyze`, and the
Android experimental build. On a device, check row trailing menus, long-press
selection, 5w-song virtual scrolling, theme toggling, gesture-safe bottom bar,
and mini player overlaid on bottom navigation. Flutter SDK/device verification
must be performed downstream; patch generation alone cannot establish it.
