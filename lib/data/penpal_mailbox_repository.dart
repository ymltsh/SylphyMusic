import '../core/penpal_mailbox_models.dart';
import 'app_db.dart';

/// Private, card-scoped outbox. Saving a note never calls an LLM.
class PenpalMailboxRepository {
  const PenpalMailboxRepository(this.database);

  final AppDb database;

  Future<PenpalMailboxNote?> pending(String cardId) async {
    final rows = await database.db.query(
      'penpal_outbox',
      where: "card_id=? AND status='pending'",
      whereArgs: [cardId],
      limit: 1,
    );
    return rows.isEmpty ? null : PenpalMailboxNote.fromRow(rows.single);
  }

  Future<List<PenpalMailboxNote>> history(
    String cardId, {
    int limit = 50,
  }) async {
    final rows = await database.db.rawQuery(
      '''SELECT n.*, COALESCE(l.title, '') AS reply_title,
                COALESCE(l.content, '') AS reply_content
         FROM penpal_outbox n
         LEFT JOIN recommendation_letters l ON l.id=n.reply_letter_id
         WHERE n.card_id=?
         ORDER BY n.created_at_ms DESC,n.id DESC LIMIT ?''',
      [cardId, limit.clamp(1, 100)],
    );
    return rows.map(PenpalMailboxNote.fromRow).toList();
  }

  /// One pending note per character. Edits increment a revision so that an
  /// in-flight generation cannot acknowledge outdated or withdrawn text.
  Future<void> saveOrReplace(
    String cardId,
    String text, {
    String relatedLetterKey = '',
  }) async {
    final normalized = text.trim();
    if (cardId.isEmpty ||
        normalized.isEmpty ||
        normalized.length > 500 ||
        RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]').hasMatch(normalized)) {
      throw const FormatException('留言需要 1–500 字，且不能包含控制字符');
    }
    await database.db.transaction((tx) async {
      final rows = await tx.query(
        'penpal_outbox',
        where: "card_id=? AND status='pending'",
        whereArgs: [cardId],
        limit: 1,
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      if (rows.isEmpty) {
        await tx.insert('penpal_outbox', {
          'card_id': cardId,
          'content': normalized,
          'related_letter_key': relatedLetterKey,
          'status': 'pending',
          'revision': 1,
          'created_at_ms': now,
          'updated_at_ms': now,
        });
      } else {
        final previous = rows.single;
        await tx.update(
          'penpal_outbox',
          {
            'content': normalized,
            'related_letter_key': relatedLetterKey.isEmpty
                ? previous['related_letter_key']
                : relatedLetterKey,
            'revision': (previous['revision'] as int) + 1,
            'updated_at_ms': now,
          },
          where: "id=? AND card_id=? AND status='pending'",
          whereArgs: [previous['id'], cardId],
        );
      }
    });
  }

  /// Append quick feedback without replacing a pending handwritten note.
  /// A repeated click stays idempotent even after the note has been answered.
  Future<bool> appendOnce(
    String cardId,
    String text, {
    required String relatedLetterKey,
  }) async {
    final message = text.trim();
    if (cardId.isEmpty ||
        message.isEmpty ||
        message.length > 500 ||
        RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]').hasMatch(message)) {
      throw const FormatException('点赞留言内容无效，请稍后重试');
    }
    return database.db.transaction((tx) async {
      final duplicate = await tx.rawQuery(
        "SELECT id FROM penpal_outbox WHERE card_id=? "
        "AND status IN ('pending','answered') AND instr(content,?)>0 LIMIT 1",
        [cardId, message],
      );
      if (duplicate.isNotEmpty) return false;
      final rows = await tx.query(
        'penpal_outbox',
        where: "card_id=? AND status='pending'",
        whereArgs: [cardId],
        limit: 1,
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      if (rows.isEmpty) {
        await tx.insert('penpal_outbox', {
          'card_id': cardId,
          'content': message,
          'related_letter_key': relatedLetterKey,
          'status': 'pending',
          'revision': 1,
          'created_at_ms': now,
          'updated_at_ms': now,
        });
      } else {
        final previous = rows.single;
        final combined = '${previous['content']}\n\n$message';
        if (combined.length > 500) {
          throw const FormatException('待回留言已接近 500 字，请先到“给笔友留言”编辑后再点赞');
        }
        await tx.update(
          'penpal_outbox',
          {
            'content': combined,
            'revision': (previous['revision'] as int) + 1,
            'updated_at_ms': now,
          },
          where: "id=? AND card_id=? AND status='pending'",
          whereArgs: [previous['id'], cardId],
        );
      }
      return true;
    });
  }

  Future<int> deleteWithdrawn(String cardId, int noteId) => database.db.delete(
    'penpal_outbox',
    where: "card_id=? AND id=? AND status='withdrawn'",
    whereArgs: [cardId, noteId],
  );

  Future<void> withdraw(String cardId, int noteId) async {
    await database.db.rawUpdate(
      "UPDATE penpal_outbox SET status='withdrawn', "
      'revision=revision+1, updated_at_ms=? '
      "WHERE card_id=? AND id=? AND status='pending'",
      [DateTime.now().millisecondsSinceEpoch, cardId, noteId],
    );
  }
}
