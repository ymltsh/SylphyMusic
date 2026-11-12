import 'package:sqflite/sqflite.dart';

import '../core/penpal_models.dart';
import 'app_db.dart';

/// Keeps private memory independent from snapshot pruning and diagnostics.
class PenpalMemoryRepository {
  const PenpalMemoryRepository(this.appDb);

  final AppDb appDb;

  Future<PenpalMemorySnapshot> snapshot(String defaultSoul) async {
    final state = await appDb.db.query(
      'penpal_memory_state',
      where: 'id=1',
      limit: 1,
    );
    final row = state.isEmpty ? null : state.first;
    final memories = await appDb.db.query(
      'penpal_memory_events',
      where: 'expires_at_ms IS NULL OR expires_at_ms>?',
      whereArgs: [DateTime.now().millisecondsSinceEpoch],
      orderBy: 'created_at_ms DESC, id DESC',
      limit: 500,
    );
    final override = row?['soul_override'] as String? ?? '';
    return PenpalMemorySnapshot(
      enabled: row?['enabled'] != 0,
      recallEnabled: row?['recall_enabled'] != 0,
      soul: override.trim().isEmpty ? defaultSoul : override,
      entries: memories.map(PenpalMemoryEntry.fromRow).toList(),
    );
  }

  Future<void> updateState({
    bool? enabled,
    bool? recallEnabled,
    String? soulOverride,
  }) async {
    await appDb.db.transaction((tx) async {
      final existing = await tx.query(
        'penpal_memory_state',
        where: 'id=1',
        limit: 1,
      );
      final before = existing.isEmpty ? null : existing.first;
      await tx.insert('penpal_memory_state', {
        'id': 1,
        'enabled': (enabled ?? before?['enabled'] != 0) ? 1 : 0,
        'recall_enabled': (recallEnabled ?? before?['recall_enabled'] != 0)
            ? 1
            : 0,
        'soul_override': soulOverride ?? before?['soul_override'] ?? '',
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> insert({
    required String kind,
    required String text,
    String? sourceKey,
    String? relatedLetterKey,
    String topic = '',
    int? expiresAtMs,
    bool pinned = false,
  }) async {
    await appDb.db.insert('penpal_memory_events', {
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

  Future<void> deleteEntry(int id) async {
    await appDb.db.delete(
      'penpal_memory_events',
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<void> clear() async {
    await appDb.db.transaction((tx) async {
      await tx.delete('penpal_memory_events');
      await tx.delete('penpal_chat_messages');
      // Clear custom persona as well, but leave explicit on/off preferences.
      await tx.update('penpal_memory_state', {
        'soul_override': '',
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      }, where: 'id=1');
    });
  }

  Future<void> clearLetterDerived() async {
    // User replies saved from letters are also removed: no orphaned memories.
    await appDb.db.transaction((tx) async {
      await tx.delete(
        'penpal_memory_events',
        where: 'related_letter_key IS NOT NULL',
      );
      await tx.delete('penpal_chat_messages');
    });
  }

  Future<void> prune() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await appDb.db.transaction((tx) async {
      await tx.delete(
        'penpal_memory_events',
        where: 'pinned=0 AND expires_at_ms IS NOT NULL AND expires_at_ms<=?',
        whereArgs: [now],
      );
      // Reflections are slow-growing; explicit user replies are never
      // silently dropped by these bounded automatic maintenance rules.
      await tx.rawDelete('''
        DELETE FROM penpal_memory_events
        WHERE kind='self' AND pinned=0 AND id NOT IN (
          SELECT id FROM penpal_memory_events WHERE kind='self'
          ORDER BY created_at_ms DESC, id DESC LIMIT 12
        )
      ''');
      await tx.rawDelete('''
        DELETE FROM penpal_memory_events
        WHERE kind IN ('letter_written','letter_opened') AND pinned=0
          AND id NOT IN (
            SELECT id FROM penpal_memory_events
            WHERE kind IN ('letter_written','letter_opened')
            ORDER BY created_at_ms DESC, id DESC LIMIT 120
          )
      ''');
    });
  }
}
