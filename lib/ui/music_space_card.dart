import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';
import 'music_source_ui.dart';

/// A source-management entry with a small, locally rendered brand-card deck.
class MusicSpaceCard extends StatefulWidget {
  const MusicSpaceCard({
    super.key,
    required this.sources,
    required this.playlistCount,
    required this.onTap,
  });

  final List<SourceProfile> sources;
  final int playlistCount;
  final VoidCallback onTap;

  @override
  State<MusicSpaceCard> createState() => _MusicSpaceCardState();
}

class _MusicSpaceCardState extends State<MusicSpaceCard>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..addStatusListener(_advance);
  Timer? _timer;
  int _index = 0;
  bool _visible = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    _syncTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncTimer();
  }

  @override
  void didUpdateWidget(MusicSpaceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the front card when a reload replaces the source list.
    final oldId = oldWidget.sources.isEmpty
        ? null
        : oldWidget.sources[_index % oldWidget.sources.length].id;
    final nextIndex = widget.sources.indexWhere((source) => source.id == oldId);
    _index = nextIndex < 0 ? 0 : nextIndex;
    _syncTimer();
  }

  void _syncTimer() {
    if (!_visible || !_foreground || widget.sources.length < 2) {
      _timer?.cancel();
      _timer = null;
      _motion.stop();
      _motion.reset();
      return;
    }
    _timer ??= Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && !_motion.isAnimating) _motion.forward(from: 0);
    });
  }

  void _advance(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {
      if (widget.sources.isNotEmpty)
        _index = (_index + 1) % widget.sources.length;
      _motion.reset();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sources = widget.sources;
    final current = sources.isEmpty ? null : sources[_index % sources.length];
    final next = sources.isEmpty
        ? null
        : sources[(_index + 1) % sources.length];
    final brand = current == null
        ? sourceBrandFor(SourceKind.local)
        : sourceBrandFor(current.kind, source: current);
    final nextBrand = next == null
        ? brand
        : sourceBrandFor(next.kind, source: next);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _motion,
        builder: (context, _) {
          final progress = Curves.easeInOutCubic.transform(_motion.value);
          final accent = Color.lerp(brand.color, nextBrand.color, progress)!;
          final secondary = Color.lerp(
            brand.secondary,
            nextBrand.secondary,
            progress,
          )!;
          Color tint(Color color, double opacity) => Color.alphaBlend(
            color.withValues(alpha: opacity),
            colors.surfaceContainerLow,
          );
          return Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    tint(accent, .10),
                    tint(secondary, .20),
                    tint(accent, .32),
                  ],
                ),
              ),
              child: InkWell(
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final deckWidth = (constraints.maxWidth * .36).clamp(
                        86.0,
                        156.0,
                      );
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.air_rounded,
                                  color: colors.onSurface,
                                  size: 30,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '我的音乐空间',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${widget.playlistCount} 个歌单 · ${sources.length} 个音乐来源',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        '管理音乐来源',
                                        style: theme.textTheme.labelLarge,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          ExcludeSemantics(
                            child: SizedBox(
                              width: deckWidth,
                              height: 146,
                              child: sources.isEmpty
                                  ? Center(
                                      child: Icon(
                                        Icons.library_music_outlined,
                                        size: 64,
                                        color: accent,
                                      ),
                                    )
                                  : _deck(
                                      sources,
                                      progress,
                                      deckWidth,
                                      colors,
                                      theme,
                                    ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _deck(
    List<SourceProfile> sources,
    double progress,
    double width,
    ColorScheme colors,
    ThemeData theme,
  ) {
    final visible = math.min(3, sources.length);
    final last = sources.length == 1 ? 0 : visible;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        for (var slot = last; slot >= 0; slot--)
          Builder(
            builder: (context) {
              final source = sources[(_index + slot) % sources.length];
              final brand = sourceBrandFor(source.kind, source: source);
              final depth = slot == 0 ? 0.0 : slot - progress;
              final leaving = slot == 0 && sources.length > 1;
              final opacity = leaving
                  ? 1 - progress
                  : (visible - depth).clamp(0.0, 1.0);
              return Opacity(
                opacity: opacity,
                child: Transform.translate(
                  offset: Offset(
                    depth * 7 + (leaving ? progress * 20 : 0),
                    -depth * 7 - (leaving ? progress * 22 : 0),
                  ),
                  child: Transform.rotate(
                    angle: (depth * .07) + (leaving ? progress * .16 : -.04),
                    child: Transform.scale(
                      scale: 1 - depth * .055,
                      child: Container(
                        width: width - 18,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            brand.color.withValues(alpha: .12),
                            colors.surfaceContainerLowest,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: brand.color.withValues(alpha: .22),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colors.shadow.withValues(alpha: .10),
                              blurRadius: 16,
                              offset: const Offset(0, 7),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MusicSourceIcon(
                              kind: source.kind,
                              source: source,
                              size: 50,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              source.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
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
          ),
      ],
    );
  }
}
