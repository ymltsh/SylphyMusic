import '../core/penpal_models.dart';
import '../core/recommendation_models.dart';
import '../data/penpal_memory_repository.dart';
import 'api_settings.dart';

/// A compact, card-scoped penpal memory. Persona follows the active card.
/// Truth checks stay in application logic, not in autobiographical notes.
class PenpalMemory {
  PenpalMemory(this.repository, this.settings);
  final PenpalMemoryRepository repository;
  final ApiSettings settings;
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

  Future<Map<String, Object?>> writeContext() async {
    if (_closed) return const {};
    final state = await snapshot();
    if (!state.enabled) return const {};
    final extra = <String, Object?>{
      if (state.soulCustomized) 'persona_note': state.soul,
    };
    if (!state.recallEnabled) return {...extra, 'recall_disabled': true};
    final self = state.entries
        .where((e) => e.kind == 'self' && _safeReflection(e.text).isNotEmpty)
        .take(5);
    final replies = state.entries.where((e) => e.kind == 'user_reply').take(3);
    final opened = state.entries
        .where((e) => e.kind == 'letter_opened')
        .take(2);
    final letters = state.entries
        .where((e) => e.kind == 'letter_written')
        .take(3);
    return {
      ...extra,
      'my_recent_thoughts': [for (final e in self) e.text],
      'user_replies': [for (final e in replies) e.text],
      'user_chat_notes': _preferences(state),
      'opened_letters': [for (final e in opened) e.displayText],
      'my_recent_letters': [for (final e in letters) e.displayText],
      'recent_topics': [
        for (final e in letters)
          if (e.topic.isNotEmpty) e.topic,
      ],
    };
  }

  Future<void> recordGeneratedLetter({
    required String day,
    required int generation,
    required String title,
    String reflection = '',
    String topic = '',
    bool mainLetter = false,
    String? expectedPersonaKey,
  }) async {
    final id = expectedPersonaKey ?? personaKey;
    if (_closed || id != personaKey || !(await snapshot()).enabled) return;
    final key = '$day:$generation';
    final shortTitle = _clean(title, 48);
    final shortTopic = _clean(topic, 28);
    await repository.insert(
      cardId: id,
      kind: 'letter_written',
      text: '我写过《$shortTitle》。',
      sourceKey: 'letter:$id:$key',
      relatedLetterKey: key,
      topic: shortTopic,
      expiresAtMs: DateTime.now()
          .add(const Duration(days: 45))
          .millisecondsSinceEpoch,
    );
    final reflectionText = _safeReflection(reflection);
    if (mainLetter && reflectionText.isNotEmpty) {
      await repository.insert(
        cardId: id,
        kind: 'self',
        text: reflectionText,
        sourceKey: 'self:$id:$day',
        relatedLetterKey: key,
        topic: shortTopic,
      );
    }
    await repository.prune(id);
  }

  Future<void> recordOpenedDailyMix(DailyMix mix) =>
      _recordOpened(day: mix.day, generation: mix.generation, title: mix.title);
  Future<void> recordOpenedLetter(RecommendationLetter letter) => _recordOpened(
    day: letter.day,
    generation: letter.generation,
    title: letter.title,
  );

  Future<void> _recordOpened({
    required String day,
    required int generation,
    required String title,
  }) async {
    if (_closed || !(await snapshot()).enabled) return;
    final key = '$day:$generation';
    final author = await repository.authoredCardForLetter(key);
    if (author == null || author != personaKey) return;
    await repository.insert(
      cardId: author,
      kind: 'letter_opened',
      text: '你翻开过《${_clean(title, 48)}》。',
      sourceKey: 'opened:$author:$key',
      relatedLetterKey: key,
      expiresAtMs: DateTime.now()
          .add(const Duration(days: 30))
          .millisecondsSinceEpoch,
    );
  }

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
    await repository.insert(
      cardId: author,
      kind: 'user_reply',
      text: value,
      relatedLetterKey: '$day:$generation',
      pinned: true,
    );
  }

  List<String> _preferences(PenpalMemorySnapshot state) => state.entries
      .where((e) => e.kind == 'chat_preference')
      .take(8)
      .map((e) => _clean(e.text, 500))
      .toList();

  Future<List<String>> explicitPreferences() async {
    if (_closed) return [];
    final state = await snapshot();
    if (!state.enabled || !state.recallEnabled) return [];
    return [
      for (final e
          in state.entries.where((e) => e.kind == 'user_reply').take(3))
        _clean(e.text, 200),
      ..._preferences(state),
    ];
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

  String _safeReflection(String input) {
    final value = _clean(input, 120);
    if (value.length < 14 || !value.startsWith('我')) return '';
    if (RegExp(
      r'用户|你曾|你一直|你一定|提醒自己|'
      r'必须|不得|不能|不应该|不应当|只允许|仅能|禁止|'
      r'不推断|不编造|保持边界|遵守规则|真实依据|事实校验',
    ).hasMatch(value)) {
      return '';
    }
    return value;
  }

  Future<void> shutdown() async {
    _closed = true;
  }
}
