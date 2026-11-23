import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';

import '../data/app_db.dart';

/// Colour policy for a lyric surface. The desktop overlay currently supports
/// system/fixed; album colour is only used on the in-app full-lyrics page.
enum LyricColorMode { album, system, fixed }

enum LyricPageWeight {
  light('细', FontWeight.w300),
  regular('常规', FontWeight.w400),
  standard('标准', null),
  bold('粗', FontWeight.w700),
  heavy('特粗', FontWeight.w900);

  const LyricPageWeight(this.label, this.fontWeight);

  final String label;
  final FontWeight? fontWeight;
}

enum MiniPlayerBarStyle { automatic, pc, standard }

enum MiuixDockWidth { short, long }

enum ToolbarFoldMode { always, automatic, never }

/// User preference. Whether Miuix can render is decided by UiStyleAvailability.
enum UiStyle { material3, miuix }

class Appearance extends ChangeNotifier {
  Appearance(this.db);
  final AppDb db;
  static const defaultSeed = Color(0xff5094b2);
  ThemeMode mode = ThemeMode.system;
  UiStyle uiStyle = UiStyle.material3;
  Color seed = defaultSeed;
  LyricColorMode lyricPageColorMode = LyricColorMode.album;
  Color lyricPageFixedColor = const Color(0xffd5f1ea);
  LyricColorMode desktopLyricColorMode = LyricColorMode.system;
  Color desktopLyricFixedColor = const Color(0xffd5f1ea);
  bool desktopLyricsEnabled = false;
  double desktopLyricFontSize = 20;
  String? _backgroundName;
  double backgroundVisibility = .24;
  bool _closed = false;
  Future<void> _backgroundWork = Future.value();
  Future<void> _coverFlowWork = Future.value();
  Future<void> _uiStyleWork = Future.value();
  bool _miuixLiquidGlass = false;
  bool get miuixLiquidGlass => _miuixLiquidGlass;
  MiuixDockWidth _miuixDockWidth = MiuixDockWidth.short;
  MiuixDockWidth get miuixDockWidth => _miuixDockWidth;
  static const _toolbarFoldModeKey = 'ui_toolbar_fold_mode';
  ToolbarFoldMode _toolbarFoldMode = ToolbarFoldMode.always;
  ToolbarFoldMode get toolbarFoldMode => _toolbarFoldMode;
  bool albumCoverFlow = false;
  bool playlistCoverFlow = false;
  static final _managedName = RegExp(r'^background-[0-9a-f-]+\.png$');
  Directory get _backgroundDirectory =>
      Directory(p.join(db.root.path, 'appearance'));
  File? get backgroundFile => _backgroundName == null
      ? null
      : File(p.join(_backgroundDirectory.path, _backgroundName!));
  String get seedHex =>
      '#${(seed.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  bool ambient = false, glass = false;
  bool solidBackground = true;
  bool playerFab = true;
  MiniPlayerBarStyle miniPlayerBarStyle = MiniPlayerBarStyle.automatic;
  int _libraryCategoryMask = 15;
  static const libraryCategoryNames = ['歌曲', '专辑', '艺术家', '文件夹'];
  static const libraryCategoryIcons = [
    Icons.music_note_outlined,
    Icons.album_outlined,
    Icons.person_outline,
    Icons.folder_outlined,
  ];
  List<int> get libraryCategories => [
    for (var index = 0; index < 4; index++)
      if ((_libraryCategoryMask & (1 << index)) != 0) index,
  ];
  Future<void> setLibraryCategory(int index, bool enabled) async {
    if (_closed || index < 0 || index >= 4) return;
    final next = enabled
        ? _libraryCategoryMask | (1 << index)
        : _libraryCategoryMask & ~(1 << index);
    if (next == 0 || next == _libraryCategoryMask) return;
    _libraryCategoryMask = next;
    notifyListeners();
    await db.setSetting('ui_library_categories', '$next');
  }

  Future<void> setUiStyle(UiStyle next) => _updateUiStyle(() async {
    if (uiStyle == next) return false;
    await db.setSetting('ui_style', next.name);
    uiStyle = next;
    return true;
  });

  Future<void> setMiuixLiquidGlass(bool enabled) => _updateUiStyle(() async {
    if (_miuixLiquidGlass == enabled) return false;
    await db.setSetting('ui_miuix_liquid_glass', '$enabled');
    _miuixLiquidGlass = enabled;
    return true;
  });

  Future<void> setMiuixDockWidth(MiuixDockWidth width) =>
      _updateUiStyle(() async {
        if (_miuixDockWidth == width) return false;
        await db.setSetting('ui_miuix_dock_width', width.name);
        _miuixDockWidth = width;
        return true;
      });

  Future<void> setToolbarFoldMode(ToolbarFoldMode mode) =>
      _updateUiStyle(() async {
        if (_toolbarFoldMode == mode) return false;
        await db.setSetting(_toolbarFoldModeKey, mode.name);
        _toolbarFoldMode = mode;
        return true;
      });

  /// Serialize appearance writes and notify only after persistence succeeds.
  Future<void> _updateUiStyle(Future<bool> Function() write) {
    if (_closed) return Future.value();
    final operation = _uiStyleWork.then((_) async {
      if (_closed) return;
      final changed = await write();
      if (changed && !_closed) notifyListeners();
    });
    // A failed write must not poison later attempts or the shutdown drain.
    _uiStyleWork = operation.catchError((Object _) {});
    return operation;
  }

  double lyricFontSize = 24;
  LyricPageWeight lyricPageWeight = LyricPageWeight.standard;
  bool lyricSkylineEnabled = false;
  double miniLyricFontSize = 20;
  static const _largeLyricFont = 28.0;
  static const _extraLargeLyricFont = _largeLyricFont * 2;
  static const lyricFontSizes = [
    20.0,
    24.0,
    _largeLyricFont,
    32.0,
    38.0,
    44.0,
    50.0,
    _extraLargeLyricFont,
  ];
  static const miniLyricFontSizes = [16.0, 18.0, 20.0, 22.0, 24.0];
  static String lyricFontLabel(double size) {
    final label = switch (size) {
      20.0 => '小',
      24.0 => '标准',
      _largeLyricFont => '大',
      _extraLargeLyricFont => '超大',
      _ => null,
    };
    final number = size.round();
    return label == null ? '$number' : '$label（$number）';
  }

  static double nearestLyricFontSize(double size, {bool preview = false}) =>
      (preview ? miniLyricFontSizes : lyricFontSizes).reduce(
        (a, b) => (a - size).abs() <= (b - size).abs() ? a : b,
      );

  Future<void> toggleCoverFlow({required bool playlist}) {
    if (_closed) return Future.value();
    final operation = _coverFlowWork.then((_) async {
      final next = !(playlist ? playlistCoverFlow : albumCoverFlow);
      await db.setSetting(
        playlist ? 'ui_playlist_cover_flow' : 'ui_album_cover_flow',
        '$next',
      );
      if (playlist) {
        playlistCoverFlow = next;
      } else {
        albumCoverFlow = next;
      }
      if (!_closed) notifyListeners();
    });
    _coverFlowWork = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> initialize() async {
    albumCoverFlow = await db.setting('ui_album_cover_flow') == 'true';
    playlistCoverFlow = await db.setting('ui_playlist_cover_flow') == 'true';
    final savedStyle = await db.setting('ui_style');
    uiStyle = UiStyle.values.firstWhere(
      (value) => value.name == savedStyle,
      orElse: () => UiStyle.material3,
    );
    _miuixLiquidGlass = await db.setting('ui_miuix_liquid_glass') == 'true';
    final savedDockWidth = await db.setting('ui_miuix_dock_width');
    _miuixDockWidth = MiuixDockWidth.values.firstWhere(
      (width) => width.name == savedDockWidth,
      orElse: () => MiuixDockWidth.short,
    );
    final savedFoldMode = await db.setting(_toolbarFoldModeKey);
    _toolbarFoldMode =
        ToolbarFoldMode.values
            .where((mode) => mode.name == savedFoldMode)
            .firstOrNull ??
        (await db.setting('ui_fold_toolbars_by_default') == 'false'
            ? ToolbarFoldMode.automatic
            : ToolbarFoldMode.always);
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
    ambient = await db.setting('ui_ambient') == 'true';
    glass = await db.setting('ui_glass') == 'true';
    playerFab = await db.setting('ui_player_fab') != 'false';
    final storedBarStyle = await db.setting('ui_mini_player_bar_style');
    miniPlayerBarStyle = MiniPlayerBarStyle.values.firstWhere(
      (style) => style.name == storedBarStyle,
      orElse: () => MiniPlayerBarStyle.automatic,
    );
    final categories = int.tryParse(
      await db.setting('ui_library_categories') ?? '',
    );
    if (categories != null && categories > 0 && categories <= 15) {
      _libraryCategoryMask = categories;
    }
    final storedSolid = await db.setting('ui_background_solid');
    solidBackground = storedSolid == null
        ? _backgroundName == null
        : storedSolid == 'true';
    LyricColorMode readColorMode(String? value, LyricColorMode fallback) =>
        LyricColorMode.values.firstWhere(
          (mode) => mode.name == value,
          orElse: () => fallback,
        );
    Color readColor(String? value, Color fallback) {
      final raw = int.tryParse(value ?? '', radix: 16);
      return raw == null || raw < 0 || raw > 0xffffff
          ? fallback
          : Color(0xff000000 | raw);
    }

    lyricPageColorMode = readColorMode(
      await db.setting('ui_lyric_page_color_mode'),
      LyricColorMode.album,
    );
    lyricPageFixedColor = readColor(
      await db.setting('ui_lyric_page_fixed_color'),
      lyricPageFixedColor,
    );
    desktopLyricColorMode = readColorMode(
      await db.setting('ui_desktop_lyric_color_mode'),
      LyricColorMode.system,
    );
    if (desktopLyricColorMode == LyricColorMode.album) {
      desktopLyricColorMode = LyricColorMode.system;
    }
    desktopLyricFixedColor = readColor(
      await db.setting('ui_desktop_lyric_fixed_color'),
      desktopLyricFixedColor,
    );
    desktopLyricsEnabled =
        await db.setting('ui_desktop_lyrics_enabled') == 'true';
    final desktopFont = double.tryParse(
      await db.setting('ui_desktop_lyrics_font_size') ?? '',
    );
    if (desktopFont != null && desktopFont.isFinite) {
      desktopLyricFontSize = desktopFont.clamp(12.0, 40.0);
    }
    lyricSkylineEnabled =
        await db.setting('ui_lyric_skyline_enabled') == 'true';
    final font = double.tryParse(await db.setting('ui_lyrics_font_size') ?? '');
    if (font != null && font.isFinite) {
      lyricFontSize = nearestLyricFontSize(font);
    }
    final savedLyricWeight = await db.setting('ui_lyric_page_weight');
    lyricPageWeight = LyricPageWeight.values.firstWhere(
      (weight) => weight.name == savedLyricWeight,
      orElse: () => LyricPageWeight.standard,
    );
    final miniFont = double.tryParse(
      await db.setting('ui_mini_lyrics_font_size') ?? '',
    );
    if (miniFont != null && miniFont.isFinite) {
      miniLyricFontSize = nearestLyricFontSize(miniFont, preview: true);
    }
  }

  Future<void> update({
    ThemeMode? theme,
    Color? color,
    double? visibility,
    bool? background,
    bool? frost,
    bool? solid,
    bool? playerFab,
    MiniPlayerBarStyle? miniPlayerBarStyle,
    double? lyricFont,
    LyricPageWeight? lyricPageWeight,
    bool? lyricSkyline,
    double? miniLyricFont,
    LyricColorMode? lyricPageColorMode,
    Color? lyricPageFixedColor,
    LyricColorMode? desktopLyricColorMode,
    Color? desktopLyricFixedColor,
    bool? desktopLyricsEnabled,
    double? desktopLyricFontSize,
  }) async {
    if (_closed) return;
    if (desktopLyricFontSize != null &&
        (!desktopLyricFontSize.isFinite ||
            desktopLyricFontSize < 12 ||
            desktopLyricFontSize > 40)) {
      throw ArgumentError('桌面歌词字号超出范围');
    }
    if (visibility != null &&
        (!visibility.isFinite || visibility < .1 || visibility > .4)) {
      throw ArgumentError('背景可见度超出范围');
    }
    if (lyricFont != null &&
        (!lyricFont.isFinite ||
            lyricFont < 16 ||
            lyricFont > _extraLargeLyricFont)) {
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
    if (background != null) await db.setSetting('ui_ambient', '$background');
    if (frost != null) await db.setSetting('ui_glass', '$frost');
    if (solid != null) await db.setSetting('ui_background_solid', '$solid');
    if (playerFab != null) await db.setSetting('ui_player_fab', '$playerFab');
    if (miniPlayerBarStyle != null) {
      await db.setSetting('ui_mini_player_bar_style', miniPlayerBarStyle.name);
    }
    if (lyricFont != null) {
      await db.setSetting('ui_lyrics_font_size', '$lyricFont');
    }
    if (lyricPageWeight != null) {
      await db.setSetting('ui_lyric_page_weight', lyricPageWeight.name);
    }
    if (lyricSkyline != null) {
      await db.setSetting('ui_lyric_skyline_enabled', '$lyricSkyline');
    }
    if (miniLyricFont != null) {
      await db.setSetting('ui_mini_lyrics_font_size', '$miniLyricFont');
    }
    if (lyricPageColorMode != null) {
      await db.setSetting('ui_lyric_page_color_mode', lyricPageColorMode.name);
    }
    if (lyricPageFixedColor != null) {
      await db.setSetting(
        'ui_lyric_page_fixed_color',
        (lyricPageFixedColor.toARGB32() & 0xffffff).toRadixString(16),
      );
    }
    if (desktopLyricColorMode != null) {
      if (desktopLyricColorMode == LyricColorMode.album) {
        throw ArgumentError('桌面歌词不支持专辑取色');
      }
      await db.setSetting(
        'ui_desktop_lyric_color_mode',
        desktopLyricColorMode.name,
      );
    }
    if (desktopLyricFixedColor != null) {
      await db.setSetting(
        'ui_desktop_lyric_fixed_color',
        (desktopLyricFixedColor.toARGB32() & 0xffffff).toRadixString(16),
      );
    }
    if (desktopLyricsEnabled != null) {
      await db.setSetting('ui_desktop_lyrics_enabled', '$desktopLyricsEnabled');
    }
    seed = color == null
        ? seed
        : Color(0xff000000 | (color.toARGB32() & 0xffffff));
    backgroundVisibility = visibility ?? backgroundVisibility;
    mode = theme ?? mode;
    ambient = background ?? ambient;
    glass = frost ?? glass;
    solidBackground = solid ?? solidBackground;
    this.playerFab = playerFab ?? this.playerFab;
    this.miniPlayerBarStyle = miniPlayerBarStyle ?? this.miniPlayerBarStyle;
    lyricFontSize = lyricFont ?? lyricFontSize;
    this.lyricPageWeight = lyricPageWeight ?? this.lyricPageWeight;
    lyricSkylineEnabled = lyricSkyline ?? lyricSkylineEnabled;
    miniLyricFontSize = miniLyricFont ?? miniLyricFontSize;
    this.lyricPageColorMode = lyricPageColorMode ?? this.lyricPageColorMode;
    this.lyricPageFixedColor = lyricPageFixedColor ?? this.lyricPageFixedColor;
    this.desktopLyricColorMode =
        desktopLyricColorMode ?? this.desktopLyricColorMode;
    this.desktopLyricFixedColor =
        desktopLyricFixedColor ?? this.desktopLyricFixedColor;
    this.desktopLyricsEnabled =
        desktopLyricsEnabled ?? this.desktopLyricsEnabled;
    if (desktopLyricFontSize != null) {
      await db.setSetting(
        'ui_desktop_lyrics_font_size',
        '$desktopLyricFontSize',
      );
      this.desktopLyricFontSize = desktopLyricFontSize;
    }
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
    await _coverFlowWork;
    await _uiStyleWork;
    dispose();
  }
}
