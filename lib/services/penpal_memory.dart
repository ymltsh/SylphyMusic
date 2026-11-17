import '../core/penpal_models.dart';
import '../core/recommendation_models.dart';
import '../data/penpal_memory_repository.dart';
import 'api_settings.dart';
import 'rp_journal_service.dart';
import 'rp_runtime.dart';

/// A compact, card-scoped penpal memory. Persona follows the active card.
/// Truth checks stay in application logic, not in autobiographical notes.
class PenpalMemory {
  PenpalMemory(this.repository, this.settings, {this.rpRuntime, this.journal});
  final PenpalMemoryRepository repository;
  final ApiSettings settings;
  final RpRuntime? rpRuntime;
  final RpJournalService? journal;
  bool _closed = false;
  int revision = 0;

  String get personaKey => settings.activeCardId;
  String get personaName => settings.cards.activeName;
  String get defaultSoul => '让角色卡决定个性和表达；这里仅存角色自己的补充想法。';

  Future<PenpalMemorySnapshot> snapshot() => repository.snapshot(
    defaultSoul,
    cardId: personaKey,
    cardName: personaName,
  );

  Future<void> saveUserReply(RecommendationLetter letter, String reply) =>
      saveReply(day: letter.day, generation: letter.generation, reply: reply);

  Future<void> saveReply({
    required String day,
    required int generation,
    required String reply,
  }) async {
    if (_closed || !(await snapshot()).enabled) throw StateError('请先开启笔友记忆');
    final value = _clean(reply, 200);
    if (value.isEmpty) throw const FormatException('不能保存空回复');
    final author = await repository.authoredCardForLetter('$day:$generation');
    if (author == null || author != personaKey) throw StateError('这封信不属于当前角色');
    // Explicit user replies now belong to the RP Core, not legacy memory.
    if (rpRuntime != null) {
      // An explicit letter response is part of the user's genuine history,
      // even when no separate chat window was opened.
      try {
        await journal?.repository.enqueueUserReply(
          author,
          '$day:$generation',
          value,
        );
      } catch (_) {
        // Do not fail an already saved response because diary is unavailable.
      }
    }
  }

  Future<void> setEnabled(bool value) {
    revision++;
    return repository.updateState(personaKey, enabled: value);
  }

  Future<void> setRecallEnabled(bool value) {
    revision++;
    return repository.updateState(personaKey, recallEnabled: value);
  }

  Future<void> setSoul(String value) async {
    if (value.trim().length > 1000)
      throw const FormatException('补充设定不能超过 1000 字');
    revision++;
    await repository.updateState(personaKey, soulOverride: _clean(value, 1000));
  }

  Future<void> resetSoul() {
    revision++;
    return repository.updateState(personaKey, soulOverride: '');
  }

  Future<void> deleteEntry(int id) {
    revision++;
    return repository.deleteEntry(id);
  }

  Future<void> clear() {
    revision++;
    return repository.clear(personaKey);
  }

  Future<void> clearLetterDerived() {
    revision++;
    return repository.clearLetterDerived(personaKey);
  }

  String _clean(String input, int limit) {
    final normalized = input
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return normalized.length > limit
        ? normalized.substring(0, limit).trimRight()
        : normalized;
  }

  Future<void> shutdown() async {
    _closed = true;
  }
}
