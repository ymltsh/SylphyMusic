import 'penpal_memory.dart';
import 'rp_journal_service.dart';
import 'rp_runtime.dart';

/// The sole RP context gateway used by chat, daily selection/letter writing,
/// and album selection/reasons. No LLM call is performed here.
///
/// A fresh context is built per LLM operation: role changes and memory opt-out
/// never reuse data captured for a different character. The journal returns
/// bounded continuity, recent diary and pending evidence, not all transcripts.
class RpPromptContext {
  const RpPromptContext._();

  static Future<Map<String, Object?>> build({
    required String cardId,
    required PenpalMemory memory,
    required RpRuntime runtime,
    required RpJournalService journal,
    String currentMessage = '',
    bool checkEvents = true,
  }) async {
    if (cardId != memory.personaKey) {
      throw StateError('角色已切换，请重新获取 RP 上下文');
    }
    final policy = await memory.snapshot();
    if (cardId != memory.personaKey) {
      throw StateError('角色已切换，请重新获取 RP 上下文');
    }
    if (!policy.enabled || !policy.recallEnabled) {
      // Do not send private memories, diary, pending dialogue or world events
      // when the user has disabled the legacy recall switch.
      return const <String, Object?>{'rp_recall_allowed': false};
    }
    final role = await runtime.snapshot(cardId);
    final roleContext = await runtime.context(
      cardId,
      currentMessage: currentMessage,
      checkEvents: checkEvents,
    );
    final diaryContext = role.state.memoryEnabled
        ? await journal.context(cardId)
        : const <String, Object?>{};
    if (cardId != memory.personaKey) {
      throw StateError('角色已切换，请重新获取 RP 上下文');
    }
    return <String, Object?>{
      'rp_recall_allowed': role.state.memoryEnabled,
      ...roleContext,
      if (role.state.memoryEnabled) ...diaryContext,
    };
  }
}
