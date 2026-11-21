# Stage 4: KernelSU-like Miuix surface refinement

Depends on Stage 1, Stage 2, Stage 2 refinement and Stage 3 applied in that order.
This patch is additive; it does not create a separate My page or playback controller.

- Reuse `SylphyAdaptiveCard` for existing grids and settings groups: Material
  retains the original Card, while experimental Miuix uses native `MiuixCard`.
  A transparent Material layer inside Miuix cards keeps settings-row ink
  feedback visible with the existing controls.
- Make library chips continuous squircle pills with 180ms Miuix color easing.
- Use Miuix semantic selection surfaces on the current/selected song.
- Style the existing music search TextField as a neutral, borderless Miuix pill;
  its TextEditingController, debounce and submission callbacks remain unchanged.
- Replace the frosted dock with native MiuixNavigationBar in an opaque squircle
  shell, muted selected background and restrained shadow. Keep one SafeArea.
- Preserve Settings icon sizing in this revision to avoid conflicting with local custom settings code.

Run:

```sh
flutter analyze
flutter test test/miuix_adaptive_components_test.dart
flutter test test/miuix_ksu_refinement_test.dart
flutter build apk --debug --dart-define=SYLPHY_EXPERIMENTAL_MIUIX=true
```

Visual QA: Android gesture / three-button navigation, dark theme, textScaleFactor
1.3, keyboard open with music search, scrolling 10k+ songs, tapping a song and
its trailing menu, switching tabs, playlist popup menu, offline/custom wallpaper.
