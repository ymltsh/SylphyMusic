# SylphyMusic playback runtime / audio-focus architecture refactor

Baseline: `ymltsh/SylphyMusic` `main` commit
`39f0b88f261c59668983a25672d314ace46e50a1` (2026-11-09).
`lib/services/playback.dart` blob `e2ab6f161f7c4f9b626cc7bd0154dad4b3ba85bb`.
This patch supersedes older focus-state code on the current branch; it does **not**
require applying V1, V2 or V3 patches. Those changes are already in this commit.

## Evidence and upstream parallels

- Xiaomi Android 14: two cached-file resumes accepted `native.play()` but had
  no real position progress; `progress_stalled` followed; audio-focus callbacks
  appeared in the same windows. An Android snapshot separately showed a bound
  service and BUFFERING session, without an effective foreground service.
  Neither observation alone proves an OS FGS exception at the exact failure.
- Linthra [#244](https://github.com/TheZupZup/Linthra/pull/244) diagnosed
  overlapping focus transport, repeated transient losses canceling recovery,
  and a Dart isolate losing execution when audio_service demoted on pause.
- Linthra [#587](https://github.com/TheZupZup/Linthra/pull/587) replaced
  `androidStopForegroundOnPause: false` (holds a WakeLock even on a long manual
  pause) with a *bounded transient-focus-only* media-session `playing` hold.
- Linthra [#826](https://github.com/TheZupZup/Linthra/issues/826) / [#875](https://github.com/TheZupZup/Linthra/issues/875)
  show that an invalid source while paused and an automatic focus resume must
  use the same underlying source-reopen logic as a user Play.
- Android audio-focus policy: <https://developer.android.com/media/optimize/audio-focus>.
  A permanent loss does not entitle an automatic resume. Playback must not begin
  until focus is granted. Background FGS restrictions cannot be bypassed.

## Resource ownership — no second player or service introduced

| Resource | One owner | Lifetime |
|---|---|---|
| `media_kit`/libmpv player + `NativeCommandGate` | `PlaybackCoordinator` | FlutterEngine / playback runtime |
| queue and on-disk playback state | `PlaybackCoordinator` / `SylphyApp` | restored without autoplay |
| proxy tickets, READY cache | existing `MediaProxy` and `CacheManager` | controlled by app/source lifetime |
| Android Service, MediaSession, FGS and WakeLock | existing `AudioService` | Android service lifetime |
| FlutterEngine cache and binding | existing `AudioServicePlugin` | app/service engine lifetime |
| temporary resume entitlement | **new pure `TransientFocusPolicy<TrackRef>`** | a single short-lived focus interruption |
| Flutter UI | `SylphyShell` | display only, never owns native audio |

The prior `PlaybackCoordinator` already owns the only `Player` and uses the only
`NativeCommandGate`. Neither is recreated by this refactor. No new Android
Service, separate focus-driven native queue, or periodic background poller is
introduced. Existing native player replacement-on-timeout and V3 progress
revalidation remain bounded safeguards, not the primary focus recovery path.

## State and transition contract

The legacy `_playRequested` continues to mean a native playback request that
has not been canceled. A **different** condition—`_focusRecovery.foregroundHeld`
—retains the listener's *automatic resume entitlement*, even after
`pause(system:true)` resets `_playRequested`. The new policy alone owns that
entitlement, its blocked state, and the affected track identity. The
coordinator owns the 5-minute expiry timer and platform effects.

| Event | Native audio | Automatic resume entitlement | MediaSession `playing` | Clock speed |
|---|---|---|---|---|
| user Play + focus granted | play | none | true | >0 **only** with confirmed progress |
| loading/rebuffering under live request | preparing | none | true | 0 until real progress |
| temporary focus loss while playing | pause | retained (max 5 min) | true (FGS remains) | 0 |
| repeated temporary focus loss | stays paused | **not canceled** | true | 0 |
| matching focus regain | resume after stable delay | retained until progress | true | 0 until progress |
| actual media progress | play | released | true by `_playRequested` | media speed |
| manual Pause, headset toggle cancel | pause | revoked immediately | false | 0 |
| permanent focus loss | pause | revoked | false | 0 |
| transient hold timeout | remains paused | revoked | false unless playback is actively requested | 0 when paused |
| focus request denied on manual Play | no native play/open | revoked | false | 0 |

The media-session `playing` bit means an **eligible running media service**, not
proof that sound is advancing. The existing `MediaNotificationClock` remains
responsible for the **real** position speed; held-focus pauses publish 0. This
mimics the Linthra #587 distinction without replacing the existing mpv clock.

## What is removed / consolidated

- Deletes `_resumeOnFocusGain`, `_focusResumeRef`, `_focusLossCount`,
  `_focusBurstStarted` and the accidental "second transient loss suppresses
  resume" rule. Multiple focus events cannot separately rewrite the same
  resume right.
- Replaces those flags with `TransientFocusPolicy`. The old separate
  `_focusWasLost` mutable flag becomes a getter from this single policy.
- The focus event handler only **decides** the interruption and uses the
  existing `pause()` / `play()` + `NativeCommandGate` transport. No extra native
  engine and no parallel focus command queue.
- `play()` now requests audio focus *before* selecting either the direct
  `native.play()` or cache/proxy reload branch. Focus denial cannot silently
  return early into native media opening. It checks request/navigation/focus
  generations after the async call; a superseded request cannot start.
- `player.open(...play:)` and `native.play()` recheck the authoritative focus
  block. A focus loss arriving during an awaited native play is followed by
  native pause, regardless of whether that play was manual or automatic.
- A headset's Play/Pause toggle treats a temporary focus hold as a **pauseable
  live session**, not as a stopped player that should try to play over a call.
- Keeps the V3 complete-cache re-open and real-progress confirmation. Does not
  add another stall watchdog, unconditional proxy restart, or next-track skip.

## Service lifecycle and battery

The existing `AudioService` foreground promotion path handles user media
buttons on the native side before waiting for Dart. The refactor changes the
*reason* for retaining an already-promoted FGS during a temporary interruption.
It does not request a prohibited new FGS while backgrounded. On ordinary user
pause `playing` becomes false, `audio_service` is still configured to demote
on pause and releases its WakeLock; the default is not changed to
`androidStopForegroundOnPause: false`.

5 minutes is a provisional maximum, borrowed from Linthra's device-tested
follow-up. Repeated losses cannot extend it indefinitely. Expiry revokes
automatic resume; user Play remains available. It is a **maximum policy**,
not a guarantee that a frozen Dart Timer executes on time. The FGS already
being held increases the opportunity to execute that timer.

`androidWillPauseWhenDucked: true` uses explicit interruption handling rather
than relying on opaque system duck/unduck to restore media volume. This can
cause brief navigation/voice duck opportunities to pause rather than mix; test
this behavior on the affected device with notifications, calls, navigation and
Bluetooth.

## Tests and release gate

New pure-Dart `test/transient_focus_policy_test.dart` covers repeated losses,
revoked manual pause, permanent loss, resume pending during another loss,
expiry, and progress-confirmed FGS release. Existing
`test/playback_reliability_test.dart` covers NativeCommandGate serial safety
and source-refresh classification. Commands:

```sh
git apply --check SylphyMusic-Playback-Architecture-Focus-Refactor.patch
git apply SylphyMusic-Playback-Architecture-Focus-Refactor.patch
flutter test test/transient_focus_policy_test.dart test/playback_reliability_test.dart
flutter analyze
flutter build apk --release
```

Device matrix: cached track / remote stream; temporary vs permanent focus
loss; repeated speech/phone focus loss; manual pause during focus hold; headset
play/pause/next; resume after 1, 20 and 120 minutes; locked screen; releasing
FGS and WakeLock on long manual pause; Android Auto; foreground promotion
rejected. Export matching `SylphyMedia`, `SylphyLifecycle`, `ActivityManager`,
`AudioManager` logcat and Dart `transient_hold_*` / `progress_resumed` events.
Compare actual progress, not only MediaSession UI.

### Known boundaries, not claimed solved

- The issue captured by V3 also occurs during **deliberate long user pauses**
  with no focus interruption. This change fixes the focus/FGS pathway but does
  not guarantee recovery from a stale AudioTrack after hours. The existing
  V3 bounded same-track reopen remains necessary while the mpv/audio-output
  root cause is investigated.
- Initial queue autoplay and direct next/previous paths still enter
  `_loadCurrent` outside the explicit `play()` API. The new native open guard
  prevents output *while a known focus block is active*, but a follow-up
  architectural extraction should route **all** autoplay entry points through
  a single focus-admission step. Do not claim full coverage of that invariant
  from this patch alone.
- No real Android device or Flutter/Android SDK was available in the patch
  generation environment. `git apply` was tested against a **sparse validation
  tree of exact GitHub source lines around each hunk**, NOT a full clone.
  Validate against a clean checkout of the commit above before release.
- The engine's `onDestroy`/Activity detach ownership, release-only resource
  shrinking and native AudioTrack state still need independent measurement.
  No speculative changes were made to those lifecycle methods.

## Local integration (2026-11-09)

Applied to the existing main and OpenList workspaces with prior edits preserved.
Four incoming hunks repeated context lines absent from the actual source; their
intended changes were merged against the existing code. OpenList retains its
imports and playback leases, with focus admission after lease acquisition and
asynchronous intent/navigation/focus checks before native playback.

The commands and device matrix above are patch-author recommendations, not
executed validation. Local delivery follows repository policy: release builds
and internal packaging only, without analyze, tests, app launch or device checks.
The supplied policy test is retained for optional user validation. No version
change, commit, push or publication is part of this patch application.
