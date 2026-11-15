# Android mpv runtime 2026-09-17

The Android edition packages the unmodified native libraries from the upstream
mpv-android 2026-09-17 release. Only the native .so files are used; libplayer.so,
application code, manifests, permissions, UI and settings from that APK are not included.
The Media3 session, JNI bridge, queue, cache leases and source resolver remain Sylphy code.
Windows retains its previous runtime.

- Binary release and complete build dependency list: https://github.com/mpv-android/mpv-android/releases/tag/2026-09-17
- Corresponding application/build scripts: https://github.com/mpv-android/mpv-android/tree/fdf74f6830c47dbaa8a22ac79726e8303f1db5af
- mpv source: https://github.com/mpv-player/mpv/tree/0b7ed670f7c353dd3dd4f8ae0fc788a181a15aa6
- FFmpeg source: https://github.com/FFmpeg/FFmpeg/tree/094a2f8a2a5e7fa64736e067de224ce28fdf5979
- Binary version: mpv v0.41.0-1049-g0b7ed670f; the upstream build includes GPL components.
- The GPL/LGPL texts, component notices and original copyright remain applicable;
  the application's MIT notice does not replace native component licenses.
- Exact binary archive download URLs and SHA-256 checks are maintained in
  tool/prepare_android_mpv.py; do not replace binaries without updating provenance.

The upstream recipe also identifies NDK r30, mbedTLS 3.6.7, dav1d 362bc1138228390a0a521ecf3af18b23c6afeb9e,
libxml2 2.15.4, fontconfig 2.18.3, FreeType 2.14.3, FriBidi 1.0.16,
HarfBuzz 14.4.0, libunibreak 8.0, libass b2fe9d8770678a7b5271387d38c20657ebf3429a,
Lua 5.2.4, libplacebo 3330a515d62139259c26239014f286e233bd3a5c and curl 8.21.0.
Follow the pinned upstream build scripts for the corresponding sources and patches.
Sylphy's release source archive contains its exact bridge, source and runtime preparation code.
