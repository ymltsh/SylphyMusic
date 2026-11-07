# Android background playback resume patch

This patch changes **resume of a paused remote/loopback media source**, not the
system notification layout or Android's battery optimization settings.

- A proxied `media_kit` source is reopened when it has been paused for 15 minutes
  or its two-hour local ticket is within five minutes of expiry. This obtains
  a new ticket and seeks to the existing saved queue position. Complete cache
  files and local files still use the ordinary fast `play()` path. A clock
  jump also causes a conservative source refresh.
- Waiting **to enter** the native command gate has a 45-second deadline. An
  expired queued command is invalidated; it cannot execute after the lock is
  eventually freed. The app displays an explicit restart-required error in
  this case. The existing per-operation timeout remains separate. Never force
  an overlapping native open or dispose from this timeout path.
- Diagnostic logs now include `resume_source_refresh`, `native_queue_delayed`,
  `native_queue_timeout`, and `proxy.ticket_rejected` with a token-free reason.

## Tests / manual validation

Run with a Flutter SDK:

```sh
flutter test test/playback_reliability_test.dart test/media_proxy_test.dart
```

Test an **installed release build** on Android. While a remote non-READY track
is paused, leave it in the background for at least 15 minutes, then use the
system media controls to resume. The app should log `resume_source_refresh`
followed by `remote_ticket_open` and normal playback progress. Also check
immediate resume (<15 minutes), complete READY cache, local files, audio focus
changes, and repeated rapid play/pause. On devices with real stalls, preserve
logcat and the opt-in diagnostic export before opening the activity.

This patch does not establish that Doze, OEM process reclamation, WAN outages,
or foreground-service restart failures are fixed. Such failures still require
Android lifecycle and device-side evidence; they must not be treated as a local
ticket issue without matching logs.
