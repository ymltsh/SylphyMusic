import '../core/penpal_chat_models.dart';
import 'app_db.dart';

class PenpalChatRepository {
  const PenpalChatRepository(this.database);
  final AppDb database;

  Future<List<PenpalChatMessage>> history(
    String persona,
    String letter, {
    int? before,
    int limit = 40,
  }) async {
    final rows = await database.db.query(
      'penpal_chat_messages',
      where:
          "(persona_key=? OR persona_key='') AND letter_key=?"
          '${before == null ? '' : ' AND id<?'}',
      whereArgs: [persona, letter, if (before != null) before],
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.reversed.map(PenpalChatMessage.fromRow).toList();
  }

  Future<void> saveTurn({
    required String persona,
    required String letter,
    required String user,
    required String assistant,
    required bool Function() stillValid,
  }) async {
    await database.db.transaction((tx) async {
      if (!stillValid()) throw StateError('聊天已停止，请重新发送');
      final state = await tx.query(
        'penpal_memory_state',
        where: 'id=1',
        limit: 1,
      );
      if (state.isNotEmpty && state.first['enabled'] == 0) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = await tx.insert('penpal_chat_messages', {
        'persona_key': persona,
        'letter_key': letter,
        'role': 'user',
        'content': user,
        'created_at_ms': now,
      });
      await tx.insert('penpal_chat_messages', {
        'persona_key': persona,
        'letter_key': letter,
        'role': 'assistant',
        'content': assistant,
        'created_at_ms': now,
      });
      // Only the user's own words become personalization evidence.
      await tx.insert('penpal_memory_events', {
        'kind': 'chat_preference',
        'text': user,
        'source_key': 'chat:$id',
        'related_letter_key': letter,
        'topic': '',
        'created_at_ms': now,
        'pinned': 1,
      });
    });
  }

  Future<void> clear(String persona, String letter) async {
    await database.db.transaction((tx) async {
      final rows = await tx.query(
        'penpal_chat_messages',
        columns: ['id'],
        where: "(persona_key=? OR persona_key='') AND letter_key=?",
        whereArgs: [persona, letter],
      );
      for (final row in rows) {
        await tx.delete(
          'penpal_memory_events',
          where: 'source_key=? AND kind=?',
          whereArgs: ['chat:${row['id']}', 'chat_preference'],
        );
      }
      await tx.delete(
        'penpal_chat_messages',
        where: "(persona_key=? OR persona_key='') AND letter_key=?",
        whereArgs: [persona, letter],
      );
      // Replies from before chat was introduced have no persona identifier.
      await tx.delete(
        'penpal_memory_events',
        where: "kind='user_reply' AND related_letter_key=?",
        whereArgs: [letter],
      );
    });
  }
}
