import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A reusable, dependency-free iPod-style Cover Flow for album and playlist
/// artwork. Only the current item and its neighbours are built, so callers can
/// keep their existing paged/virtualized data sources.
class CoverFlowView extends StatefulWidget {
  const CoverFlowView({
    super.key,
    required this.itemCount,
    required this.coverBuilder,
    required this.titleBuilder,
    required this.onActivate,
    this.subtitleBuilder,
    this.bottomPadding = 0,
    this.emptyMessage = '暂无内容',
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index, double size)
  coverBuilder;
  final String Function(int index) titleBuilder;
  final String Function(int index)? subtitleBuilder;
  final ValueChanged<int> onActivate;
  final double bottomPadding;
  final String emptyMessage;

  @override
  State<CoverFlowView> createState() => _CoverFlowViewState();
}

class _CoverFlowViewState extends State<CoverFlowView> {
  late final PageController _controller = PageController(viewportFraction: .32);

  @override
  void didUpdateWidget(covariant CoverFlowView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.itemCount != oldWidget.itemCount && widget.itemCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients || widget.itemCount == 0) {
          return;
        }
        final page = _controller.page ?? 0;
        final target = page.round().clamp(0, widget.itemCount - 1).toInt();
        if ((page - target).abs() > .01) _controller.jumpToPage(target);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    if (!_controller.hasClients || widget.itemCount == 0) return;
    final target = index.clamp(0, widget.itemCount - 1).toInt();
    unawaited(
      _controller.animateToPage(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) return Center(child: Text(widget.emptyMessage));

    return Padding(
      padding: EdgeInsets.only(bottom: widget.bottomPadding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 420.0;
          final coverSize = math
              .min(
                260.0,
                math.min(width * .58, math.max(120.0, (height - 110) * .58)),
              )
              .toDouble();
          final reflectionHeight = coverSize * .22;
          final artworkTop = math
              .max(8.0, (height - coverSize - reflectionHeight - 96) / 2)
              .toDouble();
          final desiredStep = coverSize * .76;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) {
              if (!_controller.hasClients) return;
              final position = _controller.position;
              final pageStep =
                  position.viewportDimension * _controller.viewportFraction;
              final scale = pageStep / desiredStep;
              final next = (_controller.offset - details.delta.dx * scale)
                  .clamp(position.minScrollExtent, position.maxScrollExtent)
                  .toDouble();
              _controller.jumpTo(next);
            },
            onHorizontalDragEnd: (details) {
              if (!_controller.hasClients) return;
              final page = _controller.page ?? 0;
              final velocity = details.primaryVelocity ?? 0;
              final projected = page - velocity / desiredStep * .12;
              _goToPage(projected.round());
            },
            onTapUp: (details) {
              final page = _controller.hasClients ? _controller.page ?? 0 : 0;
              final current = page
                  .round()
                  .clamp(0, widget.itemCount - 1)
                  .toInt();
              final relative =
                  (details.localPosition.dx - width / 2) / desiredStep;
              final target = (current + relative.round())
                  .clamp(0, widget.itemCount - 1)
                  .toInt();
              if (target == current) {
                widget.onActivate(current);
              } else {
                _goToPage(target);
              }
            },
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: widget.itemCount,
                      itemBuilder: (_, _) => const SizedBox.expand(),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final page = _controller.hasClients
                          ? (_controller.page ?? 0.0)
                                .clamp(0.0, (widget.itemCount - 1).toDouble())
                                .toDouble()
                          : 0.0;
                      final selected = page
                          .round()
                          .clamp(0, widget.itemCount - 1)
                          .toInt();
                      final first = math.max(0, page.floor() - 3).toInt();
                      final last = math
                          .min(widget.itemCount - 1, page.ceil() + 3)
                          .toInt();
                      final indices =
                          [
                            for (var index = first; index <= last; index++)
                              if ((index - page).abs() < 3.8) index,
                          ]..sort(
                            (a, b) =>
                                (b - page).abs().compareTo((a - page).abs()),
                          );

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (final index in indices)
                            _cover(
                              context,
                              index: index,
                              page: page,
                              width: width,
                              size: coverSize,
                              reflectionHeight: reflectionHeight,
                              top: artworkTop,
                              desiredStep: desiredStep,
                            ),
                          Positioned(
                            left: 18,
                            right: 18,
                            bottom: 12,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.titleBuilder(selected),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                if (widget.subtitleBuilder != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.subtitleBuilder!(selected),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ],
                                const SizedBox(height: 7),
                                Text(
                                  '${selected + 1} / ${widget.itemCount} · CoverFlow',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _cover(
    BuildContext context, {
    required int index,
    required double page,
    required double width,
    required double size,
    required double reflectionHeight,
    required double top,
    required double desiredStep,
  }) {
    final relative = index - page;
    final distance = relative.abs();
    final scale =
        (1 -
                .22 * distance.clamp(0.0, 1.0) -
                .06 * (distance - 1).clamp(0.0, 2.0))
            .clamp(.58, 1.0)
            .toDouble();
    final opacity = (3.8 - distance).clamp(0.0, 1.0).toDouble();
    final angle = -relative.clamp(-1.25, 1.25).toDouble() * .78;

    return Positioned(
      key: ValueKey('cover-flow-cover-$index'),
      left: width / 2 - size / 2 + relative * desiredStep,
      top: top,
      width: size,
      height: size + reflectionHeight,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .0018)
              ..scaleByDouble(scale, scale, 1, 1)
              ..rotateY(angle),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: size,
                  child: widget.coverBuilder(context, index, size),
                ),
                SizedBox(
                  width: size,
                  height: reflectionHeight,
                  child: ClipRect(
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (bounds) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x66FFFFFF), Color(0x00FFFFFF)],
                      ).createShader(bounds),
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minWidth: size,
                        maxWidth: size,
                        minHeight: size,
                        maxHeight: size,
                        child: Transform.flip(
                          flipY: true,
                          child: SizedBox.square(
                            dimension: size,
                            child: widget.coverBuilder(context, index, size),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
