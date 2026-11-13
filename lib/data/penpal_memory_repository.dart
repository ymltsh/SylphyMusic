import 'package:sqflite/sqflite.dart';

import '../core/penpal_models.dart';
import 'app_db.dart';

/// Long-term memories belong to an immutable card ID, never prompt hashes.
class PenpalMemoryRepository {
  const PenpalMemoryRepository(this.appDb);
  final AppDb appDb;

  Future<PenpalMemorySnapshot> snapshot(
    String defaultSoul, {
    required String cardId,
    required String cardName,
  }) async {
    final controls = await appDb.db.query(
      'penpal_card_memory_state',
      where: 'card_id=?',
      whereArgs: [cardId],
      limit: 1,
    );
    final row = controls.isEmpty ? null : controls.first;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await appDb.db.query(
      'penpal_memory_events',
      where: 'card_id=? AND (expires_at_ms IS NULL OR expires_at_ms>?)',
      whereArgs: [cardId, now],
      orderBy: 'created_at_ms DESC,id DESC',
      limit: 500,
    );
    final note = row?['soul_override'] as String? ?? '';
    return PenpalMemorySnapshot(
      enabled: row?['enabled'] != 0,
      recallEnabled: row?['recall_enabled'] != 0,
      soul: note.trim().isEmpty ? defaultSoul : note,
      soulCustomized: note.trim().isNotEmpty,
      personaName: cardName,
      entries: rows.map(PenpalMemoryEntry.fromRow).toList(),
    );
  }

  Future<void> updateState(
    String cardId, {
    bool? enabled,
    bool? recallEnabled,
    String? soulOverride,
  }) async {
    await appDb.db.transaction((tx) async {
      final prior = await tx.query(
        'penpal_card_memory_state',
        where: 'card_id=?',
        whereArgs: [cardId],
        limit: 1,
      );
      final row = prior.isEmpty ? null : prior.first;
      await tx.insert('penpal_card_memory_state', {
        'card_id': cardId,
        'enabled': (enabled ?? (row?['enabled'] != 0)) ? 1 : 0,
        'recall_enabled': (recallEnabled ?? (row?['recall_enabled'] != 0))
            ? 1
            : 0,
        'soul_override': soulOverride ?? row?['soul_override'] ?? '',
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> insert({
    required String cardId,
    required String kind,
    required String text,
    String? sourceKey,
    String? relatedLetterKey,
    String topic = '',
    int? expiresAtMs,
    bool pinned = false,
  }) async {
    await appDb.db.insert('penpal_memory_events', {
      'card_id': cardId,
      'kind': kind,
      'text': text,
      'source_key': sourceKey,
      'related_letter_key': relatedLetterKey,
      'topic': topic,
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
      'expires_at_ms': expiresAtMs,
      'pinned': pinned ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<String?> authoredCardForLetter(String key) async {
    final separator = key.lastIndexOf(':');
    if (separator < 0) return null;
    final generation = int.tryParse(key.substring(separator + 1));
    if (generation == null) return null;
    final rows = await appDb.db.query(
      'recommendation_letters',
      columns: ['card_id'],
      where: 'local_day=? AND generation=?',
      whereArgs: [key.substring(0, separator), generation],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final id = rows.first['card_id'] as String? ?? '';
    return id.isEmpty ? null : id;
  }

  Future<void> deleteEntry(int id) async {
    await appDb.db.delete(
      'penpal_memory_events',
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<void> clear(String cardId) async {
    await appDb.db.transaction((tx) async {
      await tx.delete(
        'penpal_memory_events',
        where: 'card_id=?',
        whereArgs: [cardId],
      );
      await tx.delete(
        'penpal_chat_messages',
        where: 'persona_key=?',
        whereArgs: [cardId],
      );
      // Clear the optional persona note, but preserve memory opt-out choices.
      await tx.update(
        'penpal_card_memory_state',
        {
          'soul_override': '',
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'card_id=?',
        whereArgs: [cardId],
      );
    });
  }

  Future<void> clearLetterDerived(String cardId) async {
    await appDb.db.transaction((tx) async {
      await tx.delete(
        'penpal_memory_events',
        where: 'card_id=? AND related_letter_key IS NOT NULL',
        whereArgs: [cardId],
      );
      // The clear-letter confirmation covers this card's attached chats.
      await tx.delete(
        'penpal_chat_messages',
        where: 'persona_key=?',
        whereArgs: [cardId],
      );
    });
  }

  Future<void> prune(String cardId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await appDb.db.transaction((tx) async {
      await tx.delete(
        'penpal_memory_events',
        where: 'card_id=? AND pinned=0 AND expires_at_ms IS NOT NULL AND expires_at_ms<=?',
        whereArgs: [cardId, now],
      );
      await tx.rawDelete(
        '''
        DELETE FROM penpal_memory_events
        WHERE card_id=? AND kind='self' AND pinned=0 AND id NOT IN (
          SELECT id FROM penpal_memory_events WHERE card_id=? AND kind='self'
          ORDER BY created_at_ms DESC,id DESC LIMIT 12
        )''',
        [cardId, cardId],
      );
      await tx.rawDelete(
        '''
        DELETE FROM penpal_memory_events
        WHERE card_id=? AND kind IN ('letter_written','letter_opened') AND pinned=0
          AND id NOT IN (
            SELECT id FROM penpal_memory_events
            WHERE card_id=? AND kind IN ('letter_written','letter_opened')
            ORDER BY created_at_ms DESC,id DESC LIMIT 120
          )''',
        [cardId, cardId],
      );
    });
  }
}
