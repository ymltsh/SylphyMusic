import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';

import '../data/app_db.dart';

class Appearance extends ChangeNotifier {
  Appearance(this.db);
  final AppDb db;
  static const defaultSeed = Color(0xff5094b2);
  ThemeMode mode = ThemeMode.system;
  Color seed = defaultSeed;
  String? _backgroundName;
  double backgroundVisibility = .24;
  bool _closed = false;
  Future<void> _backgroundWork = Future.value();
  static final _managedName = RegExp(r'^background-[0-9a-f-]+\.png$');
  Directory get _backgroundDirectory =>
      Directory(p.join(db.root.path, 'appearance'));
  File? get backgroundFile => _backgroundName == null
      ? null
      : File(p.join(_backgroundDirectory.path, _backgroundName!));
  String get seedHex =>
      '#${(seed.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  bool disc = false, ambient = false, glass = false;
  bool discRotation = false;
  bool solidBackground = true;
  bool playerFab = false;
  double lyricFontSize = 24;
  double miniLyricFontSize = 20;
  static const lyricFontSizes = [20.0, 24.0, 28.0];
  static const miniLyricFontSizes = [16.0, 20.0, 24.0];
  static String lyricFontLabel(double size) => size <= 20
      ? '小'
      : size >= 28
      ? '大'
      : '标准';
  static String miniLyricFontLabel(double size) => size <= 16
      ? '小'
      : size >= 24
      ? '大'
      : '标准';

  Future<void> initialize() async {
    final savedMode = await db.setting('ui_theme');
    mode = ThemeMode.values.firstWhere(
      (v) => v.name == savedMode,
      orElse: () => ThemeMode.system,
    );
    final storedSeed = int.tryParse(
      await db.setting('ui_seed') ?? '',
      radix: 16,
    );
    if (storedSeed != null && storedSeed >= 0 && storedSeed <= 0xffffffff) {
      seed = Color(0xff000000 | (storedSeed & 0xffffff));
    }
    final name = await db.setting('ui_background');
    if (name != null &&
        _managedName.hasMatch(name) &&
        await File(p.join(_backgroundDirectory.path, name)).exists()) {
      _backgroundName = name;
    }
    final visibility = double.tryParse(
      await db.setting('ui_background_visibility') ?? '',
    );
    if (visibility != null && visibility.isFinite) {
      backgroundVisibility = visibility.clamp(.1, .4);
    }
    disc = await db.setting('ui_disc') == 'true';
    discRotation = await db.setting('ui_disc_rotation') == 'true';
    ambient = await db.setting('ui_ambient') == 'true';
    glass = await db.setting('ui_glass') == 'true';
    playerFab = await db.setting('ui_player_fab') == 'true';
    final storedSolid = await db.setting('ui_background_solid');
    solidBackground = storedSolid == null
        ? _backgroundName == null
        : storedSolid == 'true';
    final font = double.tryParse(await db.setting('ui_lyrics_font_size') ?? '');
    if (font != null && font.isFinite) {
      final clamped = font.clamp(16.0, 40.0);
      lyricFontSize = lyricFontSizes.reduce(
        (a, b) => (a - clamped).abs() <= (b - clamped).abs() ? a : b,
      );
    }
    final miniFont = double.tryParse(
      await db.setting('ui_mini_lyrics_font_size') ?? '',
    );
    if (miniFont != null && miniFont.isFinite) {
      final clamped = miniFont.clamp(14.0, 32.0);
      miniLyricFontSize = miniLyricFontSizes.reduce(
        (a, b) => (a - clamped).abs() <= (b - clamped).abs() ? a : b,
      );
    }
  }

  Future<void> update({
    ThemeMode? theme,
    Color? color,
    double? visibility,
    bool? record,
    bool? background,
    bool? frost,
    bool? rotateDisc,
    bool? solid,
    bool? playerFab,
    double? lyricFont,
    double? miniLyricFont,
  }) async {
    if (_closed) return;
    if (visibility != null &&
        (!visibility.isFinite || visibility < .1 || visibility > .4)) {
      throw ArgumentError('背景可见度超出范围');
    }
    if (lyricFont != null &&
        (!lyricFont.isFinite || lyricFont < 16 || lyricFont > 40)) {
      throw ArgumentError('歌词字号超出范围');
    }
    if (miniLyricFont != null &&
        (!miniLyricFont.isFinite || miniLyricFont < 14 || miniLyricFont > 32)) {
      throw ArgumentError('迷你歌词字号超出范围');
    }
    if (color != null) {
      await db.setSetting('ui_seed', color.toARGB32().toRadixString(16));
    }
    if (visibility != null) {
      await db.setSetting('ui_background_visibility', '$visibility');
    }
    if (theme != null) await db.setSetting('ui_theme', theme.name);
    if (record != null) await db.setSetting('ui_disc', '$record');
    if (rotateDisc != null) {
      await db.setSetting('ui_disc_rotation', '$rotateDisc');
    }
    if (background != null) await db.setSetting('ui_ambient', '$background');
    if (frost != null) await db.setSetting('ui_glass', '$frost');
    if (solid != null) await db.setSetting('ui_background_solid', '$solid');
    if (playerFab != null) await db.setSetting('ui_player_fab', '$playerFab');
    if (lyricFont != null) {
      await db.setSetting('ui_lyrics_font_size', '$lyricFont');
    }
    if (miniLyricFont != null) {
      await db.setSetting('ui_mini_lyrics_font_size', '$miniLyricFont');
    }
    seed = color == null
        ? seed
        : Color(0xff000000 | (color.toARGB32() & 0xffffff));
    backgroundVisibility = visibility ?? backgroundVisibility;
    mode = theme ?? mode;
    disc = record ?? disc;
    discRotation = rotateDisc ?? discRotation;
    ambient = background ?? ambient;
    glass = frost ?? glass;
    solidBackground = solid ?? solidBackground;
    this.playerFab = playerFab ?? this.playerFab;
    lyricFontSize = lyricFont ?? lyricFontSize;
    miniLyricFontSize = miniLyricFont ?? miniLyricFontSize;
    if (!_closed) notifyListeners();
  }

  Future<void> pickBackground() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (_closed || picked == null || picked.path == null) return;
    await setBackground(File(picked.path!));
  }

  Future<void> setBackground(File source) => _queueBackground(() async {
    if (await source.length() > 40 * 1024 * 1024) {
      throw const FormatException('请选择小于 40 MB 的图片');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      await source.readAsBytes(),
    );
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) {
        final scale = math.min(1.0, 2048 / math.max(width, height));
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
    if (data == null) throw const FormatException('无法读取图片');
    await _backgroundDirectory.create(recursive: true);
    final name = 'background-${const Uuid().v4()}.png';
    final target = File(p.join(_backgroundDirectory.path, name));
    final temporary = File('${target.path}.tmp');
    try {
      await temporary.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await temporary.rename(target.path);
      await db.setSetting('ui_background', name);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      if (await target.exists()) await target.delete();
      rethrow;
    }
    final oldName = _backgroundName;
    _backgroundName = name;
    if (solidBackground) {
      solidBackground = false;
      await db.setSetting('ui_background_solid', 'false');
    }
    if (!_closed) notifyListeners();
    await _removeBackground(oldName);
  });

  Future<void> clearBackground() => _queueBackground(() async {
    await db.setSetting('ui_background', '');
    final oldName = _backgroundName;
    _backgroundName = null;
    if (!_closed) notifyListeners();
    await _removeBackground(oldName);
  });

  Future<void> _removeBackground(String? name) async {
    if (name == null || !_managedName.hasMatch(name)) return;
    final file = File(p.join(_backgroundDirectory.path, name));
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      /* A stale managed image may be cleaned later. */
    }
  }

  Future<void> _queueBackground(Future<void> Function() work) {
    if (_closed) return Future.value();
    final operation = _backgroundWork.then((_) => work());
    _backgroundWork = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> shutdown() async {
    _closed = true;
    await _backgroundWork;
    dispose();
  }
}
