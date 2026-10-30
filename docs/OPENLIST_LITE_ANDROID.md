# SylphyMusic OpenList Edition (Android arm64) — preview

> Branch: `feature/android-openlist-lite` · Proposed app version:
> `1.0.14-openlist.1+27` · Base: `1f5427be7546050373a1af7e81eb51203dfe9296`
>
> The original archive is a **source patch** without a precompiled AAR/APK.
> The local Windows environment has now compiled the AAR and arm64 Release APK;
> Android device behavior remains to be verified by the maintainer.

## Scope

- Same-package native Go OpenList server behind 127.0.0.1:5244 (not LAN-facing)
- Upstream v4.2.9, entire `drivers` registry and bundled frontend Web UI
- Flutter Settings → OpenList Lite → native WebView; default `admin` login
- Smart mode: start for Web UI, scanning, WebDAV file requests or network audio;
  stop after ~3 minutes without a lease. Continuous mode: user-triggered
  `specialUse` foreground service + ongoing notification and switch-to-smart action.
- Use existing SylphyMusic WebDAV music source (read-only): URL
  `http://127.0.0.1:5244/dav/`. Create a dedicated read-only OpenList user from
  the Web UI and use its credentials in SylphyMusic rather than the admin account.
- Standalone Android application ID `com.ymltsh.sylphymusic.openlist`, so the
  app can coexist with the original edition. Application data cannot be shared
  automatically between the editions.

## Apply the patch

From a clean SylphyMusic clone at the expected main baseline, run:

```bash
python3 /path/to/patch/apply.py /path/to/SylphyMusic --dry-run
python3 /path/to/patch/apply.py /path/to/SylphyMusic
# Creates feature/android-openlist-lite locally, leaves main untouched.
```

## Build

Requirements: Android SDK/NDK, Java 17, Flutter SDK, Go toolchain required by
upstream (`go.mod` requests go1.26.0 / toolchain go1.27.3), `gomobile`, internet
access for upstream source/frontend/module dependencies, and adequate disk space.

```bash
# At the SylphyMusic repository root
go install golang.org/x/mobile/cmd/gomobile@v0.0.0-20261011034528-197770444867
export PATH="$(go env GOPATH)/bin:$PATH"
bash tools/openlist_lite/build_openlist_aar.sh
flutter pub get
flutter build apk --release --split-per-abi --target-platform android-arm64
```

The script uses `.private/openlist-native` for temporary upstream sources and declares the pinned `gobind` tool dependency before binding.

The AAR is generated into `android/app/libs/openlistlib.aar`. It is **not**
committed or distributed in this patch. Before release, verify and record the
pinned upstream source SHA, frontend archive digest, AAR digest and APK digest.

## v0.3 packaging and initialization fix

The build script defaults to the Lite frontend, preserving the full Go driver registry. Set `OPENLIST_FRONTEND_VARIANT=full` to embed the full frontend in a new build workspace. Android uses `useLegacyPackaging = true` to compress native libraries inside the APK; this reduces download size, not the installed library size or runtime memory. Inspect the package with `python tools/openlist_lite/apk_size_report.py PATH_TO_APK`.

OpenList v4.2.9 does not automatically provision an administrator on a fresh database unless explicitly configured. The embedded bridge now creates a missing administrator with the per-install Keystore-protected initial password, matching the upstream setup wizard's account fields and password hashing. Existing administrators and their passwords are preserved even when the old marker is absent. Provisioning can retry without reinitializing the database within the same process; passwords are never printed to logs by this provisioning path. No database deletion is required for the previous `record not found` startup failure.

## Initial provisioning

1. Open Settings → OpenList Lite. Leave Smart selected or opt into Continuous.
2. Tap OpenList Web UI. Admin username is `admin`; the per-install initial
   password can be viewed in the settings page. Password is encrypted with a key
   in Android Keystore. The bootstrap password is installed only once; changing
   the admin password in OpenList Web UI does not reset it on app restart.
3. Add a storage mount via OpenList Web UI; create a *separate read-only account*
   with access only to required music mounts.
4. Add an existing SylphyMusic WebDAV source using the localhost URL and
   read-only account, then scan and play music as usual.
5. When switching from Continuous to Smart, the notification is removed; the
   server remains alive while active leases exist and stops after an idle grace.

## Android behavior and limitations

- Android can terminate any background process. `START_STICKY` does not promise
  an unkillable service; users can force-stop it or enable battery restrictions.
- Continuous mode uses `FOREGROUND_SERVICE_SPECIAL_USE`, requiring a documented
  qualifying user-visible use case. **Google Play approval is not assured**.
  If distribution policy rejects that category, choose an alternative compliant
  distribution/runtime design. Do not disguise continuous server activity as
  `mediaPlayback` or `dataSync` (the latter has a six-hour limit for target 35+).
- The same-process Go runtime must pass Android repeated Start/Stop tests;
  OpenList upstream does not promise unlimited in-process restart cycles.
- Web UI is embedded in an Android WebView. HTTPS links such as external OAuth
  login flows are opened in the system browser; auth callback behavior depends
  on individual storage providers and needs per-driver validation.
- The fixed port 5244 is checked before startup, and conflicts fail explicitly.
  There is intentionally no silent fallback to a different server.
- Credentials must never be sent to untrusted origins; WebView navigation is
  restricted to the local origin or an external HTTPS browser intent.
- Smart mode holds scanning and playback leases; other background prefetch/
  cache operations may need more detailed lease integration after instrumented
  device tests. Do not treat this patch as a production-grade finished release.
- Dependency source and embedded Go code are subject to OpenList's AGPL-3.0;
  distributing an APK requires license review, notices and corresponding-source
  obligations. SylphyMusic's original MIT code remains under its original terms.

## Test matrix before release

- Clean installation and first-run admin password; no credential or token logs
- Reopening Web UI and authentication after process restart
- Full driver list visible in Web UI; test mounts: 115, 123, Aliyun, Quark and
  at least one standards-based WebDAV/S3 source
- Audio MP3/FLAC and HTTP Range 206 responses; seek, buffering, lyrics, cover
- Concurrent streaming and sync; pause, resume, rapid mode switches
- 20× repeated start/stop, process death, force stop, device sleep, reboot
- Android 12/13/14/15/16 notification, FGS permissions and background limits
- 127.0.0.1 only; negative tests for port conflict, wrong auth and external URLs
- APK size/idle memory, CPU use, database checkpoint/durability

### Upstream references

- https://github.com/OpenListTeam/OpenList/releases/tag/v4.2.9
- https://github.com/OpenListTeam/OpenList-Mobile
- https://github.com/LeoHaoVIP/AListLiteAndroid
- https://developer.android.com/develop/background-work/services/fgs/service-types

## Separate release/update channel

The edition uses `com.ymltsh.sylphymusic.openlist` and isolated local
`version.json` / `version-beta.json` with `latest: null`. The app update client
fetches from `feature/android-openlist-lite`, NOT `main`: a mainline APK must
never be installed as an OpenList Edition update. Add signed OpenList Edition
release assets to its branch-specific manifest only after CI and device checks.

## Remote branch

The patch creates a local branch. The connected GitHub integration rejected
remote branch creation with HTTP 403; after review and verification, a
maintainer with push access may publish it using
`git push -u origin feature/android-openlist-lite`.
