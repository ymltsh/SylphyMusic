# Stage 7 — KernelSU glass dock and rounded Miuix iconography

Source baseline: the **updated** `ymltsh/SylphyMusic` `main` branch using
`flutter_miuix: 1.3.0`. Do not reapply Stage 1–6 patches before this patch.

## Reference and choices

- KSU's `BottomBarMiuix.kt` uses `FloatingBottomBar`, `Icons.Rounded.Cottage /
  Security / Extension / Settings`, and bottom padding derived from the real
  system navigation bar. Its floating bar uses a translucent surface, its own
  selected pill, spring animation, backdrop sampling and lens/highlight.
- The Flutter port already ships a public `MiuixGlassNavigationBar` API and
  `MiuixLayerBackdropCapture`. Prefer this native implementation over an
  imitation made from an animated `Container` and `BackdropFilter`.
- We use KSU-inspired rounded *filled* Material glyphs, rendered through the
  public `MiuixIcon` API. The previous Material 3 outlined icons are unchanged.
- Material 3 remains the default. Miuix is still Android portrait and
  experimental; the music player, queue, layouts and navigation state are shared.
- New dock has 56dp minimum content height (64dp at large text scale), with
  6dp above, 4dp below and a single system inset; horizontal inset is 28dp. This is an
  application-specific adaptation, not an official Xiaomi dimensional token.
- Selected color uses Miuix primary; unselected stays 100% opaque. The native
  glass nav widget provides spring movement and drag interaction.

## Glass capture

`MiuixLayerBackdropCapture` wraps only the current Android Miuix portrait body,
**not** the bottom glass consumer. `MiuixLayerBackdrop` is held by SylphyShell
and disposed with the State. Fallback rendering without a captured backdrop is
handled by flutter_miuix. Capture can carry GPU/snapshot overhead: profile
scrolling on low-end Android devices before release.

## Verification

```sh
flutter pub get
flutter analyze
flutter test test/miuix_floating_dock_test.dart
flutter test test/miuix_stage2_widgets_test.dart
flutter test test/miuix_ksu_refinement_test.dart
flutter test test/miuix_iconography_test.dart
flutter build apk --debug --dart-define=SYLPHY_EXPERIMENTAL_MIUIX=true
```

Visually inspect Android dark/light modes, 0->3 rapid taps, dragging across
four destinations, gesture/three-button navigation, mini-player vs dock and
scroll content sampled behind the glass. Verify fallback to Material 3 and
there are no regressions in text scaling or selected icon contrast.

Sources (do not copy KernelSU GPL source):
- https://github.com/tiann/KernelSU/blob/main/manager/app/src/main/java/me/weishu/kernelsu/ui/component/FloatingBottomBar.kt
- https://github.com/tiann/KernelSU/blob/main/manager/app/src/main/java/me/weishu/kernelsu/ui/component/bottombar/BottomBarMiuix.kt
- https://github.com/ChuxinNeko/flutter_miuix/blob/main/skill/payload/flutter-miuix/SKILL.md
- https://github.com/ChuxinNeko/flutter_miuix/blob/main/skill/payload/flutter-miuix/references/110_os4.zh.md
