import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/recommendation_models.dart';
import 'cover_art.dart';
import 'letter_image.dart';
import 'recommendation_cover_layout.dart';

/// A layered display of actual cover art from a daily recommendation snapshot.
/// No generated artwork and no changes to playback or TrackRef identity.
class RecommendationCoverDeck extends StatefulWidget {
  const RecommendationCoverDeck({
    super.key,
    required this.app,
    required this.mix,
    required this.size,
    this.interaction = Offset.zero,
  });

  final SylphyApp app;
  final DailyMix mix;
  final double size;
  final Offset interaction;

  @override
  State<RecommendationCoverDeck> createState() =>
      _RecommendationCoverDeckState();
}

class _RecommendationCoverDeckState extends State<RecommendationCoverDeck>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );
  bool _foreground = true;
  bool _enabled = false;
  SylphyApp get app => widget.app;
  DailyMix get mix => widget.mix;
  double get size => widget.size;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enabled =
        TickerMode.of(context) && !MediaQuery.disableAnimationsOf(context);
    _syncMotion();
  }

  void _syncMotion() {
    if (_enabled && _foreground) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncMotion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep export geometry and UI card stack in sync.
    final chosen = RecommendationCoverLayout.select(
      mix.items.map((item) => item.track),
    );
    final visible = math.min(4, chosen.length);
    final coverSize = size * RecommendationCoverLayout.coverRatio;
    final scheme = Theme.of(context).colorScheme;
    final faces = <Widget>[
      for (var i = 0; i < visible; i++)
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .55),
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: .18),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: CoverArt(
            app: app,
            track: chosen[i],
            size: coverSize,
            borderRadius: 10,
          ),
        ),
    ];
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<Offset>(
        tween: Tween(end: _enabled ? widget.interaction : Offset.zero),
        duration: _enabled ? const Duration(milliseconds: 180) : Duration.zero,
        curve: Curves.easeOutCubic,
        builder: (context, touch, _) => AnimatedBuilder(
          animation: _motion,
          builder: (context, _) {
            final phase = _enabled ? _motion.value * math.pi * 2 : 0.0;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, .0012)
                ..rotateX(-touch.dy * .08)
                ..rotateY(touch.dx * .1),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < visible; i++)
                    Positioned(
                      left:
                          size *
                              (visible == 1
                                  ? .23
                                  : RecommendationCoverLayout.offsets[i].x) +
                          touch.dx * (i + 1) * 2.4,
                      top:
                          size *
                              (visible == 1
                                  ? .23
                                  : RecommendationCoverLayout.offsets[i].y) +
                          (_enabled
                              ? math.sin(phase + i * .9) * size * .012
                              : 0) +
                          touch.dy * (i + 1) * 1.9,
                      child: Transform.rotate(
                        angle:
                            (visible == 1
                                ? 0
                                : RecommendationCoverLayout.angles[i]) +
                            (_enabled ? math.sin(phase + i) * .018 : 0) +
                            touch.dx * (i + 1) * .018,
                        child: faces[i],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Shared home/detail feature card, inspired by the My Music Space deck.
/// The full variant places the cover deck beside the introduction on desktop,
/// and above it on narrow phones; track-specific explanations remain below.
class RecommendationShowcase extends StatefulWidget {
  const RecommendationShowcase({
    super.key,
    required this.app,
    required this.mix,
    this.detailed = false,
    this.onTap,
    this.onPlay,
    this.footerActions = const [],
    this.footerTrailingAction,
  });

  final SylphyApp app;
  final DailyMix mix;
  final bool detailed;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final List<Widget> footerActions;
  final Widget? footerTrailingAction;

  @override
  State<RecommendationShowcase> createState() => _RecommendationShowcaseState();
}

class _RecommendationShowcaseState extends State<RecommendationShowcase> {
  final _interaction = ValueNotifier<Offset>(Offset.zero);
  SylphyApp get app => widget.app;
  DailyMix get mix => widget.mix;
  bool get detailed => widget.detailed;
  VoidCallback? get onTap => widget.onTap;
  VoidCallback? get onPlay => widget.onPlay;
  List<Widget> get footerActions => widget.footerActions;

  void _follow(Offset position, BuildContext target) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    final box = target.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty) return;
    final point = box.globalToLocal(position);
    _interaction.value = Offset(
      (point.dx / box.size.width * 2 - 1).clamp(-1.0, 1.0).toDouble(),
      (point.dy / box.size.height * 2 - 1).clamp(-1.0, 1.0).toDouble(),
    );
  }

  @override
  void dispose() {
    _interaction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final intro = mix.introduction.trim().isEmpty
        ? '今天从你的音乐库挑出一些熟悉的旋律，也留一点空间给新的发现。'
        : mix.introduction.trim();

    Widget description() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (mix.llmSucceeded) ...[
          Icon(Icons.auto_awesome_rounded, color: scheme.primary, size: 26),
          const SizedBox(height: 10),
        ],
        Text(
          mix.title,
          style:
              (detailed
                      ? theme.textTheme.headlineSmall
                      : theme.textTheme.titleLarge)
                  ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        if (!detailed)
          Text(
            '${mix.items.length} 首 · ${mix.day}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 10),
        Text(
          intro,
          maxLines: detailed ? null : 3,
          overflow: detailed ? TextOverflow.visible : TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        if (detailed) ...[
          const SizedBox(height: 18),
          Text('信里提到的几首歌', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final item in mix.items.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                '${item.track.title} · ${item.reason}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 24),
          Divider(color: scheme.outlineVariant),
          const SizedBox(height: 14),
          Text(
            '你的音乐 · ${mix.items.length} 首 · ${mix.day}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );

    return Builder(
      builder: (target) => MouseRegion(
        onHover: (event) => _follow(event.position, target),
        onExit: (_) => _interaction.value = Offset.zero,
        child: Listener(
          onPointerDown: (event) => _follow(event.position, target),
          onPointerMove: (event) => _follow(event.position, target),
          onPointerUp: (_) => _interaction.value = Offset.zero,
          onPointerCancel: (_) => _interaction.value = Offset.zero,
          child: Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                      scheme.primary.withValues(alpha: .12),
                      scheme.surfaceContainerLow,
                    ),
                    Color.alphaBlend(
                      scheme.secondary.withValues(alpha: .17),
                      scheme.surfaceContainerLow,
                    ),
                    scheme.surfaceContainerLow,
                  ],
                ),
              ),
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsets.all(detailed ? 24 : 18),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 580;
                      final deckSize = detailed
                          ? (wide ? 238.0 : 192.0)
                          : (constraints.maxWidth * .34).clamp(96.0, 158.0);
                      final deck = Semantics(
                        label: '每日精选的多张歌曲封面',
                        image: true,
                        child: ExcludeSemantics(
                          child: ValueListenableBuilder<Offset>(
                            valueListenable: _interaction,
                            builder: (context, offset, _) =>
                                RecommendationCoverDeck(
                                  app: app,
                                  mix: mix,
                                  size: deckSize,
                                  interaction: offset,
                                ),
                          ),
                        ),
                      );
                      final Widget content;
                      if (detailed && !wide) {
                        content = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(child: deck),
                            const SizedBox(height: 16),
                            description(),
                          ],
                        );
                      } else {
                        content = Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (detailed) ...[deck, const SizedBox(width: 22)],
                            Expanded(child: description()),
                            if (!detailed) ...[const SizedBox(width: 6), deck],
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          content,
                          if (detailed) ...[
                            const SizedBox(height: 12),
                            LetterImageActions(
                              app: app,
                              day: mix.day,
                              title: mix.title,
                              content: intro,
                              tracks: mix.items
                                  .map((item) => item.track)
                                  .toList(),
                              trackCount: mix.items.length,
                              additionalActions: footerActions,
                              trailingAction: widget.footerTrailingAction,
                              detailsText: mix.items
                                  .take(3)
                                  .map(
                                    (item) =>
                                        '${item.track.title} · ${item.reason}',
                                  )
                                  .join('\n'),
                            ),
                          ] else ...[
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Wrap(
                                    spacing: 9,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        '查看这轮推荐',
                                        style: theme.textTheme.labelLarge,
                                      ),
                                      const Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 17,
                                      ),
                                    ],
                                  ),
                                ),
                                if (onPlay != null) ...[
                                  const SizedBox(width: 12),
                                  IconButton.filled(
                                    onPressed: onPlay,
                                    icon: const Icon(Icons.play_arrow_rounded),
                                    tooltip: '播放每日精选',
                                    iconSize: 22,
                                    style: IconButton.styleFrom(
                                      fixedSize: const Size.square(36),
                                      minimumSize: const Size.square(36),
                                      padding: const EdgeInsets.all(7),
                                      tapTargetSize:
                                          MaterialTapTargetSize.padded,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
