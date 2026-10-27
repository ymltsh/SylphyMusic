import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

/// A free-form player scene. All frames are normalised to the whole canvas;
/// there are no cover / lyric / control regions any more.
enum PlayerPart {
  cover,
  title,
  artist,
  lyrics,
  progress,
  controls,
  queue,
  favorite,
  decoration,
}

enum PlayerBackground { album, gradient, solid }

const partLabels = {
  PlayerPart.cover: '专辑封面',
  PlayerPart.title: '歌曲标题',
  PlayerPart.artist: '歌手 / 专辑',
  PlayerPart.lyrics: '歌词预览',
  PlayerPart.progress: '进度条',
  PlayerPart.controls: '播放控制',
  PlayerPart.queue: '播放队列',
  PlayerPart.favorite: '收藏',
  PlayerPart.decoration: '装饰色块',
};

class PlayerElement {
  const PlayerElement({
    required this.id,
    required this.type,
    required this.frame,
    this.wideFrame,
    this.locked = false,
    this.hidden = false,
    this.fontSize = 22,
    this.opacity = 1,
    this.radius = 24,
    this.playWidth = 64,
    this.playHeight = 64,
    this.controlSpacing = 12,
    this.align = 'center',
    this.color,
  });
  final String id;
  final PlayerPart type;

  /// Position and size on the portrait canvas. Cut-out covers are rendered as
  /// a centred square inside this frame so the visible disc can never disagree
  /// with the selection rectangle.
  final Rect frame;
  final Rect? wideFrame;
  final bool locked, hidden;
  final double fontSize, opacity, radius, playWidth, playHeight, controlSpacing;
  final String align;
  final int? color;

  PlayerElement copyWith({
    Rect? frame,
    Rect? wideFrame,
    bool? locked,
    bool? hidden,
    double? fontSize,
    double? opacity,
    double? radius,
    double? playWidth,
    double? playHeight,
    double? controlSpacing,
    String? align,
    int? color,
    bool clearColor = false,
  }) => PlayerElement(
    id: id,
    type: type,
    frame: frame ?? this.frame,
    wideFrame: wideFrame ?? this.wideFrame,
    locked: locked ?? this.locked,
    hidden: hidden ?? this.hidden,
    fontSize: fontSize ?? this.fontSize,
    opacity: opacity ?? this.opacity,
    radius: radius ?? this.radius,
    playWidth: playWidth ?? this.playWidth,
    playHeight: playHeight ?? this.playHeight,
    controlSpacing: controlSpacing ?? this.controlSpacing,
    align: align ?? this.align,
    color: clearColor ? null : color ?? this.color,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'frame': _frameJson(frame),
    if (wideFrame != null) 'wideFrame': _frameJson(wideFrame!),
    'props': {
      'locked': locked,
      'hidden': hidden,
      'fontSize': fontSize,
      'opacity': opacity,
      'radius': radius,
      'playWidth': playWidth,
      'playHeight': playHeight,
      'controlSpacing': controlSpacing,
      'align': align,
      if (color != null) 'color': color,
    },
  };

  static PlayerElement fromJson(Object? value) {
    final json = _map(value);
    final props = _map(json['props'] ?? const <String, dynamic>{});
    final align = props['align'] ?? 'center';
    if (!['left', 'center', 'right'].contains(align)) {
      throw const FormatException('不支持的对齐方式');
    }
    final color = props['color'];
    if (color != null && (color is! int || color < 0 || color > 0xffffffff)) {
      throw const FormatException('无效颜色');
    }
    bool flag(String key) {
      final v = props[key] ?? false;
      if (v is! bool) throw const FormatException('无效属性');
      return v;
    }

    return PlayerElement(
      id: _string(json['id'], 80),
      type: _enum(PlayerPart.values, json['type']),
      frame: _readFrame(json['frame']),
      wideFrame: json['wideFrame'] == null
          ? null
          : _readFrame(json['wideFrame']),
      locked: flag('locked'),
      hidden: flag('hidden'),
      playWidth: _number(props['playWidth'] ?? 64, 56, 96),
      playHeight: _number(props['playHeight'] ?? 64, 48, 96),
      controlSpacing: _number(props['controlSpacing'] ?? 12, 0, 32),
      fontSize: _number(props['fontSize'] ?? 22, 12, 40),
      opacity: _number(props['opacity'] ?? 1, .1, 1),
      radius: _number(props['radius'] ?? 24, 0, 64),
      align: align as String,
      color: color as int?,
    );
  }
}

class PlayerLayout {
  PlayerLayout({
    required this.id,
    required this.name,
    required List<PlayerElement> elements,
    this.background = PlayerBackground.album,
    this.backgroundOpacity = .65,
  }) : elements = List.unmodifiable(elements);
  final String id, name;
  final List<PlayerElement> elements;
  final double backgroundOpacity;
  final PlayerBackground background;

  /// v2 is the free-form canvas format. v1 files are migrated on read.
  static const version = 2;
  static const legacyVersion = 1;

  PlayerLayout copyWith({
    String? id,
    String? name,
    List<PlayerElement>? elements,
    PlayerBackground? background,
    double? backgroundOpacity,
  }) => PlayerLayout(
    id: id ?? this.id,
    name: name ?? this.name,
    elements: elements ?? this.elements,
    background: background ?? this.background,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
  );

  Map<String, Object?> toJson() => {
    'version': version,
    'id': id,
    'name': name,
    'background': background.name,
    'backgroundOpacity': backgroundOpacity,
    'elements': elements.map((e) => e.toJson()).toList(),
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static PlayerLayout decode(String source) {
    if (utf8.encode(source).length > 128 * 1024) {
      throw const FormatException('布局文件过大');
    }
    return fromJson(jsonDecode(source));
  }

  static PlayerLayout fromJson(Object? value) {
    final json = _map(value);
    return switch (json['version']) {
      legacyVersion => _migrateLegacy(json),
      version => _fromV2(json),
      _ => throw const FormatException('不支持的布局版本'),
    };
  }

  static PlayerLayout _fromV2(Map<String, dynamic> json) {
    final raw = json['elements'];
    if (raw is! List || raw.length > 32) {
      throw const FormatException('最多支持 32 个组件');
    }
    final elements = raw.map(PlayerElement.fromJson).toList();
    if (elements.map((e) => e.id).toSet().length != elements.length) {
      throw const FormatException('组件 ID 重复');
    }
    if (elements.any((e) => e.type == PlayerPart.controls)) {
      elements.removeWhere(
        (e) => e.id == 'queue' && e.type == PlayerPart.queue,
      );
    }
    return PlayerLayout(
      id: _string(json['id'], 80),
      name: _string(json['name'], 60),
      elements: elements,
      background: _enum(PlayerBackground.values, json['background'] ?? 'album'),
      backgroundOpacity: _number(json['backgroundOpacity'] ?? .65, .1, 1),
    );
  }

  /// The v1 format stored every widget inside one of three vertical regions and
  /// used a second region set for wide screens. This recovers the exact
  /// on-screen rectangle at the reference sizes before normalising it to the
  /// free canvas. The old per-widget circle / rotate flags are intentionally
  /// dropped: record shape and rotation are now one global playback preference.
  static PlayerLayout _migrateLegacy(Map<String, dynamic> json) {
    final top = _number(json['topFraction'] ?? .48, .15, .65);
    final middle = _number(json['middleFraction'] ?? .2, .1, .6);
    if (top + middle > .8) {
      throw const FormatException('旧布局区域比例无效');
    }
    final raw = json['elements'];
    if (raw is! List || raw.length > 32) {
      throw const FormatException('最多支持 32 个组件');
    }
    final legacy = raw.map(_LegacyElement.fromJson).toList();
    if (legacy.map((e) => e.id).toSet().length != legacy.length) {
      throw const FormatException('组件 ID 重复');
    }
    if (legacy.any((e) => e.type == PlayerPart.controls)) {
      legacy.removeWhere(
        (e) =>
            e.id == 'queue' &&
            e.type == PlayerPart.queue &&
            e.region == _LegacyRegion.bottom,
      );
    }
    final portrait = const Size(360, 640);
    final wide = const Size(1200, 800);
    final elements = <PlayerElement>[
      for (final e in legacy)
        PlayerElement(
          id: e.id,
          type: e.type,
          frame: _normalise(
            _legacyBounds(e, portrait, top, middle, legacy),
            portrait,
          ),
          wideFrame: _normalise(
            _legacyBounds(e, wide, top, middle, legacy),
            wide,
          ),
          locked: e.locked,
          hidden: e.hidden,
          fontSize: e.fontSize,
          opacity: e.opacity,
          radius: e.radius,
          playWidth: e.playWidth,
          playHeight: e.playHeight,
          controlSpacing: e.controlSpacing,
          align: e.align,
          color: e.color,
        ),
    ];
    return PlayerLayout(
      id: _string(json['id'], 80),
      name: _string(json['name'], 60),
      elements: elements,
      background: _enum(PlayerBackground.values, json['background'] ?? 'album'),
      backgroundOpacity: _number(json['backgroundOpacity'] ?? .65, .1, 1),
    );
  }

  /// The concrete frame for the current width. Wide screens may use a separate
  /// composition, but both formats are free-form full-canvas rectangles.
  Rect frameFor(PlayerElement e, Size size) =>
      size.width > 850 ? e.wideFrame ?? e.frame : e.frame;

  Rect rawBounds(PlayerElement e, Size size) {
    final frame = frameFor(e, size);
    return Rect.fromLTWH(
      frame.left * size.width,
      frame.top * size.height,
      frame.width * size.width,
      frame.height * size.height,
    );
  }

  Rect bounds(PlayerElement e, Size size) {
    final raw = rawBounds(e, size);
    if (e.type == PlayerPart.cover) {
      // A record is always circular. Its displayed square is the source of
      // truth for selection, resizing and hit testing.
      var side = math.min(raw.width, raw.height);
      side = math.max(48.0, side).clamp(0.0, math.min(size.width, size.height));
      final left = (raw.center.dx - side / 2).clamp(0.0, size.width - side);
      final top = (raw.center.dy - side / 2).clamp(0.0, size.height - side);
      return Rect.fromLTWH(left, top, side, side);
    }
    final minimum = switch (e.type) {
      PlayerPart.controls => Size(300, math.max(72, e.playHeight + 8)),
      PlayerPart.progress => const Size(260, 64),
      PlayerPart.lyrics => const Size(120, 78),
      PlayerPart.queue || PlayerPart.favorite => const Size(48, 48),
      _ => const Size(24, 24),
    };
    final width = math.max(minimum.width, raw.width).clamp(0.0, size.width);
    final height = math.max(minimum.height, raw.height).clamp(0.0, size.height);
    final minTop = e.type == PlayerPart.progress
        ? math.min(56.0, math.max(0.0, size.height - height))
        : 0.0;
    final rect = Rect.fromLTWH(
      raw.left.clamp(0.0, math.max(0.0, size.width - width)),
      raw.top.clamp(minTop, math.max(minTop, size.height - height)),
      width,
      height,
    );
    if (e.type == PlayerPart.lyrics) {
      final actions = actionBounds(size);
      if (rect.overlaps(actions) && rect.top < actions.top) {
        return Rect.fromLTWH(
          rect.left,
          rect.top,
          rect.width,
          math.max(0, actions.top - 8 - rect.top),
        );
      }
    }
    return rect;
  }

  /// The permanent action strip follows the first visible progress component.
  /// A fallback keeps editing reachable in layouts without a progress bar.
  Rect actionBounds(Size size) {
    final progress = elements
        .where((e) => e.type == PlayerPart.progress && !e.hidden)
        .firstOrNull;
    final anchor = progress == null
        ? Rect.fromLTWH(16, size.height - 16, math.max(0, size.width - 32), 0)
        : bounds(progress, size);
    final width = math.min(480.0, anchor.width);
    final height = math.min(48.0, size.height);
    return Rect.fromLTWH(
      (anchor.center.dx - width / 2).clamp(
        0.0,
        math.max(0, size.width - width),
      ),
      (anchor.top - height - 8).clamp(0.0, math.max(0, size.height - height)),
      width,
      height,
    );
  }
}

PlayerLayout playerTemplate({bool lyrics = false}) => PlayerLayout(
  id: lyrics ? 'builtin-lyrics' : 'builtin-cover',
  name: lyrics ? '歌词优先' : '沉浸封面',
  elements: [
    PlayerElement(
      id: 'cover',
      type: PlayerPart.cover,
      radius: 28,
      frame: lyrics
          ? const Rect.fromLTWH(.25, .035, .30, .22)
          : const Rect.fromLTWH(.11, .04, .78, .36),
      wideFrame: lyrics
          ? const Rect.fromLTWH(.06, .10, .20, .36)
          : const Rect.fromLTWH(.06, .10, .30, .46),
    ),
    PlayerElement(
      id: 'title',
      type: PlayerPart.title,
      fontSize: 22,
      frame: lyrics
          ? const Rect.fromLTWH(.58, .055, .34, .065)
          : const Rect.fromLTWH(.08, .455, .84, .065),
      wideFrame: lyrics
          ? const Rect.fromLTWH(.30, .14, .24, .07)
          : const Rect.fromLTWH(.06, .61, .30, .07),
    ),
    PlayerElement(
      id: 'artist',
      type: PlayerPart.artist,
      fontSize: 14,
      frame: lyrics
          ? const Rect.fromLTWH(.58, .13, .34, .045)
          : const Rect.fromLTWH(.08, .525, .84, .04),
      wideFrame: lyrics
          ? const Rect.fromLTWH(.30, .22, .24, .045)
          : const Rect.fromLTWH(.06, .69, .30, .045),
    ),
    PlayerElement(
      id: 'lyrics',
      type: PlayerPart.lyrics,
      frame: lyrics
          ? const Rect.fromLTWH(.06, .235, .88, .45)
          : const Rect.fromLTWH(.08, .575, .84, .12),
      wideFrame: lyrics
          ? const Rect.fromLTWH(.55, .14, .40, .56)
          : const Rect.fromLTWH(.55, .16, .40, .56),
    ),
    PlayerElement(
      id: 'progress',
      type: PlayerPart.progress,
      frame: lyrics
          ? const Rect.fromLTWH(.08, .78, .84, .08)
          : const Rect.fromLTWH(.08, .79, .84, .08),
      wideFrame: lyrics
          ? const Rect.fromLTWH(.08, .80, .42, .08)
          : const Rect.fromLTWH(.06, .82, .42, .08),
    ),
    PlayerElement(
      id: 'controls',
      type: PlayerPart.controls,
      frame: lyrics
          ? const Rect.fromLTWH(.06, .88, .88, .11)
          : const Rect.fromLTWH(.06, .885, .88, .10),
      wideFrame: lyrics
          ? const Rect.fromLTWH(.08, .89, .42, .10)
          : const Rect.fromLTWH(.06, .90, .42, .09),
    ),
  ],
);

Rect _normalise(Rect pixels, Size size) => Rect.fromLTWH(
  (pixels.left / size.width).clamp(0.0, 1.0),
  (pixels.top / size.height).clamp(0.0, 1.0),
  (pixels.width / size.width).clamp(0.0, 1.0),
  (pixels.height / size.height).clamp(0.0, 1.0),
);

Map<String, dynamic> _map(Object? value) {
  if (value is! Map<String, dynamic>) throw const FormatException('无效布局对象');
  return value;
}

String _string(Object? v, int max) {
  if (v is! String || v.trim().isEmpty || v.length > max) {
    throw const FormatException('无效名称');
  }
  return v.trim();
}

double _number(Object? v, double min, double max) {
  if (v is! num || !v.isFinite || v < min || v > max) {
    throw const FormatException('布局数值超出范围');
  }
  return v.toDouble();
}

T _enum<T extends Enum>(List<T> values, Object? v) => values.firstWhere(
  (e) => e.name == v,
  orElse: () => throw const FormatException('不支持的组件或样式'),
);

Map<String, Object?> _frameJson(Rect rect) => {
  'x': rect.left,
  'y': rect.top,
  'width': rect.width,
  'height': rect.height,
};

Rect _readFrame(Object? value) {
  final f = _map(value);
  final x = _number(f['x'], 0, 1), y = _number(f['y'], 0, 1);
  final w = _number(f['width'], .01, 1), h = _number(f['height'], .01, 1);
  if (x + w > 1.000001 || y + h > 1.000001) {
    throw const FormatException('组件超出画布');
  }
  return Rect.fromLTWH(x, y, w, h);
}

// ---------------------------------------------------------------------------
// v1 migration helpers

enum _LegacyRegion { top, middle, bottom }

class _LegacyElement {
  const _LegacyElement({
    required this.id,
    required this.type,
    required this.region,
    required this.frame,
    required this.wideFrame,
    required this.wideRegion,
    required this.locked,
    required this.hidden,
    required this.fontSize,
    required this.opacity,
    required this.radius,
    required this.playWidth,
    required this.playHeight,
    required this.controlSpacing,
    required this.align,
    required this.color,
  });
  final String id;
  final PlayerPart type;
  final _LegacyRegion region;
  final Rect frame;
  final Rect? wideFrame;
  final _LegacyRegion? wideRegion;
  final bool locked, hidden;
  final double fontSize, opacity, radius, playWidth, playHeight, controlSpacing;
  final String align;
  final int? color;

  static _LegacyElement fromJson(Object? value) {
    final json = _map(value);
    final props = _map(json['props'] ?? const <String, dynamic>{});
    final align = props['align'] ?? 'center';
    if (!['left', 'center', 'right'].contains(align)) {
      throw const FormatException('不支持的对齐方式');
    }
    final color = props['color'];
    if (color != null && (color is! int || color < 0 || color > 0xffffffff)) {
      throw const FormatException('无效颜色');
    }
    bool flag(String key) {
      final v = props[key] ?? false;
      if (v is! bool) throw const FormatException('无效属性');
      return v;
    }

    return _LegacyElement(
      id: _string(json['id'], 80),
      type: _enum(PlayerPart.values, json['type']),
      region: _legacyEnum(_LegacyRegion.values, json['region']),
      frame: _readFrame(json['frame']),
      wideFrame: json['wideFrame'] == null
          ? null
          : _readFrame(json['wideFrame']),
      wideRegion: json['wideRegion'] == null
          ? null
          : _legacyEnum(_LegacyRegion.values, json['wideRegion']),
      locked: flag('locked'),
      hidden: flag('hidden'),
      fontSize: _number(props['fontSize'] ?? 22, 12, 40),
      opacity: _number(props['opacity'] ?? 1, .1, 1),
      radius: _number(props['radius'] ?? 24, 0, 64),
      playWidth: _number(props['playWidth'] ?? 64, 56, 96),
      playHeight: _number(props['playHeight'] ?? 64, 48, 96),
      controlSpacing: _number(props['controlSpacing'] ?? 12, 0, 32),
      align: align as String,
      color: color as int?,
    );
  }
}

T _legacyEnum<T extends Enum>(List<T> values, Object? v) => values.firstWhere(
  (e) => e.name == v,
  orElse: () => throw const FormatException('不支持的组件或样式'),
);

Rect _legacyBounds(
  _LegacyElement e,
  Size size,
  double topFraction,
  double middleFraction,
  List<_LegacyElement> elements,
) {
  final regions = _legacyRegions(size, topFraction, middleFraction, elements);
  final region = _legacyRegionFor(e, size);
  final area = regions[region]!;
  final frame = _legacyFrameFor(e, size, regions, area);
  final minimum = switch (e.type) {
    PlayerPart.controls => Size(300, math.max(72, e.playHeight + 8)),
    PlayerPart.progress => const Size(260, 70),
    PlayerPart.queue || PlayerPart.favorite => const Size(48, 48),
    PlayerPart.lyrics => const Size(120, 140),
    PlayerPart.cover => const Size(48, 48),
    _ => const Size(24, 24),
  };
  final width = math
      .max(minimum.width, frame.width * area.width)
      .clamp(0.0, area.width);
  final height = math
      .max(minimum.height, frame.height * area.height)
      .clamp(0.0, area.height);
  return Rect.fromLTWH(
    area.left + (frame.left * area.width).clamp(0.0, area.width - width),
    area.top + (frame.top * area.height).clamp(0.0, area.height - height),
    width,
    height,
  );
}

Map<_LegacyRegion, Rect> _legacyRegions(
  Size size,
  double topFraction,
  double middleFraction,
  List<_LegacyElement> elements,
) {
  final controlsHeight = elements
      .where((e) => e.type == PlayerPart.controls && !e.hidden)
      .fold(0.0, (height, e) => math.max(height, e.playHeight + 96));
  if (size.width > 850) {
    final width = math.min(size.width, 1200.0);
    final inset = (size.width - width) / 2;
    final left = width * .46;
    final controls = math.max(176.0, controlsHeight);
    return {
      _LegacyRegion.top: Rect.fromLTWH(inset, 0, left, size.height - controls),
      _LegacyRegion.middle: Rect.fromLTWH(
        inset + left + 24,
        0,
        width - left - 24,
        size.height,
      ),
      _LegacyRegion.bottom: Rect.fromLTWH(
        inset,
        size.height - controls,
        left,
        controls,
      ),
    };
  }
  final bottomHeight = math
      .max(size.height * (1 - topFraction - middleFraction), controlsHeight)
      .clamp(0.0, size.height * .55);
  final topHeight =
      (size.height - bottomHeight) *
      topFraction /
      (topFraction + middleFraction);
  return {
    _LegacyRegion.top: Rect.fromLTWH(0, 0, size.width, topHeight),
    _LegacyRegion.middle: Rect.fromLTWH(
      0,
      topHeight,
      size.width,
      size.height - bottomHeight - topHeight,
    ),
    _LegacyRegion.bottom: Rect.fromLTWH(
      0,
      size.height - bottomHeight,
      size.width,
      bottomHeight,
    ),
  };
}

_LegacyRegion _legacyRegionFor(_LegacyElement e, Size size) {
  if (size.width <= 850) return e.region;
  return e.wideRegion ??
      (e.region != _LegacyRegion.bottom &&
              (e.type == PlayerPart.title || e.type == PlayerPart.artist)
          ? _LegacyRegion.top
          : e.region);
}

Rect _legacyFrameFor(
  _LegacyElement e,
  Size size,
  Map<_LegacyRegion, Rect> regions,
  Rect area,
) {
  if (size.width <= 850) return e.frame;
  if (e.wideFrame != null) return e.wideFrame!;
  final side = math.min(area.width * .76, area.height - 128);
  final start = (area.height - side - 104) / 2;
  return switch (e.type) {
    PlayerPart.cover when e.region == _LegacyRegion.top => Rect.fromLTWH(
      .12,
      start / area.height,
      .76,
      side / area.height,
    ),
    PlayerPart.title when e.region != _LegacyRegion.bottom => Rect.fromLTWH(
      .06,
      (start + side + 24) / area.height,
      .88,
      48 / area.height,
    ),
    PlayerPart.artist when e.region != _LegacyRegion.bottom => Rect.fromLTWH(
      .06,
      (start + side + 80) / area.height,
      .88,
      24 / area.height,
    ),
    PlayerPart.lyrics when e.region == _LegacyRegion.middle =>
      const Rect.fromLTWH(.02, .02, .96, .96),
    PlayerPart.progress when e.region == _LegacyRegion.bottom =>
      const Rect.fromLTWH(.08, .02, .84, .4),
    PlayerPart.controls when e.region == _LegacyRegion.bottom =>
      const Rect.fromLTWH(.08, .5, .84, .44),
    _ => e.frame,
  };
}
