/// A short note the user deliberately sends to one penpal. This is not an
/// inferred preference and never becomes long-term memory automatically.
class PenpalMailboxNote {
  const PenpalMailboxNote({
    required this.id,
    required this.cardId,
    required this.content,
    required this.status,
    required this.revision,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.relatedLetterKey = '',
    this.replyLetterId,
    this.replyTitle = '',
    this.replyContent = '',
  });

  final int id;
  final String cardId;
  final String content;
  final String status; // pending / answered / withdrawn
  final int revision;
  final int createdAtMs;
  final int updatedAtMs;
  final String relatedLetterKey;
  final int? replyLetterId;
  final String replyTitle;
  final String replyContent;

  bool get isPending => status == 'pending';

  factory PenpalMailboxNote.fromRow(Map<String, Object?> row) =>
      PenpalMailboxNote(
        id: row['id'] as int,
        cardId: row['card_id'] as String,
        content: row['content'] as String,
        status: row['status'] as String,
        revision: row['revision'] as int,
        createdAtMs: row['created_at_ms'] as int,
        updatedAtMs: row['updated_at_ms'] as int,
        relatedLetterKey: row['related_letter_key'] as String? ?? '',
        replyLetterId: row['reply_letter_id'] as int?,
        replyTitle: row['reply_title'] as String? ?? '',
        replyContent: row['reply_content'] as String? ?? '',
      );
}
