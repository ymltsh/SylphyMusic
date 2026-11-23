import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/lyrics.dart';
import 'lyrics_view.dart';

/// Shows a timed cue with falling words or characters from its original line.
class SkylineLyrics extends StatefulWidget {
  const SkylineLyrics({
    super.key,
    required this.text,
    required this.position,
    required this.duration,
    required this.advancing,
    required this.speed,
    required this.fontSize,
    this.fontWeight,
    required this.color,
    required this.untimedLyrics,
  });

  final String text;
  final Duration position;
  final Duration duration;
  final bool advancing;
  final double speed;
  final double fontSize;
  final FontWeight? fontWeight;
  final Color color;
  final Widget untimedLyrics;

  @override
  State<SkylineLyrics> createState() => _SkylineLyricsState();
}

typedef _SkylineFrame = ({double age, double visibility, double lyricOffset});

class _SkylineLyricsState extends State<SkylineLyrics>
    with SingleTickerProviderStateMixin {
  static const _projectionLimitMs = 500.0;
  static const _correctionWindowMs = 400.0;
  static const _emptyFrame = (age: .4, visibility: 0.0, lyricOffset: 0.0);
  static final _edgeUnit = RegExp(
    r"[\p{Script=Latin}][\p{Script=Latin}\p{M}\p{N}]*"
    r"(?:['’‐‑-][\p{Script=Latin}\p{M}\p{N}]+)*|[\p{L}\p{N}]\p{M}*",
    unicode: true,
  );
  static const _serifFallback = [
    'Songti SC',
    'SimSun',
    'Noto Serif CJK SC',
    'Georgia',
    'serif',
  ];

  final _clock = Stopwatch()..start();
  final _frame = ValueNotifier<_SkylineFrame>(_emptyFrame);
  late final _ticker = createTicker(_tick);
  late List<LrcLine> _lines = mergedLyricLines(widget.text);
  bool _reduceMotion = false;
  int _active = -1;
  double _sampleTime = 0;
  double _samplePosition = 0;
  double _correction = 0;
  double _rate = 0;

  double get _now => _clock.elapsedMicroseconds / 1000;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final changed = _reduceMotion != reduceMotion;
    _reduceMotion = reduceMotion;
    _syncPosition(snap: changed);
  }

  @override
  void didUpdateWidget(SkylineLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    final textChanged = oldWidget.text != widget.text;
    if (textChanged) _lines = mergedLyricLines(widget.text);
    if (textChanged ||
        oldWidget.position != widget.position ||
        oldWidget.advancing != widget.advancing ||
        oldWidget.speed != widget.speed) {
      _syncPosition(snap: textChanged || widget.position < oldWidget.position);
    } else if (oldWidget.duration != widget.duration) {
      _updateFrame(_now, rebuildCue: false);
    }
  }

  double _positionAt(double now) {
    final elapsed = math.min(now - _sampleTime, _projectionLimitMs);
    final residual = math.max(0.0, 1 - elapsed / _correctionWindowMs);
    return _samplePosition + elapsed * _rate + _correction * residual;
  }

  void _syncPosition({required bool snap}) {
    final now = _now;
    final position = widget.position.inMicroseconds / 1000;
    final rate = !_reduceMotion && widget.advancing && _lines.isNotEmpty
        ? widget.speed
        : 0.0;
    final delta = _positionAt(now) - position;
    // Spread small clock corrections over several frames. The correction
    // limit keeps the projected position advancing throughout the adjustment.
    final limit = math.min(180.0, rate * _correctionWindowMs * .65);
    _correction = !snap && _rate > 0 && delta.abs() <= limit ? delta : 0;
    _sampleTime = now;
    _samplePosition = position;
    _rate = rate;

    if (_rate > 0) {
      if (!_ticker.isActive) _ticker.start();
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
    _updateFrame(now, rebuildCue: false);
  }

  void _tick(Duration _) {
    final now = _now;
    _updateFrame(now, rebuildCue: true);
    if (now - _sampleTime >= _projectionLimitMs) _ticker.stop();
  }

  void _updateFrame(double now, {required bool rebuildCue}) {
    final position = _positionAt(now);
    final index = activeLrcIndex(
      _lines,
      Duration(microseconds: (position * 1000).round()),
    );
    if (_active != index) {
      _active = index;
      if (rebuildCue) setState(() {});
    }
    if (index < 0 || _lines[index].text.isEmpty) {
      _frame.value = _emptyFrame;
      return;
    }
    if (_reduceMotion) {
      _frame.value = (age: .4, visibility: 1.0, lyricOffset: 0.0);
      return;
    }

    final cue = _lines[index];
    final end = index < _lines.length - 1
        ? _lines[index + 1].at
        : widget.duration;
    final hasEnd = end > cue.at;
    final interval = hasEnd ? (end - cue.at).inMicroseconds / 1000 : 2400.0;
    final elapsed = position - cue.at.inMicroseconds / 1000;
    final age = (elapsed / interval).clamp(0.0, 1.0);
    final enter = (elapsed / math.min(270.0, interval * .24)).clamp(0.0, 1.0);
    final exit = hasEnd
        ? ((interval - elapsed) / math.min(320.0, interval * .24)).clamp(
            0.0,
            1.0,
          )
        : 1.0;
    final entering = 1 - enter;
    _frame.value = (
      age: age,
      visibility: math.min(1 - entering * entering * entering, exit),
      lyricOffset: 8 * entering * entering - 8 * (1 - exit),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_lines.isEmpty) return widget.untimedLyrics;
    if (_active < 0 || _lines[_active].text.isEmpty) {
      return const SizedBox.expand();
    }

    final parts = _lines[_active].text.split('\n');
    final units = _edgeUnit.allMatches(parts.first).toList();
    final first = units.firstOrNull?.group(0);
    final last = units.lastOrNull?.group(0);
    final hasWord =
        (first?.runes.length ?? 0) > 1 || (last?.runes.length ?? 0) > 1;
    final style = Theme.of(context).textTheme.titleLarge!.copyWith(
      fontFamily: 'Noto Serif SC',
      fontFamilyFallback: _serifFallback,
      fontSize: widget.fontSize,
      height: 1.38,
      letterSpacing: 1.6,
      fontWeight: widget.fontWeight ?? FontWeight.w500,
      color: widget.color,
    );
    final lyric = Text.rich(
      TextSpan(
        text: parts.first,
        children: [
          if (parts.length > 1)
            TextSpan(
              text: '\n${parts.skip(1).join('\n')}',
              style: TextStyle(
                color: widget.color.withValues(alpha: .86),
                fontSize: widget.fontSize * .75,
                letterSpacing: .5,
              ),
            ),
        ],
      ),
      textAlign: TextAlign.center,
      style: style,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math
            .min(constraints.maxWidth / 680, constraints.maxHeight / 200)
            .clamp(.25, 1.0);
        final gutter = first == null
            ? 0.0
            : math.min(
                (hasWord ? 112 : 74) * scale + 14,
                constraints.maxWidth * (hasWord ? .23 : .20),
              );
        return ClipRect(
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              textDirection: TextDirection.ltr,
              children: [
                if (first != null)
                  _fallingUnit(first, style, gutter, scale, -1),
                Flexible(
                  child: ValueListenableBuilder<_SkylineFrame>(
                    valueListenable: _frame,
                    child: RepaintBoundary(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth - 2 * gutter,
                          ),
                          child: lyric,
                        ),
                      ),
                    ),
                    builder: (context, frame, child) => Transform.translate(
                      offset: Offset(0, frame.lyricOffset * scale),
                      child: Opacity(opacity: frame.visibility, child: child),
                    ),
                  ),
                ),
                if (last != null) _fallingUnit(last, style, gutter, scale, 1),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _fallingUnit(
    String unit,
    TextStyle style,
    double gutter,
    double scale,
    int side,
  ) => ExcludeSemantics(
    child: SizedBox(
      width: gutter,
      child: ValueListenableBuilder<_SkylineFrame>(
        valueListenable: _frame,
        child: RepaintBoundary(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter * .14),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                unit,
                maxLines: 1,
                textScaler: TextScaler.noScaling,
                style: style.copyWith(
                  color: const Color(0xffe7bd88),
                  fontSize: (side < 0 ? 28 : 22) * scale,
                  letterSpacing: 0,
                  shadows: const [
                    Shadow(color: Color(0xcc100a07), blurRadius: 4),
                  ],
                ),
              ),
            ),
          ),
        ),
        builder: (context, frame, child) => Transform.translate(
          offset: Offset(
            gutter * .13 * frame.age * side,
            (98 * frame.age - 71) * scale,
          ),
          child: Transform.rotate(
            angle: side * (.07 + .42 * frame.age),
            child: Opacity(
              opacity: frame.visibility * (.78 - .24 * frame.age),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}
