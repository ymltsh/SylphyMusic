/// Explicit, versioned whitelist for manually entered cross-device settings.
/// Never export the SQLite file, queue, catalog, caches, history or switches.
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:path/path.dart' as p;

import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/player_layout.dart';
import 'api_settings.dart';

const _bundleVersion = 1;
const _maxBundleBytes = 48 * 1024 * 1024;
const _maxAssetBytes = 40 * 1024 * 1024;

/// Only user-written values, never enabled/disabled switches, queue or state.
const transferConfigKeys = <String>{
  'api_quote_url',
  'api_github_mirror',
  'api_lrc_url',
  'api_llm_url',
  'api_llm_model',
  'api_llm_system_prompt',
  'api_llm_user_prompt',
  'ui_theme',
  'ui_seed',
  'ui_background_visibility',
  'ui_lyrics_font_size',
  'ui_mini_lyrics_font_size',
  'ui_lyric_page_color_mode',
  'ui_lyric_page_fixed_color',
  'ui_desktop_lyric_color_mode',
  'ui_desktop_lyric_fixed_color',
  'ui_desktop_lyrics_font_size',
  'player_layouts_v1',
};

enum TransferScope { sources, all }

class TransferBundle {
  const TransferBundle({
    required this.scope,
    required this.sources,
    required this.settings,
    required this.keys,
    required this.images,
    required this.cards,
    required this.activeCard,
  });
  final TransferScope scope;
  final List<Map<String, dynamic>> sources;
  final Map<String, String> settings;
  final Map<String, String> keys;
  final Map<String, String> images;
  final List<Map<String, dynamic>> cards;
  final String? activeCard;

  Map<String, dynamic> toJson() => {
    'version': _bundleVersion,
    'scope': scope.name,
    'sources': sources,
    'settings': settings,
    'keys': keys,
    'images': images,
    'cards': cards,
    'activeCard': activeCard,
  };

  static TransferBundle parse(Map<String, dynamic> json) {
    if (json['version'] != _bundleVersion) {
      throw const FormatException('两台设备的迁移数据版本不兼容');
    }
    final scope = TransferScope.values.byName(json['scope'] as String);
    final rawSources = json['sources'];
    if (rawSources is! List || rawSources.length > 100) {
      throw const FormatException('音乐源数量或格式无效');
    }
    final sources = <Map<String, dynamic>>[];
    for (final item in rawSources) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('音乐源配置格式无效');
      }
      sources.add(Map<String, dynamic>.from(item));
    }
    Map<String, String> strings(Object? value) {
      if (value is! Map) throw const FormatException('迁移配置格式无效');
      if (value.length > 100) throw const FormatException('迁移配置数量超限');
      return value.map((key, value) {
        if (key is! String || value is! String) {
          throw const FormatException('迁移配置字段无效');
        }
        return MapEntry(key, value);
      });
    }

    final settings = strings(json['settings']);
    final keys = strings(json['keys']);
    final images = strings(json['images']);
    final rawCards = json['cards'];
    if (rawCards is! List || rawCards.length > 30) {
      throw const FormatException('角色卡数量或格式无效');
    }
    final cards = <Map<String, dynamic>>[];
    for (final item in rawCards) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('角色卡格式无效');
      }
      cards.add(Map<String, dynamic>.from(item));
    }
    final activeCard = json['activeCard'];
    if (activeCard != null && activeCard is! String) {
      throw const FormatException('无效的角色卡选择');
    }
    if (scope == TransferScope.sources &&
        (settings.isNotEmpty ||
            keys.isNotEmpty ||
            images.isNotEmpty ||
            cards.isNotEmpty ||
            activeCard != null)) {
      throw const FormatException('仅音乐源迁移不得包含其他配置');
    }
    final bundle = TransferBundle(
      scope: scope,
      sources: sources,
      settings: settings,
      keys: keys,
      images: images,
      cards: cards,
      activeCard: activeCard as String?,
    );
    if (utf8.encode(jsonEncode(bundle.toJson())).length > _maxBundleBytes) {
      throw const FormatException('迁移包超出 48 MiB 限制');
    }
    return bundle;
  }
}

class TransferPreview {
  const TransferPreview({
    required this.newSources,
    required this.skippedSources,
    required this.settingsCount,
    required this.cardCount,
  });
  final int newSources;
  final int skippedSources;
  final int settingsCount;
  final int cardCount;
}

class DeviceTransferConfig {
  const DeviceTransferConfig(this.app);
  final SylphyApp app;

  /// Values read from AuthVault are secret until encrypted by TransferSession.
  Future<TransferBundle> export(TransferScope scope) async {
    final sources = <Map<String, dynamic>>[];
    for (final profile in app.sources) {
      if (profile.kind == SourceKind.local) continue;
      final secrets = <String, String>{};
      for (final field in ['token', 'password', 'userId', 'serverId']) {
        final value = await app.vault.read(profile.id, field);
        if (value != null && value.isNotEmpty) secrets[field] = value;
      }
      sources.add({
        'name': profile.name,
        'kind': profile.kind.name,
        'url': profile.url,
        'username': profile.username,
        'remoteUserId': profile.remoteUserId,
        'webdavBasePath': profile.webdavBasePath,
        'webdavMaxDepth': profile.webdavMaxDepth,
        'secrets': secrets,
      });
    }
    final settings = <String, String>{};
    final keys = <String, String>{};
    final images = <String, String>{};
    final cards = <Map<String, dynamic>>[];
    String? activeCard;
    if (scope == TransferScope.all) {
      for (final key in transferConfigKeys) {
        final value = await app.db.setting(key);
        if (value != null) settings[key] = value;
      }
      for (final name in ['llm', 'lrcapi']) {
        final value = await app.vault.read(name, 'token');
        if (value != null && value.isNotEmpty) keys[name] = value;
      }
      final background = app.appearance.backgroundFile;
      if (background != null && await background.exists()) {
        final bytes = await background.readAsBytes();
        if (bytes.length > _maxAssetBytes) {
          throw const FormatException('自定义背景图片过大，无法迁移');
        }
        images['background'] = base64Encode(bytes);
      }
      final storedCards = await app.db.db.query(
        'penpal_cards',
        orderBy: 'created_at_ms ASC',
      );
      for (final row in storedCards) {
        final id = row['card_id'] as String;
        final entry = <String, dynamic>{
          'id': id,
          'name': row['name'],
          'system': row['system_prompt'],
          'user': row['user_prompt'],
          'preset': row['preset_id'] ?? '',
          'artPrompt': row['art_prompt'] ?? '',
          'builtin': row['is_builtin'] == 1,
        };
        final card = await app.apiSettings.cards.get(id);
        final avatar = card == null
            ? null
            : app.apiSettings.cards.avatarFile(card);
        if (avatar != null && await avatar.exists()) {
          final bytes = await avatar.readAsBytes();
          if (bytes.length > 8 * 1024 * 1024) {
            throw const FormatException('角色卡头像过大，无法迁移');
          }
          entry['avatar'] = base64Encode(bytes);
        }
        cards.add(entry);
      }
      activeCard = app.apiSettings.activeCardId;
    }
    return TransferBundle.parse(
      TransferBundle(
        scope: scope,
        sources: sources,
        settings: settings,
        keys: keys,
        images: images,
        cards: cards,
        activeCard: activeCard,
      ).toJson(),
    );
  }

  /// Never trust incoming raw source fields, URLs, settings, file names or IDs.
  Future<TransferPreview> preview(TransferBundle bundle) async {
    _validate(bundle);
    final existing = await app.db.sources();
    var fresh = 0;
    var duplicate = 0;
    for (final row in bundle.sources) {
      final candidate = _sourceFromRow(row, 'preview');
      if (existing.any((s) => sameRemoteSource(s, candidate))) {
        duplicate++;
      } else {
        fresh++;
      }
    }
    return TransferPreview(
      newSources: fresh,
      skippedSources: duplicate,
      settingsCount:
          bundle.settings.length + bundle.keys.length + bundle.images.length,
      cardCount: bundle.cards.length,
    );
  }

  static bool sameRemoteSource(SourceProfile a, SourceProfile b) =>
      a.kind == b.kind &&
      a.username.trim().toLowerCase() == b.username.trim().toLowerCase() &&
      a.url.trim().replaceFirst(RegExp(r'/+$'), '').toLowerCase() ==
          b.url.trim().replaceFirst(RegExp(r'/+$'), '').toLowerCase() &&
      a.webdavBasePath == b.webdavBasePath;

  static SourceProfile _sourceFromRow(Map<String, dynamic> row, String id) {
    String require(String key, {int max = 2048}) {
      final value = row[key];
      if (value is! String || value.length > max) {
        throw FormatException('音乐源字段 $key 无效');
      }
      return value;
    }

    final kind = SourceKind.values.byName(require('kind', max: 30));
    if (kind == SourceKind.local) {
      throw const FormatException('本地音乐需要在新设备重新选取目录');
    }
    final url = require('url');
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('音乐源 URL 格式不安全');
    }
    final depth = row['webdavMaxDepth'];
    if (depth is! int || depth < -1 || depth > 100) {
      throw const FormatException('WebDAV 扫描深度无效');
    }
    return SourceProfile(
      id: id,
      name: require('name', max: 120),
      kind: kind,
      url: url,
      username: require('username', max: 256),
      remoteUserId: require('remoteUserId', max: 256),
      webdavBasePath: require('webdavBasePath'),
      webdavMaxDepth: depth,
    );
  }

  static void _validate(TransferBundle bundle) {
    for (final row in bundle.sources) {
      _sourceFromRow(row, 'validate');
      final secrets = row['secrets'];
      if (secrets is! Map || secrets.length > 4) {
        throw const FormatException('音乐源凭据格式无效');
      }
      for (final entry in secrets.entries) {
        if (!['token', 'password', 'userId', 'serverId'].contains(entry.key) ||
            entry.value is! String ||
            (entry.value as String).length > 16384) {
          throw const FormatException('音乐源凭据字段无效');
        }
      }
    }
    if (!bundle.settings.keys.toSet().difference(transferConfigKeys).isEmpty) {
      throw const FormatException('含有未允许迁移的设置字段');
    }
    if (!bundle.keys.keys.toSet().difference({'llm', 'lrcapi'}).isEmpty ||
        bundle.keys.values.any((value) => value.length > 16384)) {
      throw const FormatException('API 凭据字段无效');
    }
    if (!bundle.images.keys.toSet().difference({'background'}).isEmpty) {
      throw const FormatException('未知的迁移图片');
    }
    for (final item in bundle.images.values) {
      if (item.length > (_maxAssetBytes * 4 ~/ 3 + 8) ||
          base64Decode(item).length > _maxAssetBytes) {
        throw const FormatException('迁移图片过大');
      }
    }
    for (final entry in bundle.settings.entries) {
      final value = entry.value;
      if (value.length > 256 * 1024) {
        throw const FormatException('设置字段过大');
      }
      switch (entry.key) {
        case 'api_quote_url':
          ApiSettings.validateQuoteUrl(value);
          break;
        case 'api_github_mirror':
          ApiSettings.validateGitHubMirror(value);
          break;
        case 'api_lrc_url':
          ApiSettings.validateLrcApiUrl(value);
          break;
        case 'api_llm_url':
          ApiSettings.validateLlmUrl(value);
          break;
        case 'api_llm_model':
          ApiSettings.validateLlmModel(value);
          break;
        case 'api_llm_system_prompt':
          ApiSettings.validateLlmSystemPrompt(value);
          break;
        case 'api_llm_user_prompt':
          ApiSettings.validateLlmUserPrompt(value);
          break;
        case 'ui_theme':
          if (!['system', 'light', 'dark'].contains(value)) {
            throw const FormatException('主题模式无效');
          }
          break;
        case 'player_layouts_v1':
          final layout = jsonDecode(value);
          if (layout is! Map ||
              layout['templates'] is! List ||
              (layout['templates'] as List).length > 20 ||
              ![1, 2].contains(layout['version'])) {
            throw const FormatException('播放器布局版本不兼容');
          }
          for (final template in layout['templates'] as List) {
            PlayerLayout.fromJson(Map<String, dynamic>.from(template as Map));
          }
          break;
        default:
          if (value.length > 256) {
            throw const FormatException('外观字段过大');
          }
          break;
      }
    }
    for (final card in bundle.cards) {
      if (card['id'] is! String ||
          (card['id'] as String).length > 128 ||
          card['name'] is! String ||
          (card['name'] as String).length > 80 ||
          card['system'] is! String ||
          card['user'] is! String ||
          card['builtin'] is! bool ||
          card['preset'] is! String ||
          card['artPrompt'] is! String ||
          (card['artPrompt'] as String).length > 64000) {
        throw const FormatException('角色卡字段无效');
      }
      ApiSettings.validateLlmSystemPrompt(card['system'] as String);
      ApiSettings.validateLlmUserPrompt(card['user'] as String);
      final image = card['avatar'];
      if (image != null) {
        if (image is! String || image.length > 12 * 1024 * 1024) {
          throw const FormatException('角色卡图片无效');
        }
        final bytes = base64Decode(image);
        const pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
        if (bytes.length > 8 * 1024 * 1024 ||
            bytes.length < 8 ||
            List.generate(8, (i) => bytes[i]).join(',') !=
                pngSignature.join(',')) {
          throw const FormatException('角色卡头像不是有效的 PNG 文件');
        }
      }
    }
  }

  /// Config is imported as a *merge*: existing source accounts remain untouched.
  /// All settings are staged before mutating storage; on write failure new
  /// sources and secret values are reverted. A restart may be necessary for
  /// other services to reload their newly imported authoring preferences.
  Future<int> apply(TransferBundle bundle) async {
    await preview(bundle);
    if (app.busy) throw StateError('请在当前扫描或同步任务结束后迁移');
    final oldSources = await app.db.sources();
    final created = <SourceProfile>[];
    final newSecrets = <String, Map<String, String>>{};
    for (final row in bundle.sources) {
      final candidate = _sourceFromRow(row, const Uuid().v4());
      if (oldSources.any((s) => sameRemoteSource(s, candidate)) ||
          created.any((s) => sameRemoteSource(s, candidate)))
        continue;
      created.add(candidate);
      newSecrets[candidate.id] = Map<String, String>.from(
        row['secrets'] as Map,
      );
    }
    final oldSettings = <String, String?>{};
    final bumpLlm = bundle.settings.keys.any(
      (key) => key.startsWith('api_llm_'),
    );
    for (final key in <String>{
      ...bundle.settings.keys,
      if (bumpLlm) 'api_llm_revision',
    }) {
      oldSettings[key] = await app.db.setting(key);
    }
    final oldKeys = <String, String?>{};
    for (final key in bundle.keys.keys) {
      oldKeys[key] = await app.vault.read(key, 'token');
    }
    final oldPrimary = await app.db.db.query(
      'penpal_cards',
      where: 'card_id=?',
      whereArgs: ['primary'],
    );
    final oldActiveCard = await app.db.setting('penpal_active_card_id');
    final existingCards = await app.db.db.query('penpal_cards');
    final stagedAvatarFiles = <File>[];
    final stagedCards = <Map<String, Object?>>[];
    final ids = <String, String>{};
    try {
      for (final card in bundle.cards) {
        final oldId = card['id'] as String;
        final identical = oldId == 'primary'
            ? <Map<String, Object?>>[]
            : existingCards
                  .where(
                    (row) =>
                        row['name'] == card['name'] &&
                        row['system_prompt'] == card['system'] &&
                        row['user_prompt'] == card['user'],
                  )
                  .toList();
        if (identical.isNotEmpty) {
          ids[oldId] = identical.first['card_id'] as String;
          continue;
        }
        final newId = oldId == 'primary' ? oldId : const Uuid().v4();
        ids[oldId] = newId;
        String avatarPath = '';
        final image = card['avatar'];
        if (image is String) {
          final file = File(
            p.join(
              app.root.path,
              'penpal_avatars',
              'avatar-${const Uuid().v4()}.png',
            ),
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(base64Decode(image), flush: true);
          stagedAvatarFiles.add(file);
          avatarPath = p.join('penpal_avatars', p.basename(file.path));
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        stagedCards.add({
          'card_id': newId,
          'name': card['name'],
          'system_prompt': card['system'],
          'user_prompt': card['user'],
          'preset_id': card['preset'],
          'art_prompt': card['artPrompt'],
          'is_builtin': card['builtin'] == true ? 1 : 0,
          'art_path': avatarPath,
          'created_at_ms': now,
          'updated_at_ms': now,
        });
      }
      for (final entry in newSecrets.entries) {
        for (final secret in entry.value.entries) {
          await app.vault.write(entry.key, secret.key, secret.value);
        }
      }
      for (final entry in bundle.keys.entries) {
        await app.vault.write(entry.key, 'token', entry.value);
      }
      await app.db.db.transaction((tx) async {
        for (final profile in created) {
          await tx.insert('sources', profile.toRow());
        }
        for (final item in bundle.settings.entries) {
          await tx.rawInsert(
            'INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)',
            [item.key, item.value],
          );
        }
        if (bumpLlm) {
          final nextRevision =
              (int.tryParse(oldSettings['api_llm_revision'] ?? '') ?? 0) + 1;
          await tx.rawInsert(
            'INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)',
            ['api_llm_revision', '$nextRevision'],
          );
        }
        for (final item in stagedCards) {
          // The default card already exists; preserve its identity, but
          // replace its user-authored prompts. Other cards get new IDs.
          await tx.insert(
            'penpal_cards',
            item,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        final selected = ids[bundle.activeCard];
        if (selected != null) {
          await tx.rawInsert(
            'INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)',
            ['penpal_active_card_id', selected],
          );
        }
      });
      await app.reload();
      if (bundle.scope == TransferScope.all) {
        await app.appearance.initialize();
        await app.apiSettings.initialize();
        await app.playerLayouts.initialize();
      }
      // Import background via the existing safe image normalization workflow.
      final encodedBackground = bundle.images['background'];
      if (encodedBackground != null) {
        final temporary = File(
          p.join(app.root.path, 'transfer-background-${const Uuid().v4()}.png'),
        );
        try {
          await temporary.writeAsBytes(
            base64Decode(encodedBackground),
            flush: true,
          );
          await app.appearance.setBackground(temporary);
        } finally {
          if (await temporary.exists()) await temporary.delete();
        }
      }
      return created.length;
    } catch (_) {
      // Restore DB values and remove newly inserted accounts. Existing sources
      // are never edited. The original sources' tokens remain untouched.
      await app.db.db.transaction((tx) async {
        for (final profile in created) {
          await tx.delete('sources', where: 'id=?', whereArgs: [profile.id]);
        }
        for (final item in oldSettings.entries) {
          if (item.value == null) {
            await tx.delete('settings', where: 'key=?', whereArgs: [item.key]);
          } else {
            await tx.rawInsert(
              'INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)',
              [item.key, item.value],
            );
          }
        }
        if (oldPrimary.isNotEmpty) {
          await tx.insert(
            'penpal_cards',
            oldPrimary.first,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        if (oldActiveCard == null) {
          await tx.delete(
            'settings',
            where: 'key=?',
            whereArgs: ['penpal_active_card_id'],
          );
        } else {
          await tx.rawInsert(
            'INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)',
            ['penpal_active_card_id', oldActiveCard],
          );
        }
        for (final item in stagedCards) {
          if (item['card_id'] != 'primary') {
            await tx.delete(
              'penpal_cards',
              where: 'card_id=?',
              whereArgs: [item['card_id']],
            );
          }
        }
      });
      for (final profile in created) {
        await app.vault.delete(profile.id);
      }
      for (final entry in oldKeys.entries) {
        if (entry.value == null) {
          await app.vault.delete(entry.key);
        } else {
          await app.vault.write(entry.key, 'token', entry.value!);
        }
      }
      for (final file in stagedAvatarFiles) {
        if (await file.exists()) await file.delete();
      }
      await app.reload();
      rethrow;
    }
  }
}
