import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../services/lyrics.dart';

List<LrcLine> mergedLyricLines(String text) {
  // Original and translation often share a timestamp. Keep them together.
  final lines = <LrcLine>[];
  for (final line in parseLrc(text)) {
    if (lines.isNotEmpty && lines.last.at == line.at) {
      final previous = lines.removeLast();
      lines.add(
        LrcLine(
          line.at,
          [
            previous.text,
            line.text,
          ].where((text) => text.isNotEmpty).join('\n'),
        ),
      );
    } else {
      lines.add(line);
    }
  }
  return lines;
}

class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.text,
    required this.position,
    this.onSeek,
    this.initialFontSize = 22,
    this.highlightColor,
    this.textAlign = TextAlign.center,
    this.showToolbar = true,
  });
  final String text;
  final Duration position;
  final ValueChanged<Duration>? onSeek;
  final double initialFontSize;
  final Color? highlightColor;
  final TextAlign textAlign;
  final bool showToolbar;
  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final controller = ScrollController();
  late List<LrcLine> lines;
  int active = -1;
  bool following = true;
  double fontSize = 22;
  List<double> heights = [];
  List<double> offsets = [];
  double edge = 0;
  bool pending = false;
  String? geometryKey;

  @override
  void initState() {
    super.initState();
    fontSize = widget.initialFontSize;
    _parse();
  }

  void _parse() {
    lines = mergedLyricLines(widget.text);
    active = activeLrcIndex(lines, widget.position);
    geometryKey = null;
    following = true;
    _scheduleFollow();
  }

  @override
  void didUpdateWidget(LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFontSize != widget.initialFontSize) {
      fontSize = widget.initialFontSize;
      geometryKey = null;
    }
    if (oldWidget.text != widget.text) {
      _parse();
      return;
    }
    final next = activeLrcIndex(lines, widget.position);
    if (next != active) {
      active = next;
      _scheduleFollow();
    }
  }

  void _scheduleFollow() {
    if (pending) return;
    pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pending = false;
      if (!mounted || !following || !controller.hasClients || offsets.isEmpty) {
        return;
      }
      final index = active < 0 ? 0 : active;
      final target =
          (edge +
                  offsets[index] +
                  heights[index] / 2 -
                  controller.position.viewportDimension * .43)
              .clamp(0.0, controller.position.maxScrollExtent);
      if (MediaQuery.disableAnimationsOf(context)) {
        controller.jumpTo(target);
      } else {
        controller.animateTo(
          target,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  List<InlineSpan> _spans(String text, {Color? secondaryColor}) {
    if (text.isEmpty) return const [TextSpan(text: '···')];
    final parts = text.split('\n');
    return [
      TextSpan(text: parts.first),
      if (parts.length > 1)
        TextSpan(
          text: '\n${parts.skip(1).join('\n')}',
          style: TextStyle(
            fontSize: fontSize * .65,
            height: 1.5,
            fontWeight: FontWeight.w400,
            color: secondaryColor,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.titleLarge!.copyWith(
      fontSize: fontSize,
      height: 1.5,
      fontWeight: FontWeight.w600,
    );
    return Column(
      children: [
        if (widget.showToolbar)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 12, 0),
            child: Row(
              children: [
                Icon(
                  lines.isEmpty
                      ? Icons.notes_rounded
                      : Icons.graphic_eq_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lines.isEmpty
                        ? '文本歌词 · 暂无时间轴'
                        : following
                        ? '歌词 · 跟随播放'
                        : '歌词 · 自由浏览',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                PopupMenuButton<double>(
                  tooltip: '歌词字号',
                  icon: const Icon(Icons.text_fields_rounded),
                  initialValue: fontSize,
                  onSelected: (value) => setState(() {
                    fontSize = value;
                    geometryKey = null;
                  }),
                  itemBuilder: (_) => [
                    for (final entry in {
                      18.0: '小',
                      22.0: '标准',
                      28.0: '大',
                    }.entries)
                      CheckedPopupMenuItem(
                        value: entry.key,
                        checked: fontSize == entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                ),
              ],
            ),
          ),
        Expanded(
          child: lines.isEmpty
              ? SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 48),
                  child: SelectableText(
                    widget.text.trim(),
                    style: style,
                    textAlign: widget.textAlign,
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final scaler = MediaQuery.textScalerOf(context);
                    final width = (constraints.maxWidth - 56).clamp(
                      1.0,
                      double.infinity,
                    );
                    final key =
                        '${constraints.maxWidth}/${constraints.maxHeight}/$style/${scaler.scale(fontSize)}/${Directionality.of(context)}/${widget.textAlign}';
                    if (geometryKey != key) {
                      geometryKey = key;
                      heights = [];
                      offsets = [];
                      var offset = 0.0;
                      for (final line in lines) {
                        final painter = TextPainter(
                          text: TextSpan(
                            style: style,
                            children: _spans(line.text),
                          ),
                          textDirection: Directionality.of(context),
                          textScaler: scaler,
                          textAlign: widget.textAlign,
                        )..layout(maxWidth: width);
                        offsets.add(offset);
                        final height = painter.height + 28;
                        heights.add(height);
                        offset += height;
                        painter.dispose();
                      }
                      edge = constraints.maxHeight * .43;
                      _scheduleFollow();
                    }
                    return Stack(
                      children: [
                        ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (bounds) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.white,
                              Colors.white,
                              Colors.transparent,
                            ],
                            stops: [0, .12, .85, 1],
                          ).createShader(bounds),
                          child: NotificationListener<UserScrollNotification>(
                            onNotification: (notification) {
                              if (notification.direction !=
                                      ScrollDirection.idle &&
                                  following) {
                                setState(() => following = false);
                              }
                              return false;
                            },
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context)
                                  .copyWith(scrollbars: false),
                              child: ListView.builder(
                                key: const ValueKey('timed-lyrics'),
                                controller: controller,
                                padding: EdgeInsets.only(
                                  top: edge,
                                  bottom: constraints.maxHeight - edge,
                                ),
                                itemCount: lines.length,
                                itemExtentBuilder: (index, _) => heights[index],
                                itemBuilder: (context, index) {
                                  final selected = index == active;
                                  final line = lines[index];
                                  return Semantics(
                                    selected: selected,
                                    label: line.text.isEmpty ? '间奏' : null,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: widget.onSeek == null
                                          ? null
                                          : () {
                                              setState(() => following = true);
                                              widget.onSeek!(
                                                line.at < Duration.zero
                                                    ? Duration.zero
                                                    : line.at,
                                              );
                                              _scheduleFollow();
                                            },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 28,
                                          vertical: 14,
                                        ),
                                        child: AnimatedDefaultTextStyle(
                                          duration:
                                              MediaQuery.disableAnimationsOf(
                                                context,
                                              )
                                              ? Duration.zero
                                              : const Duration(
                                                  milliseconds: 220,
                                                ),
                                          style: style.copyWith(
                                            color: selected
                                                ? widget.highlightColor ??
                                                      scheme.primary
                                                : scheme.onSurface.withValues(
                                                    alpha: .48,
                                                  ),
                                          ),
                                          textAlign: widget.textAlign,
                                          child: Text.rich(
                                            TextSpan(
                                              children: _spans(
                                                line.text,
                                                secondaryColor: scheme.onSurface
                                                    .withValues(
                                                      alpha: selected
                                                          ? .68
                                                          : .38,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        if (!following)
                          Positioned(
                            bottom: 12,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: FilledButton.tonalIcon(
                                onPressed: () {
                                  setState(() => following = true);
                                  _scheduleFollow();
                                },
                                icon: const Icon(
                                  Icons.my_location_rounded,
                                  size: 18,
                                ),
                                label: const Text('回到当前'),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class LyricsPreview extends StatelessWidget {
  const LyricsPreview({
    super.key,
    required this.text,
    required this.position,
    this.fontSize = 24,
    this.lineHeight = 1.5,
    this.highlightColor,
  });
  final String text;
  final Duration position;
  final double fontSize;
  final double lineHeight;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final merged = mergedLyricLines(text);
    final plain = merged.isEmpty;
    final plainLines = plain
        ? text
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList()
        : const <String>[];
    final active = plain ? 0 : activeLrcIndex(merged, position);
    return LayoutBuilder(
      builder: (context, constraints) {
        final lines = plain
            ? (plainLines.isEmpty ? ['···'] : plainLines)
            : [for (final line in merged) line.text.split('\n').first.trim()];
        final current = plain || active < 0 ? 0 : active;
        final scaler = MediaQuery.textScalerOf(context);
        final locale = Localizations.maybeLocaleOf(context);
        TextStyle styleFor(int index) => DefaultTextStyle.of(context).style
            .merge(
              (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
                fontSize: fontSize,
                height: lineHeight,
                fontWeight: index == current
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: index == current
                    ? highlightColor ?? scheme.primary
                    : scheme.onSurface.withValues(alpha: .42),
              ),
            );
        String lineAt(int index) => lines[index].isEmpty ? '···' : lines[index];
        final heights = <int, double>{};
        double heightAt(int index) => heights.putIfAbsent(index, () {
          final painter = TextPainter(
            text: TextSpan(
              text: lineAt(index),
              style: styleFor(index).copyWith(fontWeight: FontWeight.w600),
            ),
            textDirection: Directionality.of(context),
            textAlign: TextAlign.center,
            textScaler: scaler,
            locale: locale,
            maxLines: 2,
            ellipsis: '…',
          )..layout(maxWidth: constraints.maxWidth);
          final height = painter.height;
          painter.dispose();
          return height;
        });
        var count = math.min(5, lines.length);
        var start = 0;
        // Keep the current sentence complete before adding neighbouring lines.
        // A wrapped sentence consumes its actual two-line height.
        while (true) {
          start = plain
              ? 0
              : (current - (count - 1) ~/ 2)
                    .clamp(0, math.max(0, lines.length - count))
                    .toInt();
          final height = List.generate(
            count,
            (i) => heightAt(start + i),
          ).fold(0.0, (total, value) => total + value);
          if (height <= constraints.maxHeight || count == 1) break;
          count--;
        }
        final duration = MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 320);
        final windowKey = ValueKey((text, start, count));
        final windowHeight = List.generate(
          count,
          (i) => heightAt(start + i),
        ).fold(0.0, (sum, height) => sum + height);
        final distance =
            constraints.maxHeight > 0 && constraints.maxHeight.isFinite
            ? (windowHeight / count / constraints.maxHeight).clamp(0.0, 1.0)
            : .2;
        return ClipRect(
          child: AnimatedSwitcher(
            duration: duration,
            switchInCurve: Curves.easeInOutCubic,
            switchOutCurve: Curves.easeInOutCubic,
            transitionBuilder: (child, animation) {
              final entering = child.key == windowKey;
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(0, entering ? distance : -distance),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Center(
              key: windowKey,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var index = start; index < start + count; index++)
                        SizedBox(
                          height: heightAt(index),
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: duration,
                              curve: Curves.easeInOutCubic,
                              style: styleFor(index),
                              child: Text(
                                lineAt(index),
                                maxLines: 2,
                                softWrap: true,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                textScaler: scaler,
                                locale: locale,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
