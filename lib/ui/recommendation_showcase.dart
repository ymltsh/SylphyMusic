import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/recommendation_models.dart';
import 'cover_art.dart';
import 'letter_image.dart';

/// A layered display of actual cover art from a daily recommendation snapshot.
/// No generated artwork and no changes to playback or TrackRef identity.
class RecommendationCoverDeck extends StatelessWidget {
  const RecommendationCoverDeck({
    super.key,
    required this.app,
    required this.mix,
    required this.size,
  });

  final SylphyApp app;
  final DailyMix mix;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Prefer distinct albums so adjacent cards do not repeat one cover.
    final chosen = <RecommendedTrack>[];
    final albums = <String>{};
    for (final item in mix.items) {
      if (albums.add('${item.track.ref.sourceId}:${item.track.albumGroup}')) {
        chosen.add(item);
      }
      if (chosen.length >= 4) break;
    }
    if (chosen.length < 4) {
      final refs = chosen.map((item) => item.track.ref.key).toSet();
      for (final item in mix.items) {
        if (refs.add(item.track.ref.key)) chosen.add(item);
        if (chosen.length >= 4) break;
      }
    }
    final visible = math.min(4, chosen.length);
    const offsets = [
      Offset(.33, .03),
      Offset(.04, .22),
      Offset(.40, .25),
      Offset(.18, .42),
    ];
    const angles = [.13, -.12, .10, -.06];
    final coverSize = size * .54;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < visible; i++)
            Positioned(
              left: size * (visible == 1 ? .23 : offsets[i].dx),
              top: size * (visible == 1 ? .23 : offsets[i].dy),
              child: Transform.rotate(
                angle: visible == 1 ? 0 : angles[i],
                child: Container(
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
                    track: chosen[i].track,
                    size: coverSize,
                    borderRadius: 10,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shared home/detail feature card, inspired by the My Music Space deck.
/// The full variant places the cover deck beside the introduction on desktop,
/// and above it on narrow phones; track-specific explanations remain below.
class RecommendationShowcase extends StatelessWidget {
  const RecommendationShowcase({
    super.key,
    required this.app,
    required this.mix,
    this.detailed = false,
    this.onTap,
    this.onPlay,
  });

  final SylphyApp app;
  final DailyMix mix;
  final bool detailed;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;

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
        Icon(Icons.auto_awesome_rounded, color: scheme.primary, size: 26),
        const SizedBox(height: 10),
        Text(
          detailed ? '写给你的今日音乐信' : '今天，有一封音乐来信',
          style:
              (detailed
                      ? theme.textTheme.headlineSmall
                      : theme.textTheme.titleLarge)
                  ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
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
          LetterImageActions(day: mix.day, content: intro),
          const SizedBox(height: 14),
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
        ] else ...[
          const SizedBox(height: 9),
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('查看这轮推荐', style: theme.textTheme.labelLarge),
              const SizedBox(width: 5),
              const Icon(Icons.arrow_forward_rounded, size: 17),
              if (onPlay != null) ...[
                const SizedBox(width: 7),
                IconButton(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_circle_fill_rounded),
                  tooltip: '播放每日精选',
                  iconSize: 27,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
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
                    child: RecommendationCoverDeck(
                      app: app,
                      mix: mix,
                      size: deckSize,
                    ),
                  ),
                );
                if (detailed && !wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: deck),
                      const SizedBox(height: 16),
                      description(),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (detailed) ...[deck, const SizedBox(width: 22)],
                    Expanded(child: description()),
                    if (!detailed) ...[const SizedBox(width: 6), deck],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
