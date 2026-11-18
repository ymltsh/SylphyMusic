/// A long-term RP memory unit. Day/week/month differ in density, not status.
class RpJournalEntry {
  const RpJournalEntry({
    required this.id,
    required this.level,
    required this.periodKey,
    required this.startDay,
    required this.endDay,
    required this.text,
    required this.revision,
    required this.sourceCount,
    required this.updatedAtMs,
  });

  final int id;
  final String level; // day, week, month
  final String periodKey;
  final String startDay;
  final String endDay;
  final String text;
  final int revision;
  final int sourceCount;
  final int updatedAtMs;

  String get day => startDay;

  factory RpJournalEntry.fromRow(Map<String, Object?> row) => RpJournalEntry(
    id: row['id'] as int,
    level: row['level'] as String,
    periodKey: row['period_key'] as String,
    startDay: row['start_day'] as String,
    endDay: row['end_day'] as String,
    text: row['body'] as String,
    revision: row['revision'] as int? ?? 0,
    sourceCount: row['source_count'] as int? ?? 0,
    updatedAtMs: row['updated_at_ms'] as int,
  );
}

/// Raw, auditable interaction evidence. Not itself a long-term memory unit.
class RpJournalTurn {
  const RpJournalTurn({
    required this.id,
    required this.conversationKey,
    required this.user,
    required this.assistant,
    required this.occurredAtMs,
    required this.localDay,
  });
  final int id;
  final String conversationKey;
  final String user;
  final String assistant;
  final int occurredAtMs;
  final String localDay;

  String get day {
    if (localDay.isNotEmpty) return localDay;
    final date = DateTime.fromMillisecondsSinceEpoch(occurredAtMs);
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  factory RpJournalTurn.fromRow(Map<String, Object?> row) => RpJournalTurn(
    id: row['id'] as int,
    conversationKey: row['conversation_key'] as String,
    user: row['user_text'] as String,
    assistant: row['assistant_text'] as String,
    occurredAtMs: row['occurred_at_ms'] as int,
    localDay: row['local_day'] as String? ?? '',
  );
}

class RpJournalSnapshot {
  const RpJournalSnapshot({
    required this.entries,
    required this.pending,
    required this.drafts,
  });
  final List<RpJournalEntry> entries;
  final int pending;
  final List<RpJournalTurn> drafts;

  Iterable<RpJournalEntry> ofLevel(String level) =>
      entries.where((item) => item.level == level);
}
