/// A deliberately small memory model. Raw letters stay in recommendation_letters.
class PenpalMemoryEntry {
  const PenpalMemoryEntry({
    required this.id,
    required this.kind,
    required this.text,
    required this.createdAtMs,
    this.relatedLetterKey,
    this.topic = '',
    this.pinned = false,
  });

  final int id;
  final String kind;
  final String text;
  final String? relatedLetterKey;
  final String topic;
  final int createdAtMs;
  final bool pinned;

  factory PenpalMemoryEntry.fromRow(Map<String, Object?> row) =>
      PenpalMemoryEntry(
        id: row['id'] as int,
        kind: row['kind'] as String,
        text: row['text'] as String,
        relatedLetterKey: row['related_letter_key'] as String?,
        topic: row['topic'] as String? ?? '',
        createdAtMs: row['created_at_ms'] as int,
        pinned: row['pinned'] == 1,
      );
}

class PenpalMemorySnapshot {
  const PenpalMemorySnapshot({
    required this.enabled,
    required this.recallEnabled,
    required this.soul,
    required this.entries,
  });

  final bool enabled;
  final bool recallEnabled;
  final String soul;
  final List<PenpalMemoryEntry> entries;
}
