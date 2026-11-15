# SylphyMusic Android background resume V3

Baseline: the GitHub `main` files read on 2026-11-09, including
`lib/services/playback.dart` blob `51e01e6e12d4cac0999014f649270128ea79c67a`
and `AudioService.java` blob `f348250c554d0693dafacc5055c3c6e8cf6ce430`.
The source already contains earlier V1/V2 work. This patch is **incremental**;
do not apply old V1/V2 patches again. Run `git apply --check` first.

## Confirmed observations motivating this change

- Diagnostic logs contain `native_play_completed` and `playing_changed=true`
  **without** `progress_resumed` for a track previously opened as
  `cached_file_open`; later `progress_stalled` appears.
- Some recovery attempts were interrupted by audio-focus loss. Auto recovery
  must not force output while focus is lost or a later pause/skip is in flight.
- A system snapshot shows a live, bound AudioService with `BUFFERING`, but no
  active foreground service. A snapshot alone cannot prove which FGS call failed.
- No evidence supports modifying UI CPU work, using permanent wakelocks or
  force-restarting a foreground service while Android prohibits it.

## Behaviour

1. After a pause >= 15 min, a fully cached remote file is reopened as the
   **same song** with its saved position. Local-library files and fresh cache
   resumes still use the existing fast `play()` path; proxy refresh remains.
2. For Android local and complete-cache resumes, a 12-second check waits
   for **actual progress**, not a `playing=true` event. If no progress appears,
   and the track/intent/navigation/focus are unchanged, it saves the position
   and attempts at most one serialized same-track reload. If the reopened song
   still does not progress, it stops with a clear error instead of skipping.
   Remote-proxy streaming retains its 45-second stall watchdog, to avoid
   treating ordinary upstream buffering as a decoder failure. The check is
   cancelled on progress, pause, seek, new load and shutdown. Android may
   delay timers while frozen; callbacks revalidate all conditions before action.
3. The generic stall watchdog skips HTTP proxy health checks on cached or
   local files. An interruption cancelling a recovery is explicitly logged.
4. On a new native media play gesture, AudioService reasserts startForeground
   even if its previous in-process state says it is already promoted. This
   does **not** call startForegroundService again or bypass OEM/Android denial.
   If denied, it drops the stale in-process foreground flag and WakeLock.

## Diagnostics added

Dart `resume_cached_reopen`, `resume_progress_timeout` (stage=cached/other),
`resume_same_track_reopen`, `resume_same_track_failed`,
`resume_progress_failed`, `resume_recheck_cancelled`, `stall_proxy_not_used`,
`stall_recovery_cancelled`.
Android logcat tag `SylphyMedia`: `fgs_reaffirmed` or
`fgs_reaffirm_denied`. None of these events contains song URLs or tokens.

## Validation

```bash
flutter test test/playback_reliability_test.dart
# Also run the project's full flutter test suite and Android debug build.
```

Check on the affected Xiaomi device with opt-in diagnostics and logcat:
- cached track, pause 1 min: ordinary play, real progress within 12s
- cached track, pause 20+ min: `resume_cached_reopen`, same track/position
- shorter pause that reproduces a local decoder stall: one bounded
  `resume_same_track_reopen` followed by success or `resume_progress_failed`
- audio focus loss during timer/reload: no forced playback or stale overwrite
- repeated pause, seek, skip: no late reopen and no permanent BUFFERING
- compare MediaSession speed/position with actual audio progression, and
  preserve system `fgs_reaffirm_denied` if the OEM rejects FGS promotion.

The patch cannot override Android FGS restrictions or guarantee timers run
while an OEM freezes the process. Further system logcat is still required if
foreground promotion is denied on the device.
