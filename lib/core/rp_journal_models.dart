/// An evidence-backed, character-scoped diary entry.
class RpJournalEntry {
  const RpJournalEntry({
    required this.id,
    required this.day,
    required this.conversationKey,
    required this.text,
    required this.createdAtMs,
  });

  final int id;
  final String day;
  final String conversationKey;
  final String text;
  final int createdAtMs;

  factory RpJournalEntry.fromRow(Map<String, Object?> row) => RpJournalEntry(
    id: row['id'] as int,
    day: row['local_day'] as String,
    conversationKey: row['conversation_key'] as String,
    text: row['body'] as String,
    createdAtMs: row['created_at_ms'] as int,
  );
}

class RpContinuity {
  const RpContinuity({
    this.self = '',
    this.user = '',
    this.relationship = '',
    this.openThreads = '',
    this.avoidRepetition = '',
    this.revision = 0,
    this.invalidated = false,
  });

  final String self;
  final String user;
  final String relationship;
  final String openThreads;
  final String avoidRepetition;
  final int revision;
  final bool invalidated;

  factory RpContinuity.fromRow(Map<String, Object?> row) => RpContinuity(
    self: row['self_note'] as String? ?? '',
    user: row['user_facts'] as String? ?? '',
    relationship: row['relationship'] as String? ?? '',
    openThreads: row['open_threads'] as String? ?? '',
    avoidRepetition: row['avoid_repetition'] as String? ?? '',
    revision: row['revision'] as int? ?? 0,
    invalidated: row['invalidated'] == 1,
  );

  Map<String, String> asContext() => {
    if (self.trim().isNotEmpty) 'role_self_view': self,
    if (user.trim().isNotEmpty) 'confirmed_user_facts': user,
    if (relationship.trim().isNotEmpty) 'relationship_history': relationship,
    if (openThreads.trim().isNotEmpty) 'unfinished_threads': openThreads,
    if (avoidRepetition.trim().isNotEmpty)
      'topics_not_to_proactively_repeat': avoidRepetition,
  };
}

class RpJournalTurn {
  const RpJournalTurn({
    required this.id,
    required this.conversationKey,
    required this.user,
    required this.assistant,
    required this.occurredAtMs,
  });

  final int id;
  final String conversationKey;
  final String user;
  final String assistant;
  final int occurredAtMs;

  factory RpJournalTurn.fromRow(Map<String, Object?> row) => RpJournalTurn(
    id: row['id'] as int,
    conversationKey: row['conversation_key'] as String,
    user: row['user_text'] as String,
    assistant: row['assistant_text'] as String,
    occurredAtMs: row['occurred_at_ms'] as int,
  );
}

class RpJournalSnapshot {
  const RpJournalSnapshot({
    required this.continuity,
    required this.entries,
    required this.pending,
  });

  final RpContinuity continuity;
  final List<RpJournalEntry> entries;
  final int pending;
}
