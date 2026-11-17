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
          "persona_key=? AND letter_key=?"
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
        'penpal_card_memory_state',
        where: 'card_id=?',
        whereArgs: [persona],
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
      // New RP Core classifies the saved turn after transaction commit.
      // Do NOT automatically pin every chat utterance as a long-term fact.
      // Durable, cross-session journal evidence; atomic with saved chat.
      final rpState = await tx.query(
        'rp_character_state',
        columns: ['memory_enabled'],
        where: 'card_id=?',
        whereArgs: [persona],
        limit: 1,
      );
      if (rpState.isEmpty || rpState.first['memory_enabled'] != 0) {
        final userText = user.length > 1200 ? user.substring(0, 1200) : user;
        final replyText = assistant.length > 1200
            ? assistant.substring(0, 1200)
            : assistant;
        await tx.insert('rp_journal_queue', {
          'card_id': persona,
          'conversation_key': letter,
          'user_text': userText,
          'assistant_text': replyText,
          'occurred_at_ms': now,
        });
      }
    });
  }

  Future<void> clear(String persona, String letter) async {
    await database.db.transaction((tx) async {
      final rows = await tx.query(
        'penpal_chat_messages',
        columns: ['id'],
        where: "persona_key=? AND letter_key=?",
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
        where: "persona_key=? AND letter_key=?",
        whereArgs: [persona, letter],
      );
      await tx.delete(
        'penpal_memory_events',
        where: "kind='user_reply' AND card_id=? AND related_letter_key=?",
        whereArgs: [persona, letter],
      );
      // The RP Core episode/preferences from this specific chat are private
      // derivatives and must disappear with the chat transcript.
      // A deleted conversation must vanish from diary evidence too.
      await tx.delete(
        'rp_journal_queue',
        where: 'card_id=? AND conversation_key=?',
        whereArgs: [persona, letter],
      );
      await tx.delete(
        'rp_journal_entries',
        where: 'card_id=? AND conversation_key=?',
        whereArgs: [persona, letter],
      );
      final continuityRows = await tx.query(
        'rp_continuity',
        columns: ['revision'],
        where: 'card_id=?',
        whereArgs: [persona],
      );
      if (continuityRows.isNotEmpty) {
        await tx.update(
          'rp_continuity',
          {
            'self_note': '',
            'user_facts': '',
            'relationship': '',
            'open_threads': '',
            'revision': (continuityRows.first['revision'] as int? ?? 0) + 1,
            'invalidated': 1,
            'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'card_id=?',
          whereArgs: [persona],
        );
      }
    });
  }
}
