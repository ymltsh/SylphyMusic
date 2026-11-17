/// Structured RP records. Character identities are immutable card IDs.
/// This layer deliberately does not import recommendation or audio models.
class RpCharacterState {
  const RpCharacterState({
    required this.cardId,
    required this.scene,
    required this.activity,
    required this.goal,
    required this.energy,
    required this.memoryEnabled,
    required this.eventsEnabled,
  });

  final String cardId;
  final String scene;
  final String activity;
  final String goal;
  final int energy;
  final bool memoryEnabled;
  final bool eventsEnabled;

  factory RpCharacterState.fromRow(Map<String, Object?> row) =>
      RpCharacterState(
        cardId: row['card_id'] as String,
        scene: row['scene'] as String? ?? '',
        activity: row['activity'] as String? ?? '',
        goal: row['goal'] as String? ?? '',
        energy: row['energy'] as int? ?? 65,
        memoryEnabled: row['memory_enabled'] != 0,
        eventsEnabled: row['events_enabled'] != 0,
      );
}

class RpLoreEntry {
  const RpLoreEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.content,
    required this.triggers,
    required this.priority,
    required this.chance,
    required this.cooldownHours,
    required this.enabled,
    required this.lastTriggeredMs,
  });

  final int id;
  final String kind; // lore or event
  final String title;
  final String content;
  final List<String> triggers;
  final int priority;
  final int chance; // integer percent
  final int cooldownHours;
  final bool enabled;
  final int lastTriggeredMs;

  factory RpLoreEntry.fromRow(Map<String, Object?> row, List<String> words) =>
      RpLoreEntry(
        id: row['id'] as int,
        kind: row['kind'] as String,
        title: row['title'] as String,
        content: row['content'] as String,
        triggers: words,
        priority: row['priority'] as int? ?? 50,
        chance: row['chance'] as int? ?? 30,
        cooldownHours: row['cooldown_hours'] as int? ?? 72,
        enabled: row['enabled'] != 0,
        lastTriggeredMs: row['last_triggered_ms'] as int? ?? 0,
      );
}

class RpEvent {
  const RpEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.startedAtMs,
  });
  final int id;
  final String title;
  final String description;
  final String status;
  final int startedAtMs;

  factory RpEvent.fromRow(Map<String, Object?> row) => RpEvent(
    id: row['id'] as int,
    title: row['title'] as String,
    description: row['description'] as String,
    status: row['status'] as String,
    startedAtMs: row['started_at_ms'] as int,
  );
}

class RpSnapshot {
  const RpSnapshot({
    required this.state,
    required this.lore,
    required this.events,
  });
  final RpCharacterState state;
  final List<RpLoreEntry> lore;
  final List<RpEvent> events;
}
