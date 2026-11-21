# Shared collapsible toolbars — Material 3 and Miuix

This is a **core Sylphy UI behavior**, not a Miuix-only feature. Both themes
use the same scroll threshold, layout state, More menus and underlying actions.
Only the gradients, shapes, icon treatment and press feedback adapt to the
currently selected style.

- Both phone UI modes use a subtle semantic-color gradient on the main AppBar
  and its action buttons, unless the user chooses a solid or custom image
  background. No extra Scaffold/Navigator is created.
- After an intentional upward scroll (>56dp), the library summary, filters
  and sorting controls collapse into a single More menu. Downward scroll or
  reaching the top restores the expanded controls.
- Library More retains play all, locate current, category, sort field,
  ascending/descending, album Cover Flow, and active multi-selection actions.
- Playlist More retains create, view mode and sync actions. All share the
  existing controller methods and callbacks across MD3 and Miuix.
- A single `NotificationListener` coordinates folding without replacing the
  existing `LibraryBrowser` SQL paging/ScrollController or the reorderable
  playlist grid. Fold state is reset when switching tabs.
- Reduced-motion settings remove the AnimatedSwitcher transition.
- Desktop/wide/landscape layouts retain their existing tooling because the
  collapse interaction was designed for phone-sized viewports.

## Validate

```sh
flutter analyze
flutter test test/adaptive_collapsing_chrome_test.dart
flutter build apk --debug
flutter build apk --debug --dart-define=SYLPHY_EXPERIMENTAL_MIUIX=true
```

Manual checks in **both styles**: scroll up/down in library and playlists;
open every submenu; play all, locate track, change category/sort/ordering;
enter and exit multi-select; create and sync playlists; verify existing
scroll positions, light/dark modes, image/solid backgrounds, large text,
mini player and Dock overlap, gesture navigation and wide layouts.
