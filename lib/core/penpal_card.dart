/// Stable identity for a penpal. Editing a prompt never changes [id].
class PenpalCard {
  const PenpalCard({
    required this.id,
    required this.name,
    required this.system,
    required this.user,
    required this.builtin,
    this.presetId = '',
    this.avatarPath = '',
  });
  final String id;
  final String name;
  final String system;
  final String user;
  final bool builtin;
  final String presetId;
  final String avatarPath;

  factory PenpalCard.fromRow(Map<String, Object?> row) => PenpalCard(
    id: row['card_id'] as String,
    name: row['name'] as String,
    system: row['system_prompt'] as String,
    user: row['user_prompt'] as String,
    builtin: row['is_builtin'] == 1,
    presetId: row['preset_id'] as String? ?? '',
    avatarPath: row['art_path'] as String? ?? '',
  );

  Map<String, Object?> toExport() => {
    'format': 'sylphy-penpal-card',
    'version': 1,
    'name': name,
    'system': system,
    'user': user,
  };
}
