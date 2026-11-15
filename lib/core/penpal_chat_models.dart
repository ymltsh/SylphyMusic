class PenpalChatMessage {
  const PenpalChatMessage({
    required this.role,
    required this.content,
    this.id,
    this.createdAtMs = 0,
  });

  final int? id;
  final String role;
  final String content;
  final int createdAtMs;

  factory PenpalChatMessage.fromRow(Map<String, Object?> row) =>
      PenpalChatMessage(
        id: row['id'] as int,
        role: row['role'] as String,
        content: row['content'] as String,
        createdAtMs: row['created_at_ms'] as int,
      );
}
