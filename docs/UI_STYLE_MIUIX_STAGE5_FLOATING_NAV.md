# Stage 5: real floating dock and continuous Miuix selection

**Base:** Stage 1, Stage 2, Stage 2 refinement, Stage 3, Stage 4 applied in that order.

- Existing `SylphyShell` still owns tabs, search, playback and queues; no new shell or route.
- Android Miuix portrait uses `Scaffold.extendBody: true`. Content paints behind the dock's transparent margins; the mini-player is now raised above the dock by its measured height (bar + gaps + one gesture inset); page bottoms reserve the same height. Check gesture and 3-button navigation.
- The dock has one `AnimatedPositionedDirectional` selection indicator. On quick successive taps it continues from the current position toward the new target. `MediaQuery.disableAnimations` disables that motion.
- The 4 (2–5 supported) tab icons have **full-opacity** Miuix `onSurface` foreground when inactive. No `MiuixNavigationBarItem` state alpha multiplier.
- Personal shortcuts retain their original 2-column layout and callbacks; Miuix removes the M3 inner `primaryContainer` icon tile and uses semantic icon color directly on the Miuix card. The music-management group uses the native Miuix card, while the Material branch keeps `Card.outlined`.
- The existing Material 3 bottom bar is unchanged by Stage 5.

Run:

```sh
flutter analyze
flutter test test/miuix_floating_dock_test.dart
flutter test test/miuix_stage2_widgets_test.dart test/miuix_ksu_refinement_test.dart
flutter build apk --debug --dart-define=SYLPHY_EXPERIMENTAL_MIUIX=true
```

Visual verification: tapping 0→3 and 3→1, drag/gesture navigation; translucent gaps reveal scroll content; no white rectangular strip behind dock; normal and large fonts; active/inactive glyph contrast in light/dark modes; mini-player does not overlap dock or the last library item; gestures and back navigation remain usable.

This work does not change playback services or the PlayerLayoutStore.
