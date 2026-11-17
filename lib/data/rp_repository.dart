import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/rp_models.dart';
import 'app_db.dart';

/// RP database access, isolated by the immutable character-card ID.
class RpRepository {
  const RpRepository(this.db);
  final AppDb db;

  static const _starterEvents = <(String, String)>[
    ('夹在书中的便签', '在角色的虚构日常中，翻出一张没有署名的书签；可说说它为什么引起好奇。'),
    ('还没寄出的明信片', '角色想起一张尚未写完的明信片；可以聊目的地，也可以放下。'),
    ('散乱的手稿', '角色收拾资料时翻到一页没有写完的草稿，忽然想换个写法。'),
    ('书架上的陌生封面', '角色看到一本自己还没有认真翻过的书，冒出了新的好奇。'),
  ];

  Future<RpCharacterState> ensureState(String cardId) async {
    await db.db.transaction((tx) async {
      final exists = await tx.query(
        'rp_character_state',
        where: 'card_id=?',
        whereArgs: [cardId],
        limit: 1,
      );
      if (exists.isNotEmpty) return;
      await tx.insert('rp_character_state', {
        'card_id': cardId,
        'scene': '自由场景',
        'activity': '整理自己的思绪',
        'goal': '分享一件真正感兴趣的事',
        'energy': 65,
        'memory_enabled': 1,
        'events_enabled': 1,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      });
      for (final (title, content) in _starterEvents) {
        await tx.insert('rp_lore_entries', {
          'card_id': cardId,
          'kind': 'event',
          'title': title,
          'content': content,
          'triggers_json': '[]',
          'priority': 50,
          'chance': 24,
          'cooldown_hours': 168,
          'enabled': 1,
          'last_triggered_ms': 0,
        });
      }
    });
    final rows = await db.db.query(
      'rp_character_state',
      where: 'card_id=?',
      whereArgs: [cardId],
      limit: 1,
    );
    return RpCharacterState.fromRow(rows.first);
  }

  Future<RpSnapshot> snapshot(String cardId) async {
    final state = await ensureState(cardId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await Future.wait([
      db.db.query(
        'rp_lore_entries',
        where: 'card_id=?',
        whereArgs: [cardId],
        orderBy: 'priority DESC,id DESC',
        limit: 100,
      ),
      db.db.query(
        'rp_event_instances',
        where: 'card_id=?',
        whereArgs: [cardId],
        orderBy: 'started_at_ms DESC',
        limit: 30,
      ),
    ]);
    List<String> parseTriggers(Object? raw) {
      try {
        final parsed = jsonDecode(raw as String? ?? '[]');
        return parsed is List
            ? parsed.whereType<String>().take(12).toList()
            : <String>[];
      } catch (_) {
        return [];
      }
    }

    return RpSnapshot(
      state: state,
      lore: rows[0]
          .map(
            (row) =>
                RpLoreEntry.fromRow(row, parseTriggers(row['triggers_json'])),
          )
          .toList(),
      events: rows[1].map(RpEvent.fromRow).toList(),
    );
  }

  Future<void> updateState(
    String cardId, {
    String? scene,
    String? activity,
    String? goal,
    int? energy,
    bool? memoryEnabled,
    bool? eventsEnabled,
  }) async {
    await ensureState(cardId);
    await db.db.update(
      'rp_character_state',
      {
        if (scene != null) 'scene': scene,
        if (activity != null) 'activity': activity,
        if (goal != null) 'goal': goal,
        if (energy != null) 'energy': energy.clamp(0, 100),
        if (memoryEnabled != null) 'memory_enabled': memoryEnabled ? 1 : 0,
        if (eventsEnabled != null) 'events_enabled': eventsEnabled ? 1 : 0,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'card_id=?',
      whereArgs: [cardId],
    );
  }

  /// Clear derived RP memory, not character identity or authored lore.
  Future<void> clearMemories(String cardId) async {
    await db.db.transaction((tx) async {
      for (final table in <String>[
        'rp_journal_queue',
        'rp_journal_entries',
        'rp_continuity',
        'rp_event_instances',
        'rp_event_rolls',
      ]) {
        await tx.delete(table, where: 'card_id=?', whereArgs: [cardId]);
      }
    });
  }

  Future<int> addLore(
    String cardId, {
    required String kind,
    required String title,
    required String content,
    List<String> triggers = const [],
    int priority = 50,
    int chance = 30,
    int cooldownHours = 72,
  }) => db.db.insert('rp_lore_entries', {
    'card_id': cardId,
    'kind': kind,
    'title': title,
    'content': content,
    'triggers_json': jsonEncode(triggers),
    'priority': priority.clamp(0, 100),
    'chance': chance.clamp(0, 100),
    'cooldown_hours': cooldownHours.clamp(1, 2160),
    'enabled': 1,
    'last_triggered_ms': 0,
  });

  Future<void> removeLore(String cardId, int id) async {
    await db.db.delete(
      'rp_lore_entries',
      where: 'card_id=? AND id=?',
      whereArgs: [cardId, id],
    );
  }

  Future<void> enableLore(String cardId, int id, bool enabled) async {
    await db.db.update(
      'rp_lore_entries',
      {'enabled': enabled ? 1 : 0},
      where: 'card_id=? AND id=?',
      whereArgs: [cardId, id],
    );
  }

  /// One daily roll per character. Skipped rolls stay skipped, so opening the
  /// same screen repeatedly never increases the chance of an event.
  Future<bool> claimDailyRoll(String cardId, String day) =>
      db.db.transaction((tx) async {
        final current = await tx.query(
          'rp_event_rolls',
          columns: ['card_id'],
          where: 'card_id=? AND local_day=?',
          whereArgs: [cardId, day],
          limit: 1,
        );
        if (current.isNotEmpty) return false;
        await tx.insert('rp_event_rolls', {
          'card_id': cardId,
          'local_day': day,
          'created_at_ms': DateTime.now().millisecondsSinceEpoch,
        });
        return true;
      });

  Future<void> beginEvent(String cardId, RpLoreEntry card) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.db.transaction((tx) async {
      await tx.update(
        'rp_event_instances',
        {'status': 'resolved', 'ended_at_ms': now},
        where: "card_id=? AND status='active'",
        whereArgs: [cardId],
      );
      await tx.insert('rp_event_instances', {
        'card_id': cardId,
        'lore_id': card.id,
        'title': card.title,
        'description': card.content,
        'status': 'active',
        'started_at_ms': now,
      });
      await tx.update(
        'rp_lore_entries',
        {'last_triggered_ms': now},
        where: 'card_id=? AND id=?',
        whereArgs: [cardId, card.id],
      );
      await tx.update(
        'rp_character_state',
        {'activity': card.title, 'updated_at_ms': now},
        where: 'card_id=?',
        whereArgs: [cardId],
      );
    });
  }

  /// An event is a transient scene seed, not an eternal active fact.
  Future<void> resolveStaleEvents(String cardId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - const Duration(days: 1).inMilliseconds;
    final old = await db.db.query(
      'rp_event_instances',
      where: "card_id=? AND status='active' AND started_at_ms<?",
      whereArgs: [cardId, cutoff],
    );
    for (final row in old) {
      await resolveEvent(cardId, row['id'] as int);
    }
  }

  Future<void> resolveEvent(String cardId, int id) async {
    await db.db.transaction((tx) async {
      final rows = await tx.query(
        'rp_event_instances',
        where: 'card_id=? AND id=? AND status=?',
        whereArgs: [cardId, id, 'active'],
        limit: 1,
      );
      if (rows.isEmpty) return;
      await tx.update(
        'rp_event_instances',
        {
          'status': 'resolved',
          'ended_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'card_id=? AND id=?',
        whereArgs: [cardId, id],
      );
      // Preserve an activity that the user has since edited manually.
      await tx.update(
        'rp_character_state',
        {
          'activity': '整理自己的思绪',
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'card_id=? AND activity=?',
        whereArgs: [cardId, rows.first['title']],
      );
    });
  }

  Future<void> prune(String cardId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.db.transaction((tx) async {
      await tx.delete(
        'rp_event_rolls',
        where: 'card_id=? AND created_at_ms<?',
        whereArgs: [cardId, now - const Duration(days: 60).inMilliseconds],
      );
      await tx.delete(
        'rp_event_instances',
        where: 'card_id=? AND started_at_ms<? AND status=?',
        whereArgs: [
          cardId,
          now - const Duration(days: 90).inMilliseconds,
          'resolved',
        ],
      );
    });
  }
}
