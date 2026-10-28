import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_controller.dart';
import '../../core/appearance.dart';
import '../../core/models.dart';
import '../../core/player_layout.dart';
import '../system_bars.dart';
import '../player_quick_actions.dart';
import 'layout_editing.dart';
import 'layout_renderer.dart';

class PlayerLayoutEditor extends StatefulWidget {
  const PlayerLayoutEditor({
    super.key,
    required this.app,
    required this.initial,
    required this.theme,
    required this.track,
    required this.lyrics,
  });
  final SylphyApp app;
  final PlayerLayout initial;
  final ThemeData theme;
  final Track track;
  final Future<String?>? lyrics;
  @override
  State<PlayerLayoutEditor> createState() => _PlayerLayoutEditorState();
}

class _PlayerLayoutEditorState extends State<PlayerLayoutEditor> {
  late final draft = PlayerLayoutDraft(widget.initial);
  bool snapping = true, preview = false, saving = false;
  int divisions = 3;
  String? error;
  Rect? gestureFrame;
  Offset gestureDelta = Offset.zero;
  List<double> vertical = [], horizontal = [];
  bool allowPop = false;

  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => error = '操作失败，请检查布局文件、保存位置或存储空间后重试');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _save({bool asNew = false}) => _run(() async {
    await widget.app.playerLayouts.save(
      draft.value,
      asNew: asNew || draft.value.id.startsWith('builtin-'),
    );
    if (!mounted) return;
    setState(() {
      allowPop = true;
      draft.baseline = draft.value.encode();
    });
    Navigator.pop(context);
  });

  Future<void> _leave() async {
    if (!draft.dirty) {
      setState(() => allowPop = true);
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未保存的布局？'),
        content: const Text('未保存的组件布局将被丢弃，已自动保存的外观设置会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => allowPop = true);
      Navigator.pop(context);
    }
  }

  /// Matches the area used by the real player at this window size: safe area,
  /// and the 1200 dp content cap. Playback has no top bar.
  Size _playerCanvas(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    return Size(
      math.min(
        1200,
        math.max(280, screen.width - padding.left - padding.right),
      ),
      math.max(320, screen.height - padding.top - padding.bottom),
    );
  }

  Rect _normalised(Rect pixels, Size canvas) {
    final width = (pixels.width / canvas.width).clamp(.01, 1.0);
    final height = (pixels.height / canvas.height).clamp(.01, 1.0);
    return Rect.fromLTWH(
      (pixels.left / canvas.width).clamp(0.0, 1 - width),
      (pixels.top / canvas.height).clamp(0.0, 1 - height),
      width,
      height,
    );
  }

  Rect _defaultFrame(PlayerPart type, Size canvas) {
    final width = canvas.width, height = canvas.height;
    final side = math.min(width, height) * .56;
    Rect px(double left, double top, double w, double h) =>
        Rect.fromLTWH(left, top, w, h);
    return switch (type) {
      PlayerPart.cover => _normalised(
        px((width - side) / 2, height * .08, side, side),
        canvas,
      ),
      PlayerPart.title => _normalised(
        px(width * .08, height * .55, width * .84, 52),
        canvas,
      ),
      PlayerPart.artist => _normalised(
        px(width * .08, height * .625, width * .84, 30),
        canvas,
      ),
      PlayerPart.lyrics => _normalised(
        px(width * .08, height * .68, width * .84, 130),
        canvas,
      ),
      PlayerPart.progress => _normalised(
        px(width * .08, height * .84, width * .84, 68),
        canvas,
      ),
      PlayerPart.controls => _normalised(
        px(width * .06, height * .915, width * .88, 70),
        canvas,
      ),
      PlayerPart.queue || PlayerPart.favorite => _normalised(
        px(width / 2 - 24, height * .45, 48, 48),
        canvas,
      ),
      PlayerPart.decoration => _normalised(
        px(width * .1, height * .1, width * .3, height * .2),
        canvas,
      ),
    };
  }

  void _add() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final type in PlayerPart.values)
            ListTile(
              title: Text(partLabels[type]!),
              onTap: () {
                final canvas = _playerCanvas(context);
                Navigator.pop(context);
                if (draft.value.elements.length >= 32) {
                  setState(() => error = '最多支持 32 个组件');
                  return;
                }
                final element = PlayerElement(
                  id: const Uuid().v4(),
                  type: type,
                  frame: _defaultFrame(type, canvas),
                  wideFrame: _defaultFrame(type, canvas),
                  fontSize: type == PlayerPart.artist ? 14 : 22,
                );
                draft.change(
                  draft.value.copyWith(
                    elements: [...draft.value.elements, element],
                  ),
                );
                draft.select(element.id);
              },
            ),
        ],
      ),
    ),
  );

  PlayerElement _withFrame(PlayerElement e, Rect frame, Size canvas) =>
      canvas.width > 850
      ? e.copyWith(wideFrame: frame)
      : e.copyWith(frame: frame);

  void _start(PlayerElement e, Size size) {
    draft.select(e.id);
    if (e.locked) return;
    draft.begin();
    gestureFrame = draft.value.bounds(e, size);
    gestureDelta = Offset.zero;
  }

  void _drag(
    PlayerElement e,
    Size size,
    Offset delta,
    double scale, {
    bool resize = false,
  }) {
    final before = gestureFrame;
    if (e.locked || before == null) return;
    gestureDelta += delta / scale;
    final square = e.type == PlayerPart.cover;
    final proposed = resize
        ? Rect.fromLTWH(
            before.left,
            before.top,
            square
                ? before.width +
                      (gestureDelta.dx.abs() > gestureDelta.dy.abs()
                          ? gestureDelta.dx
                          : gestureDelta.dy)
                : before.width + gestureDelta.dx,
            square
                ? before.height +
                      (gestureDelta.dx.abs() > gestureDelta.dy.abs()
                          ? gestureDelta.dx
                          : gestureDelta.dy)
                : before.height + gestureDelta.dy,
          )
        : before.shift(gestureDelta);
    final result = PlayerSnapEngine.constrain(
      proposed,
      size,
      divisions: divisions,
      enabled: snapping,
      resize: resize,
      square: square,
      minSize: square ? 48 : 24,
    );
    final frame = _normalised(result.frame, size);
    draft.update(_withFrame(e, frame, size));
    setState(() {
      vertical = result.vertical;
      horizontal = result.horizontal;
    });
  }

  void _end() {
    draft.commit();
    gestureFrame = null;
    setState(() {
      vertical = [];
      horizontal = [];
    });
  }

  Widget _canvas(
    BuildContext context,
    Size size,
    double scale,
    ThemeData theme,
  ) {
    final data = PlayerWidgetContext(
      app: widget.app,
      track: widget.track,
      lyrics: widget.lyrics,
      preview: true,
    );
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: PlayerLayoutBackground(layout: draft.value, data: data),
          ),
          if (!preview)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _GridPainter(
                    divisions: divisions,
                    enabled: snapping,
                    scale: scale,
                  ),
                ),
              ),
            ),
          for (final e in draft.value.elements.where((e) => !e.hidden))
            Positioned.fromRect(
              rect: draft.value.bounds(e, size),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: PlayerWidgetRegistry.build(context, e, data),
                    ),
                  ),
                  if (!preview)
                    Positioned.fill(
                      child: GestureDetector(
                        key: ValueKey('edit-${e.id}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => draft.select(e.id),
                        onPanStart: (_) => _start(e, size),
                        onPanUpdate: (details) =>
                            _drag(e, size, details.delta, scale),
                        onPanEnd: (_) => _end(),
                        onPanCancel: _end,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape:
                                e.type == PlayerPart.cover &&
                                    widget.app.appearance.disc
                                ? BoxShape.circle
                                : BoxShape.rectangle,
                            borderRadius:
                                e.type == PlayerPart.cover &&
                                    !widget.app.appearance.disc
                                ? BorderRadius.circular(e.radius)
                                : null,
                            border: Border.all(
                              color: draft.selectedId == e.id
                                  ? theme.colorScheme.primary
                                  : Colors.transparent,
                              width: 2 / scale,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (!preview &&
                      draft.selectedId == e.id &&
                      !e.locked &&
                      e.type == PlayerPart.cover)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: IgnorePointer(
                        child: Container(
                          width: 10 / scale,
                          height: 10 / scale,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  if (!preview && draft.selectedId == e.id && !e.locked)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: GestureDetector(
                        key: const ValueKey('resize-handle'),
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) => _start(e, size),
                        onPanUpdate: (details) =>
                            _drag(e, size, details.delta, scale, resize: true),
                        onPanEnd: (_) => _end(),
                        onPanCancel: _end,
                        child: Container(
                          width: 36 / scale,
                          height: 36 / scale,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(8 / scale),
                          ),
                          child: Icon(
                            Icons.open_in_full,
                            color: theme.colorScheme.onPrimary,
                            size: 18 / scale,
                          ),
                        ),
                      ),
                    ),
                  if (!preview && draft.selectedId == e.id)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: Colors.black87,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 3 / scale,
                              vertical: 1 / scale,
                            ),
                            child: Text(
                              '${partLabels[e.type]}${e.locked ? ' · 已锁定' : ''}',
                              style: TextStyle(
                                fontSize: 10 / scale,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Positioned.fromRect(
            rect: draft.value.actionBounds(size),
            child: IgnorePointer(
              child: PlayerQuickActions(
                app: widget.app,
                track: widget.track,
                preview: true,
              ),
            ),
          ),
          if (!preview && (vertical.isNotEmpty || horizontal.isNotEmpty))
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _GuidePainter(
                    vertical,
                    horizontal,
                    scale: scale,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> update, {
    String? valueLabel,
    int? steps,
    Key? sliderKey,
  }) => Row(
    children: [
      SizedBox(
        width: 64,
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
      Expanded(
        child: Slider(
          key: sliderKey,
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: steps,
          label: valueLabel,
          onChangeStart: (_) => draft.begin(),
          onChangeEnd: (_) => draft.commit(),
          onChanged: update,
        ),
      ),
      SizedBox(
        width: valueLabel == null ? 36 : 48,
        child: Text(valueLabel ?? value.toStringAsFixed(value <= 1 ? 2 : 0)),
      ),
    ],
  );

  Widget _inspector(Size canvas, {bool wide = false}) {
    final e = draft.selected;
    final frame = e == null ? Rect.zero : draft.value.frameFor(e, canvas);
    PlayerElement setFrame(PlayerElement value, Rect next) {
      final left = next.left.clamp(0.0, 1 - next.width);
      final top = next.top.clamp(0.0, 1 - next.height);
      final adjusted = Rect.fromLTWH(left, top, next.width, next.height);
      return _withFrame(value, adjusted, canvas);
    }

    return ListView(
      key: const ValueKey('player-inspector'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '组件与样式',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('添加'),
            ),
          ],
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(draft.selectedId),
          initialValue: e?.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '选择组件（含隐藏项）'),
          items: [
            for (final v in draft.value.elements)
              DropdownMenuItem(
                value: v.id,
                child: Text(
                  '${partLabels[v.type]}${v.hidden ? ' · 隐藏' : ''}${v.locked ? ' · 锁定' : ''}',
                ),
              ),
          ],
          onChanged: draft.select,
        ),
        if (e != null) ...[
          Row(
            children: [
              IconButton(
                tooltip: e.locked ? '解锁组件' : '锁定组件',
                onPressed: () => draft.update(e.copyWith(locked: !e.locked)),
                icon: Icon(e.locked ? Icons.lock : Icons.lock_open),
              ),
              IconButton(
                tooltip: e.hidden ? '显示组件' : '隐藏组件',
                onPressed: e.locked
                    ? null
                    : () => draft.update(e.copyWith(hidden: !e.hidden)),
                icon: Icon(e.hidden ? Icons.visibility_off : Icons.visibility),
              ),
              IconButton(
                tooltip: '删除组件',
                onPressed: e.locked ? null : draft.remove,
                icon: const Icon(Icons.delete_outline),
              ),
              const Spacer(),
              if ([PlayerPart.title, PlayerPart.artist].contains(e.type))
                PopupMenuButton<String>(
                  tooltip: '对齐',
                  enabled: !e.locked,
                  onSelected: (v) => draft.update(e.copyWith(align: v)),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'left', child: Text('左对齐')),
                    PopupMenuItem(value: 'center', child: Text('居中')),
                    PopupMenuItem(value: 'right', child: Text('右对齐')),
                  ],
                ),
            ],
          ),
          AbsorbPointer(
            absorbing: e.locked,
            child: Opacity(
              opacity: e.locked ? .4 : 1,
              child: Column(
                children: [
                  if (e.type == PlayerPart.cover) ...[
                    _slider(
                      '大小',
                      draft.value.bounds(e, canvas).width,
                      48,
                      math.min(canvas.width, canvas.height),
                      (v) {
                        final bounds = draft.value.bounds(e, canvas);
                        final left = (bounds.center.dx - v / 2)
                            .clamp(0.0, math.max(0.0, canvas.width - v))
                            .toDouble();
                        final top = (bounds.center.dy - v / 2)
                            .clamp(0.0, math.max(0.0, canvas.height - v))
                            .toDouble();
                        draft.update(
                          _withFrame(
                            e,
                            _normalised(Rect.fromLTWH(left, top, v, v), canvas),
                            canvas,
                          ),
                        );
                      },
                    ),
                    SwitchListTile(
                      key: const ValueKey('editor-disc'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('唱片样式'),
                      subtitle: const Text('关闭时显示专辑封面'),
                      value: widget.app.appearance.disc,
                      onChanged: saving
                          ? null
                          : (value) => _run(
                              () => widget.app.appearance.update(record: value),
                            ),
                    ),
                    SwitchListTile(
                      key: const ValueKey('editor-disc-rotation'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('唱片旋转'),
                      value: widget.app.appearance.discRotation,
                      onChanged: saving || !widget.app.appearance.disc
                          ? null
                          : (value) => _run(
                              () => widget.app.appearance.update(
                                rotateDisc: value,
                              ),
                            ),
                    ),
                    const Text(
                      '封面样式与旋转自动保存，同步用于播放页、歌词页和迷你播放器。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ] else ...[
                    _slider(
                      '宽度',
                      frame.width,
                      .01,
                      1,
                      (v) => draft.update(
                        setFrame(
                          e,
                          Rect.fromLTWH(
                            frame.left.clamp(0.0, 1 - v),
                            frame.top,
                            v,
                            frame.height,
                          ),
                        ),
                      ),
                    ),
                    _slider(
                      '高度',
                      frame.height,
                      .01,
                      1,
                      (v) => draft.update(
                        setFrame(
                          e,
                          Rect.fromLTWH(
                            frame.left,
                            frame.top.clamp(0.0, 1 - v),
                            frame.width,
                            v,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if ([PlayerPart.title, PlayerPart.artist].contains(e.type))
                    _slider(
                      '字号',
                      e.fontSize,
                      12,
                      40,
                      (v) => draft.update(e.copyWith(fontSize: v)),
                    ),
                  if (e.type == PlayerPart.lyrics) ...[
                    DropdownButtonFormField<double>(
                      key: ValueKey(
                        'editor-mini-font/${widget.app.appearance.miniLyricFontSize}',
                      ),
                      initialValue: widget.app.appearance.miniLyricFontSize,
                      decoration: const InputDecoration(labelText: '迷你歌词字号'),
                      items: [
                        for (final size in Appearance.miniLyricFontSizes)
                          DropdownMenuItem(
                            value: size,
                            child: Text(
                              '${Appearance.miniLyricFontLabel(size)} · ${size.toInt()}',
                            ),
                          ),
                      ],
                      onChanged: saving
                          ? null
                          : (value) => _run(
                              () => widget.app.appearance.update(
                                miniLyricFont: value,
                              ),
                            ),
                    ),
                    const Text(
                      '字号自动保存；完整歌词字号在歌词页内调整。',
                      style: TextStyle(fontSize: 12),
                    ),
                    _slider(
                      '歌词行距',
                      e.lyricLineHeight,
                      1,
                      2.5,
                      (v) => draft.update(e.copyWith(lyricLineHeight: v)),
                      steps: 30,
                      sliderKey: const ValueKey('editor-lyric-line-height'),
                      valueLabel: '${e.lyricLineHeight.toStringAsFixed(2)}×',
                    ),
                    const Text(
                      '行距随布局保存；空间不足时优先完整显示当前句。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                  _slider(
                    '透明度',
                    e.opacity,
                    .1,
                    1,
                    (v) => draft.update(e.copyWith(opacity: v)),
                  ),
                  if (e.type == PlayerPart.decoration ||
                      e.type == PlayerPart.controls ||
                      (e.type == PlayerPart.cover &&
                          !widget.app.appearance.disc))
                    _slider(
                      '圆角',
                      e.radius,
                      0,
                      64,
                      (v) => draft.update(e.copyWith(radius: v)),
                    ),
                  if (e.type == PlayerPart.controls)
                    _slider(
                      '播放键宽',
                      e.playWidth,
                      56,
                      96,
                      (v) => draft.update(e.copyWith(playWidth: v)),
                    ),
                  if (e.type == PlayerPart.controls) ...[
                    _slider(
                      '播放键高',
                      e.playHeight,
                      48,
                      96,
                      (v) => draft.update(e.copyWith(playHeight: v)),
                    ),
                    _slider(
                      '按钮间距',
                      e.controlSpacing,
                      0,
                      32,
                      (v) => draft.update(e.copyWith(controlSpacing: v)),
                    ),
                  ],
                  if (e.type != PlayerPart.cover &&
                      e.type != PlayerPart.favorite)
                    Wrap(
                      spacing: 4,
                      children: [
                        for (final c in <int?>[
                          null,
                          0xffffffff,
                          0xff82c7e4,
                          0xffe8bca3,
                          0xffb3d6a6,
                        ])
                          ChoiceChip(
                            label: c == null
                                ? const Text('主题')
                                : Icon(Icons.circle, color: Color(c), size: 18),
                            selected: e.color == c,
                            onSelected: (_) => draft.update(
                              e.copyWith(color: c, clearColor: c == null),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
        const Divider(height: 32),
        Text('页面', style: Theme.of(context).textTheme.titleMedium),
        DropdownButtonFormField<PlayerBackground>(
          key: ValueKey(draft.value.background),
          initialValue: draft.value.background,
          decoration: const InputDecoration(labelText: '背景'),
          items: const [
            DropdownMenuItem(
              value: PlayerBackground.album,
              child: Text('封面模糊'),
            ),
            DropdownMenuItem(
              value: PlayerBackground.gradient,
              child: Text('主题渐变'),
            ),
            DropdownMenuItem(value: PlayerBackground.solid, child: Text('纯色')),
          ],
          onChanged: (v) {
            if (v != null) draft.change(draft.value.copyWith(background: v));
          },
        ),
        _slider(
          '背景浓度',
          draft.value.backgroundOpacity,
          .1,
          1,
          (v) => draft.change(draft.value.copyWith(backgroundOpacity: v)),
        ),
        if (draft.value.background == PlayerBackground.album)
          SwitchListTile(
            key: const ValueKey('editor-ambient'),
            contentPadding: EdgeInsets.zero,
            title: const Text('封面模糊背景'),
            subtitle: const Text('自动保存；关闭时使用主题或纯色底色'),
            value: widget.app.appearance.ambient,
            onChanged: saving
                ? null
                : (value) => _run(
                    () => widget.app.appearance.update(background: value),
                  ),
          ),
        const Text(
          '拖动组件摆放，拖动右下角缩放；9 / 16 宫格和吸附可开关。',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Future<void> _rename() async {
    final input = TextEditingController(text: draft.value.name);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('模板名称'),
        content: TextField(controller: input, maxLength: 60, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (input.text.trim().isNotEmpty) {
                Navigator.pop(context, input.text.trim());
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (mounted && value != null) {
      draft.change(draft.value.copyWith(name: value));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
  }

  Widget _toolbar() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        PopupMenuButton<PlayerLayout>(
          tooltip: '选择布局模板',
          onSelected: (layout) {
            draft.change(layout);
            draft.select(null);
          },
          itemBuilder: (_) => [
            for (final l in [
              playerTemplate(),
              playerTemplate(lyrics: true),
              ...widget.app.playerLayouts.templates,
            ])
              PopupMenuItem(value: l, child: Text(l.name)),
          ],
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('${draft.value.name} ▾'),
          ),
        ),
        IconButton(
          tooltip: '撤销',
          onPressed: draft.canUndo ? draft.undo : null,
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          tooltip: '重做',
          onPressed: draft.canRedo ? draft.redo : null,
          icon: const Icon(Icons.redo),
        ),
        IconButton(
          tooltip: '吸附开关',
          isSelected: snapping,
          onPressed: () => setState(() => snapping = !snapping),
          icon: const Icon(Icons.grid_4x4),
        ),
        PopupMenuButton<int>(
          tooltip: '选择宫格',
          initialValue: divisions,
          onSelected: (value) => setState(() => divisions = value),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 3, child: Text('九宫格 · 3×3')),
            PopupMenuItem(value: 4, child: Text('十六宫格 · 4×4')),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Text(divisions == 3 ? '9宫格' : '16宫格'),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: '布局操作',
          onSelected: (action) {
            switch (action) {
              case 'add':
                _add();
              case 'rename':
                _rename();
              case 'saveAs':
                _save(asNew: true);
              case 'reset':
                draft.change(playerTemplate());
                draft.select(null);
              case 'default':
                _run(() async {
                  await widget.app.playerLayouts.select(null);
                  if (!mounted) return;
                  setState(() => allowPop = true);
                  Navigator.pop(context);
                });
              case 'export':
                _run(() => widget.app.playerLayouts.exportFile(draft.value));
              case 'import':
                _run(() async {
                  final layout = await widget.app.playerLayouts.importFile();
                  if (mounted && layout != null) {
                    draft.change(layout);
                    draft.select(null);
                  }
                });
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'add', child: Text('添加组件')),
            PopupMenuItem(value: 'rename', child: Text('重命名模板')),
            PopupMenuItem(value: 'saveAs', child: Text('另存为新模板并应用')),
            PopupMenuItem(value: 'reset', child: Text('恢复默认布局')),
            PopupMenuItem(value: 'default', child: Text('使用系统默认布局')),
            PopupMenuItem(value: 'import', child: Text('导入布局 JSON')),
            PopupMenuItem(value: 'export', child: Text('导出布局 JSON')),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([draft, widget.app.appearance]),
    builder: (context, _) => Theme(
      data: widget.theme,
      child: Builder(
        builder: (context) => PopScope(
          canPop: allowPop || !draft.dirty,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _leave();
          },
          child: AppSystemBars(
            child: Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  tooltip: '关闭编辑器',
                  onPressed: _leave,
                  icon: const Icon(Icons.close),
                ),
                title: const Text('播放页编辑器'),
                actions: [
                  IconButton(
                    tooltip: preview ? '继续编辑' : '预览布局',
                    onPressed: () => setState(() => preview = !preview),
                    icon: Icon(
                      preview ? Icons.edit_outlined : Icons.visibility_outlined,
                    ),
                  ),
                  IconButton(
                    tooltip: '保存并应用',
                    onPressed: saving ? null : _save,
                    icon: const Icon(Icons.check),
                  ),
                ],
              ),
              body: SafeArea(
                top: false,
                child: Column(
                  children: [
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (widget.app.playerLayouts.loadFailed)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('原布局无法读取，暂用默认布局；原数据保留，保存后才替换。'),
                      ),
                    if (widget.app.playerLayouts.active == null)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 2),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '当前未启用自定义布局；保存后成为独立自定义模板。',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    _toolbar(),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth > 850;
                          final canvasSize = _playerCanvas(context);
                          final canvas = LayoutBuilder(
                            builder: (context, box) {
                              final scale = math
                                  .min(
                                    (box.maxWidth - 24) / canvasSize.width,
                                    (box.maxHeight - 24) / canvasSize.height,
                                  )
                                  .clamp(.05, 2.0);
                              return Center(
                                child: SizedBox(
                                  width: canvasSize.width * scale,
                                  height: canvasSize.height * scale,
                                  child: FittedBox(
                                    child: SizedBox(
                                      width: canvasSize.width,
                                      height: canvasSize.height,
                                      child: _canvas(
                                        context,
                                        canvasSize,
                                        scale,
                                        widget.theme,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                          if (wide) {
                            return Row(
                              children: [
                                Expanded(child: canvas),
                                SizedBox(
                                  width: 320,
                                  child: _inspector(canvasSize, wide: true),
                                ),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              Expanded(child: canvas),
                              SizedBox(
                                height: math.min(
                                  260,
                                  constraints.maxHeight * .43,
                                ),
                                child: _inspector(canvasSize),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter(
    this.vertical,
    this.horizontal, {
    required this.scale,
    required this.color,
  });
  final List<double> vertical, horizontal;
  final double scale;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1 / scale;
    for (final x in vertical) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (final y in horizontal) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) => true;
}

class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.divisions,
    required this.enabled,
    required this.scale,
  });
  final int divisions;
  final bool enabled;
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    final cell = Paint()
      ..color = enabled ? Colors.white12 : Colors.white10
      ..strokeWidth = 1 / scale;
    final strong = Paint()
      ..color = enabled ? Colors.white24 : Colors.white12
      ..strokeWidth = 1.25 / scale;
    for (var i = 1; i < divisions; i++) {
      final x = size.width * i / divisions;
      final y = size.height * i / divisions;
      final paint = i * 2 == divisions ? strong : cell;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.divisions != divisions ||
      old.enabled != enabled ||
      old.scale != scale;
}
