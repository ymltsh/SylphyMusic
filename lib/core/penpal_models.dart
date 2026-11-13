/// Compact local memories. The original letters remain in recommendation_letters.
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

  /// Presentation is separate from the factual event, and never adds rules.
  String get displayText {
    if (kind == 'letter_opened') {
      final title = RegExp(r'《[^》]{1,70}》').firstMatch(text)?.group(0);
      if (title != null) return '你翻开过$title。';
    }
    if (kind == 'letter_written') {
      final title = RegExp(r'《[^》]{1,70}》').firstMatch(text)?.group(0);
      if (title != null) return '我写过$title。';
    }
    return text;
  }

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
    required this.soulCustomized,
    required this.personaName,
    required this.entries,
  });

  final bool enabled;
  final bool recallEnabled;
  final String soul;
  final bool soulCustomized;
  final String personaName;
  final List<PenpalMemoryEntry> entries;
}
