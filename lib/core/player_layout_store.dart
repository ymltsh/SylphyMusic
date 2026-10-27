import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/app_db.dart';
import 'player_layout.dart';

class PlayerLayoutStore extends ChangeNotifier {
  PlayerLayoutStore(this.db);
  final AppDb db;

  /// Kept for compatibility with installations created before the free-form
  /// canvas. The payload itself is versioned and upgraded on read.
  static const settingsKey = 'player_layouts_v1';
  static const storageVersion = 2;
  List<PlayerLayout> _templates = [];
  List<PlayerLayout> get templates => List.unmodifiable(_templates);
  String? _activeId;
  PlayerLayout? get active =>
      _templates.where((e) => e.id == _activeId).firstOrNull;
  bool _closed = false;
  bool loadFailed = false;
  Future<void> _pending = Future.value();

  Future<void> initialize() async {
    final text = await db.setting(settingsKey);
    if (text == null) return;
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      if ((json['version'] != 1 && json['version'] != storageVersion) ||
          json['templates'] is! List ||
          (json['templates'] as List).length > 20) {
        throw const FormatException('布局设置版本不支持');
      }
      final loaded = (json['templates'] as List)
          .map(PlayerLayout.fromJson)
          .toList();
      if (loaded.map((l) => l.id).toSet().length != loaded.length) {
        throw const FormatException('模板重复');
      }
      final id = json['activeId'];
      if (id != null && (id is! String || !loaded.any((l) => l.id == id))) {
        throw const FormatException('模板不存在');
      }
      _templates = loaded;
      _activeId = id as String?;
    } catch (_) {
      loadFailed = true;
      // Leave the stored bytes intact. Only an explicit save replaces them.
    }
  }

  Future<void> save(PlayerLayout layout, {bool asNew = false}) =>
      _queue(() async {
        final checked = PlayerLayout.decode(layout.encode());
        final saved = checked.copyWith(
          id: asNew ? const Uuid().v4() : checked.id,
        );
        final next = [..._templates.where((l) => l.id != saved.id), saved];
        if (next.length > 20) throw const FormatException('最多保存 20 个模板');
        await _write(next, saved.id);
      });
  Future<void> select(String? id) => _queue(() async {
    if (id != null && !_templates.any((e) => e.id == id)) {
      throw const FormatException('模板不存在');
    }
    await _write(_templates, id);
  });
  Future<void> _write(List<PlayerLayout> layouts, String? activeId) async {
    await db.setSetting(
      settingsKey,
      jsonEncode({
        'version': storageVersion,
        'activeId': activeId,
        'templates': layouts.map((l) => l.toJson()).toList(),
      }),
    );
    _templates = List.of(layouts);
    _activeId = activeId;
    loadFailed = false;
    if (!_closed) notifyListeners();
  }

  Future<void> _queue(Future<void> Function() action) {
    if (_closed) return Future.error(StateError('布局存储已关闭'));
    final result = _pending.then((_) => action());
    _pending = result.catchError((Object _) {});
    return result;
  }

  Future<PlayerLayout?> importFile() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked?.path == null) return null;
    final file = File(picked!.path!);
    if (await file.length() > 128 * 1024) throw const FormatException('布局文件过大');
    return PlayerLayout.decode(await file.readAsString())
        .copyWith(id: const Uuid().v4());
  }

  Future<void> exportFile(PlayerLayout layout) async {
    final checked = PlayerLayout.decode(layout.encode());
    await FilePicker.saveFile(
      fileName: 'sylphy-player-layout.json',
      bytes: Uint8List.fromList(utf8.encode(checked.encode())),
      mimeType: 'application/json',
    );
  }

  Future<void> shutdown() async {
    _closed = true;
    await _pending;
    dispose();
  }
}
