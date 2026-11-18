import 'package:sqflite/sqflite.dart';

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
      late final int noteId;
      if (rows.isEmpty) {
        noteId = await tx.insert('penpal_outbox', {
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
        noteId = previous['id'] as int;
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
      await _replacePendingEvidence(tx, cardId, noteId, normalized, now);
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
      late final int noteId;
      if (rows.isEmpty) {
        noteId = await tx.insert('penpal_outbox', {
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
        noteId = previous['id'] as int;
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
      final current = await tx.query(
        'penpal_outbox',
        columns: ['content'],
        where: 'id=?',
        whereArgs: [noteId],
        limit: 1,
      );
      await _replacePendingEvidence(
        tx,
        cardId,
        noteId,
        current.single['content'] as String,
        now,
      );
      return true;
    });
  }

  Future<int> deleteWithdrawn(String cardId, int noteId) => database.db.delete(
    'penpal_outbox',
    where: "card_id=? AND id=? AND status='withdrawn'",
    whereArgs: [cardId, noteId],
  );

  Future<void> withdraw(String cardId, int noteId) async {
    await database.db.transaction((tx) async {
      final updated = await tx.rawUpdate(
        "UPDATE penpal_outbox SET status='withdrawn', "
        'revision=revision+1, updated_at_ms=? '
        "WHERE card_id=? AND id=? AND status='pending'",
        [DateTime.now().millisecondsSinceEpoch, cardId, noteId],
      );
      if (updated > 0) await _removeEvidence(tx, cardId, noteId);
    });
  }

  Future<void> _replacePendingEvidence(
    Transaction tx,
    String cardId,
    int noteId,
    String content,
    int now,
  ) async {
    final key = 'mailbox:$noteId';
    final prior = await tx.query(
      'rp_journal_queue',
      columns: ['digested_at_ms'],
      where: 'card_id=? AND conversation_key=?',
      whereArgs: [cardId, key],
    );
    await tx.delete(
      'rp_journal_queue',
      where: 'card_id=? AND conversation_key=?',
      whereArgs: [cardId, key],
    );
    if (prior.any((r) => r['digested_at_ms'] != null)) {
      await _invalidateSummaries(tx, cardId);
    }
    final state = await tx.query(
      'rp_character_state',
      columns: ['memory_enabled'],
      where: 'card_id=?',
      whereArgs: [cardId],
      limit: 1,
    );
    if (state.isNotEmpty && state.single['memory_enabled'] == 0) return;
    await tx.insert('rp_journal_queue', {
      'card_id': cardId,
      'conversation_key': key,
      'user_text': content,
      'assistant_text': '',
      'occurred_at_ms': now,
      'local_day': _mailboxLocalDay(now),
    });
  }

  static String _mailboxLocalDay(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _removeEvidence(
    Transaction tx,
    String cardId,
    int noteId,
  ) async {
    final key = 'mailbox:$noteId';
    final prior = await tx.query(
      'rp_journal_queue',
      columns: ['digested_at_ms'],
      where: 'card_id=? AND conversation_key=?',
      whereArgs: [cardId, key],
    );
    await tx.delete(
      'rp_journal_queue',
      where: 'card_id=? AND conversation_key=?',
      whereArgs: [cardId, key],
    );
    if (prior.any((r) => r['digested_at_ms'] != null)) {
      await _invalidateSummaries(tx, cardId);
    }
  }

  Future<void> _invalidateSummaries(Transaction tx, String cardId) async {
    await tx.delete(
      'rp_journal_entries',
      where: 'card_id=?',
      whereArgs: [cardId],
    );
    await tx.update(
      'rp_journal_queue',
      {'digested_at_ms': null},
      where: 'card_id=?',
      whereArgs: [cardId],
    );
  }
}
