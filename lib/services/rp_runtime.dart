import 'dart:math';

import '../core/rp_models.dart';
import '../data/rp_repository.dart';

/// Foreground-only RP coordinator. No timers, background agent or network calls.
/// The caller may use this even when the music library is empty.
class RpRuntime {
  const RpRuntime(this.repository);
  final RpRepository repository;

  Future<RpSnapshot> snapshot(String cardId) => repository.snapshot(cardId);

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

  /// Character state + activated lore; durable memory comes from the
  /// journal context, never a parallel fragment/topic database.
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
      if (lore.isNotEmpty) 'activated_lorebook': lore,
      if (data.state.eventsEnabled && active.isNotEmpty)
        'fictional_rp_event': {
          'title': active.first.title,
          'setup': active.first.description,
          'rule': '这是角色虚构世界中的情境，不是真实用户经历；可轻描淡写或不提。',
        },
      'interaction_guidance':
          '角色有独立审美、好奇与主见，不要机械地总结用户，更不要靠重复往事维持熟悉感。'
          '不应为了展示记忆而强行提起旧事；结合最新交流自然发展话题。'
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
}
