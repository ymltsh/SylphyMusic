# Sylphy Android native runtime wrapper

The Java/Gradle packaging wrapper retains the media-kit package identity to keep
Flutter dependencies compatible. It does not create a player or audio session.
The wrapper code is MIT; this does not relicense the packaged native libraries.

The runtime is fetched from the pinned mpv-android 2026-09-17 release by
`tool/prepare_android_mpv.py`. Every upstream APK is verified against its SHA-256
before extracting only the listed native libraries. Original application code,
libplayer.so, permissions and UI are not included. Generated libraries are ignored
and can be reproduced with that script.

Native GPL/LGPL notices and corresponding source/build references are recorded in
`docs/native_licenses/mpv-android-2026-09-17-NOTICE.md`, bundled in Android assets,
and exposed through Flutter's license registry. Windows is unaffected.
