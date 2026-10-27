import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/player_layout.dart';

class SnapResult {
  const SnapResult(this.frame, this.vertical, this.horizontal);
  final Rect frame;
  final List<double> vertical, horizontal;
}

/// Snaps a free-form widget to the visible 3×3 (9-cell) or 4×4 (16-cell)
/// canvas grid. Unlike the previous editor there are no regions: the whole
/// player is one canvas.
class PlayerSnapEngine {
  static const _threshold = 12.0;

  static SnapResult constrain(
    Rect proposed,
    Size canvas, {
    int divisions = 3,
    bool enabled = true,
    bool resize = false,
    bool square = false,
    double minSize = 24,
  }) {
    final grid = divisions == 4 ? 4 : 3;
    final min = math.min(minSize, math.min(canvas.width, canvas.height));
    var rect = _clampRect(proposed, canvas, min, square);
    if (!enabled) {
      return SnapResult(rect, const [], const []);
    }
    final xs = _anchors(canvas.width, grid);
    final ys = _anchors(canvas.height, grid);
    if (square) {
      return _snapSquare(rect, canvas, xs, ys, resize, min);
    }
    if (resize) {
      final x = _nearest(rect.right, xs);
      final y = _nearest(rect.bottom, ys);
      var width = rect.width;
      var height = rect.height;
      final guidesX = <double>[];
      final guidesY = <double>[];
      if (x != null) {
        width = (x - rect.left).clamp(min, canvas.width - rect.left);
        guidesX.add(x);
      }
      if (y != null) {
        height = (y - rect.top).clamp(min, canvas.height - rect.top);
        guidesY.add(y);
      }
      rect = Rect.fromLTWH(rect.left, rect.top, width, height);
      return SnapResult(rect, guidesX, guidesY);
    }
    final dx = _nearestAny([rect.left, rect.center.dx, rect.right], xs);
    final dy = _nearestAny([rect.top, rect.center.dy, rect.bottom], ys);
    var left = rect.left + (dx?.$1 ?? 0);
    var top = rect.top + (dy?.$1 ?? 0);
    left = left.clamp(0.0, math.max(0.0, canvas.width - rect.width));
    top = top.clamp(0.0, math.max(0.0, canvas.height - rect.height));
    return SnapResult(
      Rect.fromLTWH(left, top, rect.width, rect.height),
      dx == null ? const [] : [dx.$2],
      dy == null ? const [] : [dy.$2],
    );
  }

  static Rect _clampRect(Rect proposed, Size canvas, double min, bool square) {
    if (square) {
      final side = proposed.width
          .clamp(min, math.min(canvas.width, canvas.height))
          .toDouble();
      final left = proposed.left
          .clamp(0.0, math.max(0.0, canvas.width - side))
          .toDouble();
      final top = proposed.top
          .clamp(0.0, math.max(0.0, canvas.height - side))
          .toDouble();
      return Rect.fromLTWH(left, top, side, side);
    }
    final width = proposed.width.clamp(min, canvas.width).toDouble();
    final height = proposed.height.clamp(min, canvas.height).toDouble();
    return Rect.fromLTWH(
      proposed.left.clamp(0.0, math.max(0.0, canvas.width - width)),
      proposed.top.clamp(0.0, math.max(0.0, canvas.height - height)),
      width,
      height,
    );
  }

  static SnapResult _snapSquare(
    Rect rect,
    Size canvas,
    List<double> xs,
    List<double> ys,
    bool resize,
    double min,
  ) {
    if (resize) {
      final right = _nearest(rect.right, xs);
      final bottom = _nearest(rect.bottom, ys);
      double? side;
      double? guideX;
      double? guideY;
      if (right != null) {
        side = right - rect.left;
        guideX = right;
      }
      if (bottom != null) {
        final candidate = bottom - rect.top;
        if (side == null ||
            (candidate - rect.width).abs() < (side - rect.width).abs()) {
          side = candidate;
          guideX = null;
          guideY = bottom;
        } else if ((candidate - side).abs() < .001) {
          guideY = bottom;
        }
      }
      final next = (side ?? rect.width)
          .clamp(
            min,
            math.min(canvas.width - rect.left, canvas.height - rect.top),
          )
          .toDouble();
      return SnapResult(
        Rect.fromLTWH(rect.left, rect.top, next, next),
        guideX == null ? const [] : [guideX],
        guideY == null ? const [] : [guideY],
      );
    }
    final dx = _nearestAny([rect.left, rect.center.dx, rect.right], xs);
    final dy = _nearestAny([rect.top, rect.center.dy, rect.bottom], ys);
    var left = rect.left + (dx?.$1 ?? 0);
    var top = rect.top + (dy?.$1 ?? 0);
    left = left.clamp(0.0, math.max(0.0, canvas.width - rect.width));
    top = top.clamp(0.0, math.max(0.0, canvas.height - rect.height));
    return SnapResult(
      Rect.fromLTWH(left, top, rect.width, rect.height),
      dx == null ? const [] : [dx.$2],
      dy == null ? const [] : [dy.$2],
    );
  }

  static List<double> _anchors(double length, int divisions) {
    final values = <double>{
      for (var i = 0; i <= divisions; i++) length * i / divisions,
      length / 2,
    }.toList()..sort();
    return values;
  }

  static double? _nearest(double value, List<double> targets) {
    double? best;
    var distance = _threshold;
    for (final target in targets) {
      final delta = (target - value).abs();
      if (delta < distance) {
        distance = delta;
        best = target;
      }
    }
    return best;
  }

  static (double, double)? _nearestAny(
    List<double> anchors,
    List<double> targets,
  ) {
    (double, double)? best;
    var distance = _threshold;
    for (final anchor in anchors) {
      for (final target in targets) {
        final delta = (target - anchor).abs();
        if (delta < distance) {
          distance = delta;
          best = (target - anchor, target);
        }
      }
    }
    return best;
  }
}

class PlayerLayoutDraft extends ChangeNotifier {
  PlayerLayoutDraft(this.value) : baseline = value.encode();
  PlayerLayout value;
  String baseline;
  String? selectedId;
  final List<PlayerLayout> _undo = [], _redo = [];
  PlayerLayout? _gestureStart;
  bool get dirty => value.encode() != baseline;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  PlayerElement? get selected =>
      value.elements.where((e) => e.id == selectedId).firstOrNull;
  void select(String? id) {
    selectedId = id;
    notifyListeners();
  }

  void begin() {
    _gestureStart = value;
  }

  void commit() {
    final before = _gestureStart;
    _gestureStart = null;
    if (before != null && before.encode() != value.encode()) {
      _record(before);
      notifyListeners();
    }
  }

  void _record(PlayerLayout before) {
    _undo.add(before);
    if (_undo.length > 80) _undo.removeAt(0);
    _redo.clear();
  }

  void change(PlayerLayout next) {
    if (next.encode() == value.encode()) return;
    if (_gestureStart == null) _record(value);
    value = next;
    notifyListeners();
  }

  void update(PlayerElement next) => change(
    value.copyWith(
      elements: [
        for (final e in value.elements)
          if (e.id == next.id) next else e,
      ],
    ),
  );
  void remove() {
    final e = selected;
    if (e == null || e.locked) return;
    change(
      value.copyWith(
        elements: value.elements.where((v) => v.id != e.id).toList(),
      ),
    );
    select(null);
  }

  void undo() {
    if (!canUndo) return;
    _redo.add(value);
    value = _undo.removeLast();
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(value);
    value = _redo.removeLast();
    notifyListeners();
  }
}
