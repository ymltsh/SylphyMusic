import 'package:sqflite/sqflite.dart';

import '../core/rp_journal_models.dart';
import 'app_db.dart';

/// Stores the journal's source evidence and its derived narrative separately.
/// The pending queue is written in the same SQLite transaction as the chat.
class RpJournalRepository {
  const RpJournalRepository(this.db);
  final AppDb db;

  Future<RpContinuity> continuity(String cardId) async {
    final rows = await db.db.query(
      'rp_continuity',
      where: 'card_id=?',
      whereArgs: [cardId],
      limit: 1,
    );
    return rows.isEmpty
        ? const RpContinuity()
        : RpContinuity.fromRow(rows.first);
  }

  Future<List<RpJournalEntry>> recentDiaries(
    String cardId, {
    int limit = 3,
  }) async {
    final rows = await db.db.query(
      'rp_journal_entries',
      where: 'card_id=?',
      whereArgs: [cardId],
      orderBy: 'created_at_ms DESC,id DESC',
      limit: limit,
    );
    return rows.map(RpJournalEntry.fromRow).toList();
  }

  Future<List<RpJournalTurn>> pending(String cardId, {int limit = 12}) async {
    final rows = await db.db.query(
      'rp_journal_queue',
      where: 'card_id=? AND digested_at_ms IS NULL',
      whereArgs: [cardId],
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map(RpJournalTurn.fromRow).toList();
  }

  Future<List<RpJournalTurn>> recentPending(
    String cardId, {
    int limit = 4,
  }) async {
    final rows = await db.db.query(
      'rp_journal_queue',
      where: 'card_id=? AND digested_at_ms IS NULL',
      whereArgs: [cardId],
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.reversed.map(RpJournalTurn.fromRow).toList();
  }

  Future<RpJournalSnapshot> snapshot(String cardId) async {
    final results = await Future.wait([
      continuity(cardId),
      recentDiaries(cardId, limit: 80),
      pending(cardId, limit: 1000),
    ]);
    return RpJournalSnapshot(
      continuity: results[0] as RpContinuity,
      entries: results[1] as List<RpJournalEntry>,
      pending: (results[2] as List<RpJournalTurn>).length,
    );
  }

  Future<void> enqueueLetter(
    String cardId,
    String letterKey,
    String title,
    String body,
  ) async {
    if (body.trim().isEmpty) return;
    final rows = await db.db.query(
      'rp_character_state',
      columns: ['memory_enabled'],
      where: 'card_id=?',
      whereArgs: [cardId],
      limit: 1,
    );
    if (rows.isNotEmpty && rows.first['memory_enabled'] == 0) return;
    final text = '${title.trim()}\n${body.trim()}';
    await db.db.insert('rp_journal_queue', {
      'card_id': cardId,
      'conversation_key': 'letter:$letterKey',
      'user_text': '',
      'assistant_text': text.length <= 1200 ? text : text.substring(0, 1200),
      'occurred_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> commit({
    required String cardId,
    required List<RpJournalTurn> turns,
    required String diary,
    required RpContinuity next,
    required int expectedRevision,
  }) async {
    if (turns.isEmpty || diary.trim().isEmpty) return;
    final ids = turns.map((t) => t.id).toList();
    await db.db.transaction((tx) async {
      final currentRows = await tx.query(
        'rp_continuity',
        where: 'card_id=?',
        whereArgs: [cardId],
        limit: 1,
      );
      final revision = currentRows.isEmpty
          ? 0
          : (currentRows.first['revision'] as int? ?? 0);
      if (revision != expectedRevision) {
        throw StateError('连续记忆在整理期间发生变更，保留待整理记录');
      }
      final placeholders = List.filled(ids.length, '?').join(',');
      final evidence = await tx.rawQuery(
        'SELECT id FROM rp_journal_queue WHERE card_id=? '
        'AND digested_at_ms IS NULL AND id IN ($placeholders)',
        [cardId, ...ids],
      );
      if (evidence.length != ids.length) {
        throw StateError('待整理记录已变更，未写入日记');
      }
      final first = turns.first;
      final local = DateTime.fromMillisecondsSinceEpoch(first.occurredAtMs);
      final day =
          '${local.year.toString().padLeft(4, '0')}-'
          '${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}';
      final now = DateTime.now().millisecondsSinceEpoch;
      await tx.insert('rp_journal_entries', {
        'card_id': cardId,
        'local_day': day,
        'conversation_key': first.conversationKey,
        'body': diary.trim(),
        'created_at_ms': now,
      });
      await tx.insert('rp_continuity', {
        'card_id': cardId,
        'self_note': next.self,
        'user_facts': next.user,
        'relationship': next.relationship,
        'open_threads': next.openThreads,
        'avoid_repetition': next.avoidRepetition,
        'revision': expectedRevision + 1,
        'invalidated': 0,
        'updated_at_ms': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.rawUpdate(
        'UPDATE rp_journal_queue SET digested_at_ms=? '
        'WHERE card_id=? AND id IN ($placeholders)',
        [now, cardId, ...ids],
      );
      // Retain processed evidence for deletion / rebuilding, but not forever.
      await tx.delete(
        'rp_journal_queue',
        where: 'card_id=? AND digested_at_ms IS NOT NULL AND occurred_at_ms<?',
        whereArgs: [cardId, now - const Duration(days: 180).inMilliseconds],
      );
    });
  }

  /// Source deletion must not leave a derived memory that still quotes it.
  /// The next digest rebuilds continuity from the surviving diary evidence.
  Future<void> deleteConversation(String cardId, String conversationKey) async {
    await db.db.transaction((tx) async {
      await tx.delete(
        'rp_journal_queue',
        where: 'card_id=? AND conversation_key=?',
        whereArgs: [cardId, conversationKey],
      );
      await tx.delete(
        'rp_journal_entries',
        where: 'card_id=? AND conversation_key=?',
        whereArgs: [cardId, conversationKey],
      );
      await tx.update(
        'rp_continuity',
        {
          'self_note': '',
          'user_facts': '',
          'relationship': '',
          'open_threads': '',
          'avoid_repetition': '',
          'invalidated': 1,
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
          'revision': (await _revision(tx, cardId)) + 1,
        },
        where: 'card_id=?',
        whereArgs: [cardId],
      );
    });
  }

  Future<int> _revision(DatabaseExecutor tx, String cardId) async {
    final rows = await tx.query(
      'rp_continuity',
      columns: ['revision'],
      where: 'card_id=?',
      whereArgs: [cardId],
    );
    return rows.isEmpty ? 0 : (rows.first['revision'] as int? ?? 0);
  }

  Future<void> clear(String cardId) async {
    await db.db.transaction((tx) async {
      for (final table in [
        'rp_journal_queue',
        'rp_journal_entries',
        'rp_continuity',
      ]) {
        await tx.delete(table, where: 'card_id=?', whereArgs: [cardId]);
      }
    });
  }

  Future<void> deleteEntry(String cardId, int id) async {
    await db.db.transaction((tx) async {
      await tx.delete(
        'rp_journal_entries',
        where: 'card_id=? AND id=?',
        whereArgs: [cardId, id],
      );
      await tx.update(
        'rp_continuity',
        {
          'self_note': '',
          'user_facts': '',
          'relationship': '',
          'open_threads': '',
          'avoid_repetition': '',
          'invalidated': 1,
          'revision': (await _revision(tx, cardId)) + 1,
        },
        where: 'card_id=?',
        whereArgs: [cardId],
      );
    });
  }

  Future<void> updateContinuity(String cardId, RpContinuity value) async {
    await db.db.transaction((tx) async {
      final rows = await tx.query(
        'rp_continuity',
        columns: ['revision'],
        where: 'card_id=?',
        whereArgs: [cardId],
      );
      final actual = rows.isEmpty ? 0 : (rows.first['revision'] as int? ?? 0);
      if (actual != value.revision) {
        throw StateError('角色连续记忆已更新，请重新载入后编辑');
      }
      await tx.insert('rp_continuity', {
        'card_id': cardId,
        'self_note': value.self,
        'user_facts': value.user,
        'relationship': value.relationship,
        'open_threads': value.openThreads,
        'avoid_repetition': value.avoidRepetition,
        'revision': value.revision + 1,
        'invalidated': 0,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }
}
