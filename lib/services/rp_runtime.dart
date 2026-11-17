import 'dart:math';

import '../core/rp_models.dart';
import '../data/rp_repository.dart';

/// Foreground-only RP coordinator. No timers, background agent or network calls.
/// The caller may use this even when the music library is empty.
class RpRuntime {
  const RpRuntime(this.repository);
  final RpRepository repository;

  Future<RpSnapshot> snapshot(String cardId) => repository.snapshot(cardId);

  static String _clean(String input, int limit) {
    final text = input
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text.length <= limit ? text : text.substring(0, limit);
  }

  static String _key(String topic) => _clean(
    topic.toLowerCase().replaceAll(RegExp(r'[\s，。！？：:；;“”"《》]+'), ''),
    36,
  );

  static int _seed(String value) {
    var hash = 2166136261;
    for (final code in value.codeUnits) {
      hash = (hash ^ code) * 16777619 & 0x7fffffff;
    }
    return hash;
  }

  static String _day(DateTime now) =>
      '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';

  /// Builds a bounded, separated context. Old or cooling topics are used as a
  /// repetition veto, not as suggestions for the model to mention again.
  Future<Map<String, Object?>> context(
    String cardId, {
    String currentMessage = '',
    bool checkEvents = true,
  }) async {
    await repository.resolveStaleEvents(cardId);
    var data = await repository.snapshot(cardId);
    if (checkEvents && data.state.eventsEnabled) {
      await _maybeEvent(cardId, data);
      data = await repository.snapshot(cardId);
    }
    final input = currentMessage.toLowerCase();
    final now = DateTime.now().millisecondsSinceEpoch;
    final lore = data.lore
        .where((entry) {
          if (!entry.enabled || entry.kind != 'lore') return false;
          if (entry.triggers.isEmpty) return false;
          return entry.triggers.any(
            (word) =>
                word.trim().isNotEmpty && input.contains(word.toLowerCase()),
          );
        })
        .take(4)
        .map((item) => {'title': item.title, 'text': item.content})
        .toList();
    final memories = data.state.memoryEnabled
        ? data.memories
              .where((memory) {
                if (memory.kind == 'user_reply') {
                  return memory.pinned ||
                      now - memory.createdAtMs <
                          const Duration(days: 3).inMilliseconds;
                }
                if (memory.kind == 'episode') return memory.pinned;
                return memory.pinned || memory.importance >= 3;
              })
              .take(6)
              .map(
                (e) => {'type': e.kind, 'text': e.content, 'origin': e.source},
              )
              .toList()
        : <Map<String, String>>[];
    final recentTopics = (data.state.memoryEnabled ? data.topics : <RpTopic>[])
        .where(
          (e) =>
              e.status == 'resolved' ||
              e.cooldownUntilMs > now ||
              e.status == 'cooling',
        )
        .take(12)
        .map((e) => e.label)
        .toList();
    final active = data.events
        .where((e) => e.status == 'active')
        .take(1)
        .toList();
    return <String, Object?>{
      'runtime_schema': 1,
      'character': {
        'scene': data.state.scene,
        'current_activity': data.state.activity,
        'current_goal': data.state.goal,
        'energy_hint': data.state.energy,
      },
      if (data.state.memoryEnabled) 'relevant_memories': memories,
      if (lore.isNotEmpty) 'activated_lorebook': lore,
      if (data.state.eventsEnabled && active.isNotEmpty)
        'fictional_rp_event': {
          'title': active.first.title,
          'setup': active.first.description,
          'rule': '这是角色虚构世界中的情境，不是真实用户经历；可轻描淡写或不提。',
        },
      'do_not_proactively_repeat': recentTopics,
      'interaction_guidance':
          '角色有独立审美、好奇与主见，不要机械地总结用户，更不要靠重复往事维持熟悉感。'
          '未由用户明确重新提起的已结束话题，优先转向眼前内容或新话题。'
          '不必每次询问用户；若发问，应是一句真正想了解的具体问题。'
          '角色的叙事状态不证明真实世界发生过这些事。',
    };
  }

  Future<void> _maybeEvent(String cardId, RpSnapshot data) async {
    final now = DateTime.now();
    final day = _day(now);
    if (!await repository.claimDailyRoll(cardId, day)) return;
    final available = data.lore
        .where(
          (e) =>
              e.enabled &&
              e.kind == 'event' &&
              now.millisecondsSinceEpoch - e.lastTriggeredMs >=
                  Duration(hours: e.cooldownHours).inMilliseconds,
        )
        .toList();
    if (available.isEmpty) return;
    final random = Random(_seed('$cardId:$day:rp-v21'));
    // A little unpredictability is preferable to forcing an event each day.
    if (random.nextInt(100) >= 38) return;
    available.sort((a, b) => b.priority.compareTo(a.priority));
    final shuffled = [...available]..shuffle(random);
    for (final entry in shuffled) {
      if (random.nextInt(100) >= entry.chance) continue;
      await repository.beginEvent(cardId, entry);
      return;
    }
  }

  /// Only explicit, first-person preferences become durable facts. Ordinary
  /// chatter becomes short-lived episodic context, never a pinned preference.
  Future<void> recordTurn(
    String cardId,
    String user,
    String reply, {
    String conversationKey = '',
  }) async {
    final content = _clean(user, 240);
    if (content.isEmpty) return;
    final state = await repository.ensureState(cardId);
    if (!state.memoryEnabled) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final wantsEnd = RegExp(r'翻篇|换个话题|不要再提|别再提|不想再聊|就聊到这').hasMatch(content);
    if (wantsEnd) {
      final history = await repository.snapshot(cardId);
      final explicitMatch = history.topics
          .take(12)
          .any((topic) => content.contains(topic.label));
      for (final topic in history.topics.take(12)) {
        if (content.contains(topic.label) ||
            (!explicitMatch && topic.status == 'active')) {
          await repository.putTopic(cardId, topic.key, topic.label, 'cooling');
        }
      }
    }
    final explicitPreference = RegExp(
      r'(^|[。！？\n])\s*(?:我(?:真的|特别|更|很)?(?:喜欢|偏爱|讨厌|不喜欢)|请记住|以后请)',
    ).hasMatch(content);
    if (explicitPreference && !content.contains('别记住')) {
      await repository.remember(
        cardId,
        'preference',
        content,
        source: 'explicit_user_chat',
        conversationKey: conversationKey,
        importance: 4,
      );
    } else {
      await repository.remember(
        cardId,
        'episode',
        content,
        source: 'user_chat',
        conversationKey: conversationKey,
        importance: 1,
        expiresAtMs: now + const Duration(days: 7).inMilliseconds,
      );
    }
    final requestTopic = RegExp(r'(?:聊聊|谈谈|说说|关于)([^，。！？]{2,16})')
        .firstMatch(content);
    if (requestTopic != null && !wantsEnd) {
      final label = _clean(requestTopic.group(1) ?? '', 16);
      if (label.isNotEmpty) {
        await repository.putTopic(cardId, _key(label), label, 'active');
      }
    }
    await repository.prune(cardId);
  }

  /// A writer's theme becomes an anti-repetition signal after the letter is
  /// committed, not a permanent user preference.
  Future<void> recordLetter(
    String cardId, {
    required String title,
    required String day,
    required int generation,
    String topic = '',
  }) async {
    final state = await repository.ensureState(cardId);
    if (!state.memoryEnabled) return;
    final label = _clean(
      topic.isNotEmpty ? topic : (title == '写给你的今日音乐信' ? '' : title),
      28,
    );
    if (label.isNotEmpty) {
      await repository.putTopic(
        cardId,
        _key(label),
        label,
        'cooling',
        origin: 'letter',
      );
    }
    await repository.remember(
      cardId,
      'episode',
      '写过一封题为《${_clean(title, 48)}》的信。',
      source: 'generated_letter',
      conversationKey: '$day:$generation',
      importance: 1,
      expiresAtMs:
          DateTime.now().millisecondsSinceEpoch +
          const Duration(days: 14).inMilliseconds,
    );
    await repository.prune(cardId);
  }

  Future<void> recordUserReply(
    String cardId,
    String letterKey,
    String text,
  ) async {
    final state = await repository.ensureState(cardId);
    if (!state.memoryEnabled) return;
    await repository.remember(
      cardId,
      'user_reply',
      _clean(text, 200),
      source: 'explicit_saved_reply',
      conversationKey: letterKey,
      importance: 3,
    );
  }

  Future<void> markTopic(String cardId, String topic, String status) async {
    final text = _clean(topic, 28);
    if (text.isEmpty || !['active', 'cooling', 'resolved'].contains(status))
      return;
    await repository.putTopic(
      cardId,
      _key(text),
      text,
      status,
      origin: 'manual',
    );
  }
}
