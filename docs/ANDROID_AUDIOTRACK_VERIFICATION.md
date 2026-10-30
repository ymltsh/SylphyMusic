# Android AudioTrack A/B validation (experimental)

This patch is for investigating short crackling / popping when switching Android apps under load. It is **not** a verified fix and should not be merged into `main` without real-device tests.

## Scope

- Android only: request `ao=audiotrack,opensles,` before opening tracks.
- Keep the original media_kit backend if the request throws; mpv may also silently ignore the request.
- After playback position advances past 500 ms, log `current-ao` once per track.
- No changes to `audio-buffer`, FLAC decoding, HTTP relay, cache policy, foreground lifecycle, or audio focus.
- Other platforms are unchanged.

## Build and test

1. Create a clean branch from `main`, apply the patch, and build a **release** APK. Compare with the same commit of `main` built in release mode.
2. Enable **Settings → Diagnostics and Feedback → Record diagnostic logs** before playback.
3. In **Settings → Downloads & Cache → Cache Storage**, confirm the test FLAC is in the complete-cache list. Stop and reopen that exact song after caching, so the new play uses the local file instead of an older HTTP proxy URL.
4. Check for `cached_file_open` (not `remote_ticket_open`) plus `audio_output_selected` in the diagnostic export.
5. Play the same 30MB+ FLAC through the same output device. Repeat opening/closing WeChat and switching back to the music app 20 times for each build. Record the number of audible pops.
6. Repeat with speaker versus Bluetooth (if relevant). Record Android version and phone model.

Expected opt-in log entries on the patched build:

```json
{"scope":"playback","event":"audio_output_override_requested"}
{"scope":"playback","event":"cached_file_open"}
{"scope":"playback","event":"audio_output_selected","type":"audiotrack"}
```

`audio_output_override_requested` is **not** proof that the driver switched. `audio_output_selected` reports the runtime backend: `audiotrack`, `opensles`, `aaudio`, `null`, `other`, or `unavailable`. If `opensles` still appears, the test has not verified an AudioTrack switch. If the probe is unavailable, use Android logcat (AudioTrack, AudioFlinger, mpv) for native evidence.

No additional diagnostic field keys are required: the existing allowlisted `type` key is used. This code intentionally does not record URLs, track names, or credentials.

## Interpretation

- AudioTrack confirmed, fewer pops: an AO-backend-specific issue is more plausible.
- AudioTrack confirmed, unchanged pops: next isolate output buffering and underruns rather than changing multiple things at once.
- OpenSL ES or unavailable: do not count the patched run as an AudioTrack experiment.
- Audio is silent or behaves worse: stop the test and revert this patch.

## Revert

On the local verification branch, revert the patch with `git apply -R SylphyMusic-android-audiotrack-validation.patch` (from the repository root, using the path to the patch). If committed, revert the test commit instead.
