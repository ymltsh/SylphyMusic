import 'package:flutter/material.dart';

/// Keeps its angle when paused and does no work when hidden or motion is off.
class RotatingCover extends StatefulWidget {
  const RotatingCover({
    super.key,
    required this.enabled,
    required this.playing,
    required this.child,
  });
  final bool enabled, playing;
  final Widget child;
  @override
  State<RotatingCover> createState() => _RotatingCoverState();
}

class _RotatingCoverState extends State<RotatingCover>
    with SingleTickerProviderStateMixin {
  late final motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  );
  void _sync() {
    final enabled = widget.enabled && !MediaQuery.disableAnimationsOf(context);
    if (!enabled) {
      motion.stop();
      if (motion.value != 0) motion.value = 0;
    } else if (widget.playing && TickerMode.valuesOf(context).enabled) {
      if (!motion.isAnimating) motion.repeat();
    } else {
      motion.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(RotatingCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RotationTransition(turns: motion, child: widget.child);
}
