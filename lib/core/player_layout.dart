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
  quickActions,
  controls,
  queue,
  favorite,
  decoration,
}

enum PlayerProgressStyle { classic, wave, segmented }

enum PlayerBackground { album, gradient, solid }

/// The shape and rendering of an individual cover element, not a global switch.
enum PlayerCoverStyle { rounded, vinyl, immersive }

/// The edge where an immersive cover fades into the canvas behind it.
enum CoverFadeDirection { right, left, bottom, top }

const partLabels = {
  PlayerPart.cover: '专辑封面',
  PlayerPart.title: '歌曲标题',
  PlayerPart.artist: '歌手 / 专辑',
  PlayerPart.lyrics: '歌词预览',
  PlayerPart.progress: '进度条',
  PlayerPart.quickActions: '快捷操作区',
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
    this.quickActionSpacing,
    this.progressStyle = PlayerProgressStyle.classic,
    this.progressThickness = 2,
    this.waveAmplitude = 4,
    this.waveLength = 24,
    this.lyricLineHeight = 1.5,
    this.align = 'center',
    this.color,
    this.lyricFollowSystemColor = true,
    this.coverStyle = PlayerCoverStyle.vinyl,
    this.coverRotation = true,
    this.coverFadeStart = .5,
    this.coverFadeDirection = CoverFadeDirection.bottom,
  });
  final String id;
  final PlayerPart type;

  /// Normalized free-canvas rectangle. Rounded and vinyl covers are square;
  /// immersive covers use the entire rectangle without aspect-ratio clamping.
  final Rect frame;
  final Rect? wideFrame;
  final bool locked, hidden;
  final double fontSize, opacity, radius, playWidth, playHeight, controlSpacing;
  final double? quickActionSpacing;
  final PlayerProgressStyle progressStyle;
  final double progressThickness, waveAmplitude, waveLength;
  final double lyricLineHeight;
  final String align;
  final int? color;

  /// Only the lyrics preview uses this flag. It selects system black/white
  /// instead of the usual theme accent when no explicit color is set.
  final bool lyricFollowSystemColor;
  final PlayerCoverStyle coverStyle;
  final bool coverRotation;
  final double coverFadeStart;
  final CoverFadeDirection coverFadeDirection;

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
    double? quickActionSpacing,
    bool clearQuickActionSpacing = false,
    PlayerProgressStyle? progressStyle,
    double? progressThickness,
    double? waveAmplitude,
    double? waveLength,
    double? lyricLineHeight,
    String? align,
    int? color,
    bool clearColor = false,
    bool? lyricFollowSystemColor,
    PlayerCoverStyle? coverStyle,
    bool? coverRotation,
    double? coverFadeStart,
    CoverFadeDirection? coverFadeDirection,
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
    quickActionSpacing: clearQuickActionSpacing
        ? null
        : quickActionSpacing ?? this.quickActionSpacing,
    progressStyle: progressStyle ?? this.progressStyle,
    progressThickness: progressThickness ?? this.progressThickness,
    waveAmplitude: waveAmplitude ?? this.waveAmplitude,
    waveLength: waveLength ?? this.waveLength,
    lyricLineHeight: lyricLineHeight ?? this.lyricLineHeight,
    align: align ?? this.align,
    color: clearColor ? null : color ?? this.color,
    lyricFollowSystemColor:
        lyricFollowSystemColor ?? this.lyricFollowSystemColor,
    coverStyle: coverStyle ?? this.coverStyle,
    coverRotation: coverRotation ?? this.coverRotation,
    coverFadeStart: coverFadeStart ?? this.coverFadeStart,
    coverFadeDirection: coverFadeDirection ?? this.coverFadeDirection,
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
      if (type == PlayerPart.quickActions && quickActionSpacing != null)
        'quickActionSpacing': quickActionSpacing,
      if (type == PlayerPart.progress) ...{
        'progressStyle': progressStyle.name,
        'progressThickness': progressThickness,
        'waveAmplitude': waveAmplitude,
        'waveLength': waveLength,
      },
      'lyricLineHeight': lyricLineHeight,
      'align': align,
      if (color != null) 'color': color,
      if (type == PlayerPart.lyrics)
        'lyricFollowSystemColor': lyricFollowSystemColor,
      if (type == PlayerPart.cover) 'coverStyle': coverStyle.name,
      if (type == PlayerPart.cover) 'coverRotation': coverRotation,
      if (type == PlayerPart.cover) 'coverFadeStart': coverFadeStart,
      if (type == PlayerPart.cover)
        'coverFadeDirection': coverFadeDirection.name,
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
    bool flag(String key, {bool defaultValue = false}) {
      final v = props[key] ?? defaultValue;
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
      quickActionSpacing: props['quickActionSpacing'] == null
          ? null
          : _number(props['quickActionSpacing'], 0, 64),
      progressStyle: _enum(
        PlayerProgressStyle.values,
        props['progressStyle'] ?? 'classic',
      ),
      progressThickness: _number(props['progressThickness'] ?? 2, 1, 8),
      waveAmplitude: _number(props['waveAmplitude'] ?? 4, 0, 8),
      waveLength: _number(props['waveLength'] ?? 24, 12, 64),
      lyricLineHeight: _number(props['lyricLineHeight'] ?? 1.5, 1, 2.5),
      fontSize: _number(props['fontSize'] ?? 22, 12, 40),
      opacity: _number(props['opacity'] ?? 1, .1, 1),
      radius: _number(props['radius'] ?? 24, 0, 64),
      align: align as String,
      color: color as int?,
      lyricFollowSystemColor: flag(
        'lyricFollowSystemColor',
        defaultValue: true,
      ),
      // New v4 layouts do not read legacy circle/rotate switches.
      coverStyle: _enum(
        PlayerCoverStyle.values,
        props['coverStyle'] ?? 'vinyl',
      ),
      coverRotation: flag('coverRotation', defaultValue: true),
      coverFadeStart: _number(props['coverFadeStart'] ?? .5, 0, .95),
      coverFadeDirection: _enum(
        CoverFadeDirection.values,
        props['coverFadeDirection'] ?? 'bottom',
      ),
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

  /// Breaking layout format: former templates must be recreated by the user.
  static const version = 4;
  static const maxElements = 33; // Former 32 plus the quick-action row.

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
    if (json['version'] != version) {
      throw const FormatException('只支持新版 v4 播放页布局');
    }
    final raw = json['elements'];
    if (raw is! List || raw.length > maxElements) {
      throw const FormatException('最多支持 33 个组件');
    }
    final elements = raw.map(PlayerElement.fromJson).toList();
    if (elements.map((e) => e.id).toSet().length != elements.length) {
      throw const FormatException('组件 ID 重复');
    }
    if (elements.where((e) => e.type == PlayerPart.quickActions).length > 1) {
      throw const FormatException('快捷操作区只能有一个');
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
    if (e.type == PlayerPart.cover &&
        e.coverStyle != PlayerCoverStyle.immersive) {
      // Vinyl and rounded covers keep their square selection/resize bounds.
      var side = math.min(raw.width, raw.height);
      side = math.max(48.0, side).clamp(0.0, math.min(size.width, size.height));
      final left = (raw.center.dx - side / 2).clamp(0.0, size.width - side);
      final top = (raw.center.dy - side / 2).clamp(0.0, size.height - side);
      return Rect.fromLTWH(left, top, side, side);
    }
    final minimum = switch (e.type) {
      PlayerPart.controls => Size(300, math.max(72, e.playHeight + 8)),
      PlayerPart.progress => const Size(260, 64),
      PlayerPart.quickActions => const Size(200, 48),
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

  /// No action strip is drawn after the user removes (or hides) it.
  Rect actionBounds(Size size) {
    final actions = elements
        .where((e) => e.type == PlayerPart.quickActions && !e.hidden)
        .firstOrNull;
    return actions == null ? Rect.zero : bounds(actions, size);
  }
}

PlayerLayout playerTemplate({bool lyrics = false}) => PlayerLayout(
  id: lyrics ? 'builtin-lyrics' : 'builtin-cover',
  name: lyrics ? '歌词优先' : '唱片播放',
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
      id: 'quick-actions',
      type: PlayerPart.quickActions,
      frame: lyrics
          ? const Rect.fromLTWH(.08, .692, .84, .075)
          : const Rect.fromLTWH(.08, .703, .84, .075),
      wideFrame: lyrics
          ? const Rect.fromLTWH(.09, .73, .40, .06)
          : const Rect.fromLTWH(.07, .75, .40, .06),
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
