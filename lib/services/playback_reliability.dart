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
