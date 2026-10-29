# Local audio_service patch

Vendored from the locked pub.dev `audio_service` 0.18.19 package
(archive SHA-256: `95f3267f3449eb5cf71c8fcf1d556f57af1e898e2dc5815fb168d1843653edb7`).
Runtime sources, package metadata, upstream documentation and MIT license are
preserved; upstream examples and tests are omitted.

Local change: `AudioService.java` calls `builder.setColorized(false)` only on
Android 10 (API 29), after configuring the media style. This opts out of
artwork-derived notification coloring while retaining artwork and actions.

The app uses this directory through its `pubspec.yaml` path dependency. When
upgrading the upstream package, review and reapply this change.
