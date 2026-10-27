import 'package:flutter/material.dart';

import '../services/lyrics.dart';

class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.text,
    required this.position,
    this.onSeek,
  });
  final String text;
  final Duration position;
  final ValueChanged<Duration>? onSeek;
  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final controller = ScrollController();
  late List<LrcLine> lines = parseLrc(widget.text);
  int active = -1;
  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      lines = parseLrc(widget.text);
      active = -1;
    }
    _update();
  }

  void _update() {
    final next = activeLrcIndex(lines, widget.position);
    if (next == active) return;
    active = next;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients || active < 0) return;
      final target =
          (active * 64.0 - controller.position.viewportDimension / 2 + 32)
              .clamp(0.0, controller.position.maxScrollExtent);
      controller.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return SingleChildScrollView(child: SelectableText(widget.text));
    }
    return ListView.builder(
      controller: controller,
      itemExtent: 64,
      itemCount: lines.length,
      itemBuilder: (context, index) => InkWell(
        onTap: widget.onSeek == null
            ? null
            : () => widget.onSeek!(lines[index].at),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
              color: index == active
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: index == active ? FontWeight.w700 : FontWeight.w400,
            ),
            child: Text(
              lines[index].text,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
