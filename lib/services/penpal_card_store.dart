import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;

import '../core/penpal_card.dart';
import '../data/app_db.dart';
import 'api_settings.dart';
import 'penpal_prompt_presets.dart';

/// Local roster. Built-in Easter eggs are *not* seeded into the roster.
/// Only an explicit discovery from the icon Easter egg reveals them.
class PenpalCardStore extends ChangeNotifier {
  PenpalCardStore(this.db, this.settings);
  final AppDb db;
  final ApiSettings settings;
  static const primaryId = 'primary';
  static const _uuid = Uuid();
  String activeName = '我的音乐笔友';
  bool _ready = false;
  bool _closed = false;
  String _activeAvatarPath = '';
  Future<void> _avatarWork = Future.value();
  static final _avatarName = RegExp(r'^avatar-[0-9a-f-]+\.png$');

  File? _avatarFile(String relative) {
    if (p.dirname(relative) != 'penpal_avatars' ||
        !_avatarName.hasMatch(p.basename(relative)))
      return null;
    return File(p.join(db.root.path, relative));
  }

  File? avatarFile(PenpalCard card) => _avatarFile(card.avatarPath);
  File? get activeAvatarFile => _avatarFile(_activeAvatarPath);

  Future<void> _queueAvatar(Future<void> Function() work) {
    if (_closed) return Future.error(StateError('角色卡服务已关闭'));
    final next = _avatarWork.then((_) => work());
    _avatarWork = next.catchError((Object _) {});
    return next;
  }

  Future<void> _removeAvatar(String relative) async {
    final file = _avatarFile(relative);
    if (file != null) {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException catch (_) {}
    }
  }

  Future<void> setAvatar(String id, List<int> bytes) => _queueAvatar(() async {
    final card = await get(id);
    if (card == null) throw StateError('角色卡不存在');
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
      throw const FormatException('请选择小于 8 MiB 的图片');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      Uint8List.fromList(bytes),
    );
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) {
        final scale = math.min(1.0, 512 / math.max(width, height));
        return ui.TargetImageSize(
          width: math.max(1, (width * scale).round()),
          height: math.max(1, (height * scale).round()),
        );
      },
    );
    late final ui.FrameInfo frame;
    try {
      frame = await codec.getNextFrame();
    } finally {
      codec.dispose();
    }
    ByteData? data;
    try {
      data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      frame.image.dispose();
    }
    if (data == null) throw const FormatException('无法读取头像图片');
    final relative = p.join('penpal_avatars', 'avatar-${_uuid.v4()}.png');
    final target = _avatarFile(relative)!;
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    try {
      await temporary.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await temporary.rename(target.path);
      final count = await db.db.update(
        'penpal_cards',
        {
          'art_path': relative,
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'card_id=?',
        whereArgs: [id],
      );
      if (count == 0) throw StateError('角色卡已删除');
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      if (await target.exists()) await target.delete();
      rethrow;
    }
    if (id == activeId) _activeAvatarPath = relative;
    await _removeAvatar(card.avatarPath);
    if (!_closed) notifyListeners();
  });

  Future<void> clearAvatar(String id) => _queueAvatar(() async {
    final card = await get(id);
    if (card == null) throw StateError('角色卡不存在');
    await db.db.update(
      'penpal_cards',
      {'art_path': ''},
      where: 'card_id=?',
      whereArgs: [id],
    );
    if (id == activeId) _activeAvatarPath = '';
    await _removeAvatar(card.avatarPath);
    if (!_closed) notifyListeners();
  });

  String get activeId => settings.activeCardId;

  Future<void> initialize() async {
    if (_ready) return;
    // Database migration creates the initial card from the previously active
    // System/User prompts. Never auto-populate Venti/Sylphiette.
    final count = await db.db.rawQuery(
      'SELECT COUNT(*) AS n FROM penpal_cards',
    );
    if ((count.first['n'] as int? ?? 0) == 0) {
      // Only an exact match to a previously applied bundled card is evidence
      // that the user *already opted in* before upgrading. Fresh installs and
      // unrelated prompts never discover the hidden Easter eggs.
      String? knownPreset;
      final currentSystem = settings.llmSystemPrompt;
      final possiblePreset = currentSystem.startsWith('你以《原神》温迪（Venti）的形象')
          ? 'venti'
          : currentSystem.startsWith('你以《无职转生》希露菲叶特·格雷拉特')
          ? 'sylphiette'
          : null;
      if (possiblePreset != null) {
        try {
          final preset = possiblePreset == 'venti'
              ? await PenpalPromptPreset.venti()
              : await PenpalPromptPreset.sylphiette();
          if (currentSystem == preset.system &&
              settings.llmUserPrompt == preset.user) {
            knownPreset = possiblePreset;
          }
        } catch (_) {
          // Missing bundled assets must not prevent restoring the default card.
        }
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.db.transaction((tx) async {
        await tx.insert('penpal_cards', {
          'card_id': primaryId,
          'name': '我的音乐笔友',
          'system_prompt': knownPreset == null
              ? settings.llmSystemPrompt
              : ApiSettings.defaultLlmSystemPrompt,
          'user_prompt': knownPreset == null
              ? settings.llmUserPrompt
              : ApiSettings.defaultLlmUserPrompt,
          'created_at_ms': now,
          'updated_at_ms': now,
        });
        if (knownPreset != null) {
          await tx.insert('penpal_cards', {
            'card_id': knownPreset,
            'name': knownPreset == 'venti' ? '温迪' : '希露菲',
            'system_prompt': settings.llmSystemPrompt,
            'user_prompt': settings.llmUserPrompt,
            'is_builtin': 1,
            'preset_id': knownPreset,
            'created_at_ms': now,
            'updated_at_ms': now,
          });
          await tx.rawInsert(
            'INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)',
            ['penpal_active_card_id', knownPreset],
          );
          // Respect the old memory opt-out for this previously active role.
          final inherited = await tx.query(
            'penpal_card_memory_state',
            where: 'card_id=?',
            whereArgs: [primaryId],
            limit: 1,
          );
          if (inherited.isNotEmpty) {
            await tx.insert('penpal_card_memory_state', {
              ...inherited.first,
              'card_id': knownPreset,
            });
          }
        }
      });
    }
    final saved = await db.setting('penpal_active_card_id');
    final selected = saved != null ? await get(saved) : null;
    final current =
        selected ?? await get(primaryId) ?? (await list()).firstOrNull;
    if (current == null) throw StateError('缺少默认音乐笔友');
    activeName = current.name;
    _activeAvatarPath = current.avatarPath;
    settings.adoptCharacterCard(current.id, current.system, current.user);
    // Preserve old conversations that can be matched to the *current* prompt.
    // Other historical hashes are left unattributed, never assigned by guess.
    final legacyHash = sha256.convert(utf8.encode(current.system)).toString();
    await db.db.rawUpdate(
      'UPDATE penpal_chat_messages SET persona_key=? WHERE persona_key=?',
      [current.id, legacyHash],
    );
    _ready = true;
  }

  Future<List<PenpalCard>> list() async => (await db.db.query(
    'penpal_cards',
    orderBy: 'created_at_ms ASC,card_id ASC',
  )).map(PenpalCard.fromRow).toList();

  Future<PenpalCard?> get(String id) async {
    final rows = await db.db.query(
      'penpal_cards',
      where: 'card_id=?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : PenpalCard.fromRow(rows.first);
  }

  Future<void> activate(String id) async {
    final card = await get(id);
    if (card == null) throw StateError('角色卡不存在');
    if (settings.activeCardId == id &&
        settings.llmSystemPrompt == card.system &&
        settings.llmUserPrompt == card.user)
      return;
    final revision = settings.llmRevision + 1;
    await db.db.transaction((tx) async {
      for (final e in {
        'penpal_active_card_id': id,
        'api_llm_system_prompt': card.system,
        'api_llm_user_prompt': card.user,
        'api_llm_revision': '$revision',
      }.entries) {
        await tx.rawInsert(
          'INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)',
          [e.key, e.value],
        );
      }
    });
    activeName = card.name;
    _activeAvatarPath = card.avatarPath;
    settings.adoptCharacterCard(
      card.id,
      card.system,
      card.user,
      revision: revision,
    );
    notifyListeners();
  }

  Future<PenpalCard> create({
    required String name,
    required String system,
    required String user,
    String? forcedId,
    String presetId = '',
    bool builtin = false,
  }) async {
    if (_closed) throw StateError('角色卡服务已关闭');
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 80) {
      throw const FormatException('角色名需要 1–80 字');
    }
    final sys = ApiSettings.validateLlmSystemPrompt(system);
    final usr = ApiSettings.validateLlmUserPrompt(user);
    final id = forcedId ?? _uuid.v4();
    final existing = await get(id);
    if (existing != null) return existing;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.db.insert('penpal_cards', {
      'card_id': id,
      'name': cleanName,
      'system_prompt': sys,
      'user_prompt': usr,
      'is_builtin': builtin ? 1 : 0,
      'preset_id': presetId,
      'created_at_ms': now,
      'updated_at_ms': now,
    });
    notifyListeners();
    return (await get(id))!;
  }

  /// Calling this method is deliberately the only way an Easter egg appears.
  Future<PenpalCard> discover(String preset) async {
    if (preset != 'venti' && preset != 'sylphiette') {
      throw const FormatException('未知的内置彩蛋');
    }
    final prompts = preset == 'venti'
        ? await PenpalPromptPreset.venti()
        : await PenpalPromptPreset.sylphiette();
    final card = await create(
      forcedId: preset,
      presetId: preset,
      builtin: true,
      name: preset == 'venti' ? '温迪' : '希露菲',
      system: prompts.system,
      user: prompts.user,
    );
    await activate(card.id);
    return card;
  }

  Future<PenpalCard> duplicate(PenpalCard original) => create(
    name: '${original.name} · 副本',
    system: original.system,
    user: original.user,
  );

  Future<void> updateCard(
    String id, {
    required String name,
    required String system,
    required String user,
  }) async {
    if (_closed) throw StateError('角色卡服务已关闭');
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 80) {
      throw const FormatException('角色名需要 1–80 字');
    }
    final newSystem = ApiSettings.validateLlmSystemPrompt(system);
    final newUser = ApiSettings.validateLlmUserPrompt(user);
    final active = id == activeId;
    final revision = settings.llmRevision + 1;
    await db.db.transaction((tx) async {
      final existing = await tx.query(
        'penpal_cards',
        where: 'card_id=?',
        whereArgs: [id],
        limit: 1,
      );
      if (existing.isEmpty) throw StateError('角色卡不存在');
      await tx.update(
        'penpal_cards',
        {
          'name': cleanName,
          'system_prompt': newSystem,
          'user_prompt': newUser,
          'is_builtin': 0,
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'card_id=?',
        whereArgs: [id],
      );
      if (active) {
        for (final entry in {
          'api_llm_system_prompt': newSystem,
          'api_llm_user_prompt': newUser,
          'api_llm_revision': '$revision',
        }.entries) {
          await tx.rawInsert(
            'INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)',
            [entry.key, entry.value],
          );
        }
      }
    });
    if (active) {
      activeName = cleanName;
      settings.adoptCharacterCard(id, newSystem, newUser, revision: revision);
    }
    notifyListeners();
  }

  Future<PenpalCard> importJson(String raw) async {
    if (raw.length > 150000) throw const FormatException('角色卡 JSON 过大');
    final o = jsonDecode(raw);
    if (o is! Map) throw const FormatException('角色卡 JSON 结构无效');
    final sys = o['system'];
    final usr = o['user'];
    if (sys is! String || usr is! String) {
      throw const FormatException('需要 system 和 user 文本字段');
    }
    return create(
      name: (o['name'] as String?) ?? '导入的笔友',
      system: sys,
      user: usr,
    );
  }

  String exportJson(PenpalCard card) =>
      const JsonEncoder.withIndent('  ').convert(card.toExport());

  /// Switch the active identity in the same transaction as deletion.
  Future<void> delete(String id) => _queueAvatar(() async {
    if (_closed) throw StateError('角色卡服务已关闭');
    String removedAvatar = '';
    PenpalCard? replacement;
    final active = id == activeId;
    final revision = settings.llmRevision + 1;
    await db.db.transaction((tx) async {
      final target = await tx.query(
        'penpal_cards',
        where: 'card_id=?',
        whereArgs: [id],
        limit: 1,
      );
      if (target.isEmpty) throw StateError('角色卡不存在');
      removedAvatar = target.first['art_path'] as String? ?? '';
      final remaining = await tx.query(
        'penpal_cards',
        where: 'card_id<>?',
        whereArgs: [id],
        orderBy: 'created_at_ms ASC,card_id ASC',
        limit: 1,
      );
      if (remaining.isEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final fresh = <String, Object?>{
          'card_id': _uuid.v4(),
          'name': '我的音乐笔友',
          'system_prompt': ApiSettings.defaultLlmSystemPrompt,
          'user_prompt': ApiSettings.defaultLlmUserPrompt,
          'created_at_ms': now,
          'updated_at_ms': now,
        };
        await tx.insert('penpal_cards', fresh);
        replacement = PenpalCard.fromRow({...fresh, 'is_builtin': 0});
      } else if (active) {
        replacement = PenpalCard.fromRow(remaining.first);
      }
      if (active) {
        final next = replacement!;
        for (final entry in {
          'penpal_active_card_id': next.id,
          'api_llm_system_prompt': next.system,
          'api_llm_user_prompt': next.user,
          'api_llm_revision': '$revision',
        }.entries) {
          await tx.rawInsert(
            'INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)',
            [entry.key, entry.value],
          );
        }
      }
      await tx.delete(
        'penpal_memory_events',
        where: 'card_id=?',
        whereArgs: [id],
      );
      await tx.delete(
        'penpal_chat_messages',
        where: 'persona_key=?',
        whereArgs: [id],
      );
      await tx.delete(
        'penpal_card_memory_state',
        where: 'card_id=?',
        whereArgs: [id],
      );
      await tx.delete('penpal_cards', where: 'card_id=?', whereArgs: [id]);
      // Historical letters retain their original author ID.
    });
    if (active) {
      final next = replacement!;
      activeName = next.name;
      _activeAvatarPath = next.avatarPath;
      settings.adoptCharacterCard(
        next.id,
        next.system,
        next.user,
        revision: revision,
      );
    }
    await _removeAvatar(removedAvatar);
    if (!_closed) notifyListeners();
  });

  Future<void> shutdown() async {
    _closed = true;
    await _avatarWork;
  }
}
