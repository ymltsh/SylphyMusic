# Local audio_service patch

Vendored from the locked pub.dev `audio_service` 0.18.19 package
(archive SHA-256: `95f3267f3449eb5cf71c8fcf1d556f57af1e898e2dc5815fb168d1843653edb7`).
Runtime sources, package metadata, upstream documentation and MIT license are
preserved; upstream examples and tests are omitted.

Local change: on Android 10 (API 29), notifications with three media actions
use `DecoratedMediaCustomViewStyle` with a custom RemoteViews layout that keeps
the transport icons white. Artwork-derived coloring remains enabled; action
icons, accessibility descriptions and PendingIntents come from existing actions.
Other versions and action counts retain the upstream media style.
The layout is `android/src/main/res/layout/audio_service_media_controls_q.xml`.
This supersedes the earlier Android 10 `setColorized(false)` workaround.

`getResourceId` resolves the seven standard transport icons using explicit
`R.drawable` references before falling back to dynamic lookup for custom names.
The release resource shrinker otherwise cannot see icon names supplied by Dart
and removes the glyphs even though the clickable RemoteViews buttons survive.

The app uses this directory through its `pubspec.yaml` path dependency. When
upgrading the upstream package, review and reapply this change.
