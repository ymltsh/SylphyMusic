# Stage 6: KSU icon treatment and shorter liquid-glass dock

**Base:** Stage 1, Stage 2, Stage 2 refinement, Stage 3, Stage 4, Stage 5.

- The Miuix dock now targets a more KernelSU-like visual weight: shorter (58dp), narrower (`maxWidth: 448`), with reduced outer padding.
- `BackdropFilter` is back, but kept inside the dock clip so the blur remains local to the pill. A light highlight gradient is layered above it to imitate a liquid-glass surface without switching the app to the full OS4 Glass preset.
- The moving selection indicator remains a single traveling squircle; its easing uses the Miuix standard decelerate curve.
- Unselected tabs keep readable, full-opacity foreground colors.
- Quick action icons and the music-space header icon use a small KSU-like treatment in Miuix mode: soft tinted container, primary glyph, no Material 3 `primaryContainer` card-in-card appearance.
- Settings entry icons in Miuix mode become plain colored glyphs without the Material square background.

Run:

```sh
flutter analyze
flutter test test/miuix_floating_dock_test.dart
flutter build apk --debug --dart-define=SYLPHY_EXPERIMENTAL_MIUIX=true
```

Visual checks:

- Dock appears truly floating, with visible blur/glass between the content and the pill.
- The dock width is closer to KernelSU and does not span edge-to-edge on normal phones.
- Quick icons on “我的” and the music-space card look like KSU-style Miuix icons rather than plain Material tiles.
- Settings list icons are no longer wrapped by a Material badge in Miuix mode.

Open question for product review: whether other list pages (favorites, cache tasks, source cards) should also move to this icon treatment, or keep plain line icons to avoid visual noise.
