/// A bounded number of previous-track entries is enough for user navigation.
const int maxPlaybackHistoryEntries = 300;

List<int> appendPlaybackHistory(List<int> history, int index) {
  final result = [...history, index];
  if (result.length <= maxPlaybackHistoryEntries) return result;
  return result.sublist(result.length - maxPlaybackHistoryEntries);
}

enum PlaybackFailureKind {
  localTicketExpired,
  authentication,
  missing,
  retryable,
}

/// Local proxy ticket expiration must not be confused with remote HTTP 403.
PlaybackFailureKind classifyPlaybackFailure(
  String reason,
  String? proxyFailure,
) {
  if (proxyFailure == 'local_ticket_expired') {
    return PlaybackFailureKind.localTicketExpired;
  }
  if (proxyFailure == '404') return PlaybackFailureKind.missing;
  if (const {'401', '403', 'tls'}.contains(proxyFailure)) {
    return PlaybackFailureKind.authentication;
  }
  final lower = reason.toLowerCase();
  if (RegExp(r'(^|[^0-9])(401|403)([^0-9]|$)').hasMatch(lower) ||
      lower.contains('certificate')) {
    return PlaybackFailureKind.authentication;
  }
  return PlaybackFailureKind.retryable;
}

/// A paused mpv HTTP source may keep a stale connection and a short-lived
/// loopback ticket. Reopen only proxied media, preserving local/cached files.
/// A clock jump is treated conservatively as a request to refresh the source.
bool shouldRefreshRemotePlaybackSource({
  required DateTime? ticketIssuedAt,
  required DateTime? pausedAt,
  required DateTime now,
  required Duration ticketLifetime,
  Duration refreshBeforeExpiry = const Duration(minutes: 5),
  Duration maxPausedAge = const Duration(minutes: 15),
}) {
  if (ticketIssuedAt == null) return false;
  final ticketAge = now.difference(ticketIssuedAt);
  if (ticketAge.isNegative ||
      ticketAge >= ticketLifetime - refreshBeforeExpiry) {
    return true;
  }
  if (pausedAt == null) return false;
  final pausedAge = now.difference(pausedAt);
  return pausedAge.isNegative || pausedAge >= maxPausedAge;
}

/// An old mpv HTTP/loopback source can be unusable even when its ticket has
/// not yet expired. Reopen only remote sources actually using the local proxy.
bool shouldReopenPausedProxy({
  required bool usingProxy,
  required DateTime? pausedAt,
  required DateTime now,
  Duration maxPause = const Duration(minutes: 15),
}) {
  if (!usingProxy || pausedAt == null) return false;
  final age = now.difference(pausedAt);
  return age.isNegative || age >= maxPause;
}

/// A complete cache file still has an mpv decoder/AudioTrack that can become
/// unusable after long Android process suspension. Reopen the file, not the
/// network source, while preserving the queue's stored position.
bool shouldReopenPausedCache({
  required bool usingCompleteCache,
  required DateTime? pausedAt,
  required DateTime now,
  Duration maxPause = const Duration(minutes: 15),
}) {
  if (!usingCompleteCache || pausedAt == null) return false;
  final elapsed = now.difference(pausedAt);
  return elapsed.isNegative || elapsed >= maxPause;
}

/// A stale native play completion is not proof of audible progress. A retry
/// must remain tied to the same user intent, song and granted audio focus.
bool mayRecoverUnconfirmedResume({
  required bool stillCurrent,
  required bool playRequested,
  required bool userPaused,
  required bool focusLost,
  required bool progressConfirmed,
  required bool recoveryRunning,
}) =>
    stillCurrent &&
    playRequested &&
    !userPaused &&
    !focusLost &&
    !progressConfirmed &&
    !recoveryRunning;
