# Shared header capsule and smooth collapsible toolbars (MD3 / Miuix)

- Both styles use **one search + settings capsule**; when folded, a separate **circular More** appears immediately beside it on the same `AppBar` row.
- The More menu retains the exact existing LibraryBrowser callbacks for playback, locate, selection and playlist actions. `LibraryBrowser` publishes those callbacks to an optional `ValueNotifier` after a frame, not while building.
- Library and playlist toolbars use one `SylphyAnimatedToolbar` (`AnimatedCrossFade`, 320ms) so their **heights and opacity** interpolate together, with no row jumping at the end.
- `SylphyToolbarScrollTracker` waits for a sustained 24dp upward / 28dp downward scroll to avoid flicker from tiny reversals, expands automatically near scroll offset zero, and never creates or resets a scroll controller.
- MD3 and Miuix share all state and callbacks; only the surface and press feedback differ.
- Full app `SylphyShell` and existing `LibraryBrowser` SQL paging, queue state, album Cover Flow, and `PlaylistReorderGrid` remain untouched by the style separation.

Validate on Android with both UI styles: scroll quickly, reverse direction, use the More submenus, change the library category, select tracks, and verify that the player and scroll position persist. Disable animations via system accessibility settings to verify immediate transitions.

```
flutter analyze
flutter test test/adaptive_header_pill_motion_test.dart
flutter test test/adaptive_collapsing_chrome_test.dart
```
