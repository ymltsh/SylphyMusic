import 'package:sqflite/sqflite.dart';

import '../core/rp_journal_models.dart';
import 'app_db.dart';

/// Persistent long-term memories in three density tiers.
/// The evidence queue is retained for source deletion/rebuilding; it is not
/// injected wholesale into prompts and is never counted as a memory tier.
class RpJournalRepository {
  const RpJournalRepository(this.db);
  final AppDb db;

  Future<List<RpJournalEntry>> entries(
    String cardId, {
    String? level,
    int limit = 120,
  }) async {
    final rows = await db.db.query(
      'rp_journal_entries',
      where: level == null ? 'card_id=?' : 'card_id=? AND level=?',
      whereArgs: level == null ? [cardId] : [cardId, level],
      orderBy: 'start_day DESC,id DESC',
      limit: limit.clamp(1, 500),
    );
    return rows.map(RpJournalEntry.fromRow).toList();
  }

  Future<RpJournalEntry?> unit(String cardId, String level, String key) async {
    final rows = await db.db.query(
      'rp_journal_entries',
      where: 'card_id=? AND level=? AND period_key=?',
      whereArgs: [cardId, level, key],
      limit: 1,
    );
    return rows.isEmpty ? null : RpJournalEntry.fromRow(rows.single);
  }

  Future<List<RpJournalTurn>> pending(String cardId, {int limit = 32}) async {
    final rows = await db.db.query(
      'rp_journal_queue',
      where: 'card_id=? AND digested_at_ms IS NULL',
      whereArgs: [cardId],
      orderBy: 'occurred_at_ms ASC,id ASC',
      limit: limit.clamp(1, 300),
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
      orderBy: 'occurred_at_ms DESC,id DESC',
      limit: limit.clamp(1, 24),
    );
    return rows.reversed.map(RpJournalTurn.fromRow).toList();
  }

  Future<RpJournalSnapshot> snapshot(String cardId) async {
    final results = await Future.wait([
      entries(cardId, limit: 180),
      recentPending(cardId, limit: 16),
    ]);
    final count = await db.db.rawQuery(
      'SELECT COUNT(*) AS amount FROM rp_journal_queue '
      'WHERE card_id=? AND digested_at_ms IS NULL',
      [cardId],
    );
    return RpJournalSnapshot(
      entries: results[0] as List<RpJournalEntry>,
      drafts: results[1] as List<RpJournalTurn>,
      pending: (count.first['amount'] as int?) ?? 0,
    );
  }

  /// A real user message/reply is evidence; generated letters alone are not.
  Future<void> enqueueUserReply(
    String cardId,
    String conversationKey,
    String message,
  ) async {
    final value = message.trim();
    if (value.isEmpty) return;
    if (!await memoryEnabled(cardId)) return;
    await db.db.insert('rp_journal_queue', {
      'card_id': cardId,
      'conversation_key': conversationKey,
      'user_text': value.length > 1200 ? value.substring(0, 1200) : value,
      'assistant_text': '',
      'occurred_at_ms': DateTime.now().millisecondsSinceEpoch,
      'local_day': _localDay(DateTime.now()),
    });
  }

  static String _localDay(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<bool> memoryEnabled(String cardId) async {
    final rows = await db.db.query(
      'rp_character_state',
      columns: ['memory_enabled'],
      where: 'card_id=?',
      whereArgs: [cardId],
      limit: 1,
    );
    return rows.isEmpty || rows.first['memory_enabled'] != 0;
  }

  /// Atomic diary upsert: exactly one daily unit per local date. The revision
  /// and evidence-ID checks prevent a late LLM response reviving deleted data.
  Future<void> commitDay({
    required String cardId,
    required String day,
    required RpJournalEntry? previous,
    required List<RpJournalTurn> turns,
    required String content,
  }) async {
    if (turns.isEmpty || content.trim().isEmpty) return;
    final ids = turns.map((t) => t.id).toList();
    await db.db.transaction((tx) async {
      final current = await tx.query(
        'rp_journal_entries',
        where: "card_id=? AND level='day' AND period_key=?",
        whereArgs: [cardId, day],
        limit: 1,
      );
      if ((current.isEmpty ? null : current.single['revision']) !=
          (previous == null ? null : previous.revision)) {
        throw StateError('日记在整理期间已变更');
      }
      final placeholders = List.filled(ids.length, '?').join(',');
      final checked = await tx.rawQuery(
        'SELECT id FROM rp_journal_queue '
        'WHERE card_id=? AND digested_at_ms IS NULL AND id IN ($placeholders)',
        [cardId, ...ids],
      );
      if (checked.length != ids.length) {
        throw StateError('原始交流发生变化，取消本次整理');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final value = <String, Object?>{
        'card_id': cardId,
        'level': 'day',
        'period_key': day,
        'start_day': day,
        'end_day': day,
        'body': content.trim(),
        'source_count': (previous?.sourceCount ?? 0) + turns.length,
        'revision': (previous?.revision ?? -1) + 1,
        'updated_at_ms': now,
      };
      if (current.isEmpty) {
        await tx.insert('rp_journal_entries', value);
      } else {
        await tx.update(
          'rp_journal_entries',
          value,
          where: 'id=?',
          whereArgs: [current.single['id']],
        );
      }
      await tx.rawUpdate(
        'UPDATE rp_journal_queue SET digested_at_ms=? '
        'WHERE card_id=? AND id IN ($placeholders)',
        [now, cardId, ...ids],
      );
    });
  }

  /// Condense older units into a denser one. Source units disappear only after
  /// a successful, revision-checked target write (no memory duplication).
  Future<void> commitRollup({
    required String cardId,
    required String level,
    required String periodKey,
    required String startDay,
    required String endDay,
    required List<RpJournalEntry> sources,
    required RpJournalEntry? previous,
    required String content,
  }) async {
    if (sources.isEmpty || content.trim().isEmpty) return;
    if (level != 'week' && level != 'month') {
      throw ArgumentError.value(level, 'level');
    }
    await db.db.transaction((tx) async {
      final target = await tx.query(
        'rp_journal_entries',
        where: 'card_id=? AND level=? AND period_key=?',
        whereArgs: [cardId, level, periodKey],
        limit: 1,
      );
      if ((target.isEmpty ? null : target.single['revision']) !=
          (previous == null ? null : previous.revision)) {
        throw StateError('归纳目标在整理期间发生变化');
      }
      for (final source in sources) {
        final found = await tx.query(
          'rp_journal_entries',
          columns: ['revision'],
          where: 'card_id=? AND id=?',
          whereArgs: [cardId, source.id],
          limit: 1,
        );
        if (found.isEmpty || found.single['revision'] != source.revision) {
          throw StateError('归纳来源在整理期间发生变化');
        }
      }
      final value = <String, Object?>{
        'card_id': cardId,
        'level': level,
        'period_key': periodKey,
        'start_day': startDay,
        'end_day': endDay,
        'body': content.trim(),
        'source_count':
            (previous?.sourceCount ?? 0) +
            sources.fold<int>(0, (count, e) => count + e.sourceCount),
        'revision': (previous?.revision ?? -1) + 1,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      };
      if (target.isEmpty) {
        await tx.insert('rp_journal_entries', value);
      } else {
        await tx.update(
          'rp_journal_entries',
          value,
          where: 'id=?',
          whereArgs: [target.single['id']],
        );
      }
      for (final source in sources) {
        await tx.delete(
          'rp_journal_entries',
          where: 'card_id=? AND id=?',
          whereArgs: [cardId, source.id],
        );
      }
    });
  }

  /// A source conversation was deleted. Fail closed: discard *all* derived
  /// units, then rebuild from surviving source evidence next recommendation.
  /// This is preferable to leaving a detail from the deleted dialogue in a
  /// previously condensed monthly memory. It may need extra LLM calls.
  static Future<void> discardAndRequeue(Transaction tx, String cardId) async {
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

  Future<void> deleteConversation(String cardId, String key) async {
    await db.db.transaction((tx) async {
      await tx.delete(
        'rp_journal_queue',
        where: 'card_id=? AND conversation_key=?',
        whereArgs: [cardId, key],
      );
      await discardAndRequeue(tx, cardId);
    });
  }

  Future<void> clear(String cardId) async {
    await db.db.transaction((tx) async {
      for (final table in ['rp_journal_queue', 'rp_journal_entries']) {
        await tx.delete(table, where: 'card_id=?', whereArgs: [cardId]);
      }
    });
  }

  Future<void> deleteEntry(String cardId, int id) async {
    await db.db.delete(
      'rp_journal_entries',
      where: 'card_id=? AND id=?',
      whereArgs: [cardId, id],
    );
  }
}
