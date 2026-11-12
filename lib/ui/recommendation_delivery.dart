import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/recommendation_models.dart';
import '../services/recommendation_service.dart';

/// Presentation timing stays here; generation never waits for an animation.
class RecommendationDeliveryBuilder extends StatefulWidget {
  const RecommendationDeliveryBuilder({
    super.key,
    required this.future,
    required this.service,
    required this.builder,
    this.compact = false,
  });

  final Future<DailyMix> future;
  final RecommendationService service;
  final AsyncWidgetBuilder<DailyMix> builder;
  final bool compact;

  @override
  State<RecommendationDeliveryBuilder> createState() =>
      _RecommendationDeliveryBuilderState();
}

class _RecommendationDeliveryBuilderState
    extends State<RecommendationDeliveryBuilder> {
  AsyncSnapshot<DailyMix>? _result;
  Timer? _delay;
  int _epoch = 0;
  bool _visible = false;
  int? _arrival;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void didUpdateWidget(RecommendationDeliveryBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.future != widget.future) _watch();
  }

  void _watch() {
    final epoch = ++_epoch;
    _delay?.cancel();
    _result = null;
    _arrival = null;
    _visible = false;
    // Reopening a cached letter should not play the entire delivery story.
    _delay = Timer(const Duration(milliseconds: 180), () {
      if (mounted && epoch == _epoch) setState(() => _visible = true);
    });
    widget.future.then(
      (mix) async {
        if (!mounted || epoch != _epoch) return;
        _delay?.cancel();
        if (_visible &&
            mix.items.isNotEmpty &&
            !MediaQuery.disableAnimationsOf(context)) {
          setState(() => _arrival = 4);
          await Future<void>.delayed(const Duration(milliseconds: 420));
          if (!mounted || epoch != _epoch) return;
          setState(() => _arrival = 5);
          await Future<void>.delayed(const Duration(milliseconds: 520));
          if (!mounted || epoch != _epoch) return;
        }
        setState(
          () => _result = AsyncSnapshot.withData(ConnectionState.done, mix),
        );
      },
      onError: (Object error, StackTrace stack) {
        if (!mounted || epoch != _epoch) return;
        _delay?.cancel();
        setState(
          () => _result = AsyncSnapshot.withError(
            ConnectionState.done,
            error,
            stack,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    ++_epoch;
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_result != null) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(
          milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 240,
        ),
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity, child: child),
        child: widget.builder(context, _result!),
      );
    }
    final content = !_visible
        ? const SizedBox(height: 176)
        : ValueListenableBuilder<DailyLetterStage>(
            valueListenable: widget.service.dailyStage,
            builder: (context, stage, _) => _LetterJourney(
              stage: _arrival ?? stage.index,
              compact: widget.compact,
            ),
          );
    return widget.compact
        ? content
        : Center(child: SingleChildScrollView(child: content));
  }
}

class _LetterJourney extends StatefulWidget {
  const _LetterJourney({required this.stage, required this.compact});
  final int stage;
  final bool compact;

  @override
  State<_LetterJourney> createState() => _LetterJourneyState();
}

class _LetterJourneyState extends State<_LetterJourney>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );
  final _clock = Stopwatch()..start();
  Timer? _timer;
  int _seconds = 0;
  bool _foreground = true;
  bool _animate = false;

  static const _titles = [
    '可以为我推荐几首歌吗？',
    '笔友正在翻找唱片',
    '把想分享的，慢慢写成信',
    '装好歌曲，封上一点心意',
    '来信正乘着风赶来',
    '拆开信封，音乐在里面',
  ];
  static const _details = [
    '一张小纸条，开启今天的音乐来往',
    '从你的曲库里，挑一些熟悉与意外',
    '选好的歌，正在变成几句想对你说的话',
    '整理这封信，也收好这一轮的歌',
    '下一站，就是你的耳边',
    '愿这里有一首，恰好合你心意',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_foreground && mounted)
        setState(() => _seconds = _clock.elapsed.inSeconds);
    });
  }

  @override
  void didUpdateWidget(_LetterJourney oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stage != widget.stage) {
      _clock.reset();
      _seconds = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate =
        TickerMode.of(context) && !MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  void _sync() {
    if (_animate && _foreground) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _clock.stop();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final stage = widget.stage;
    final slow = _seconds >= 18 && stage < 3;
    return Semantics(
      liveRegion: true,
      label: _titles[stage],
      child: ExcludeSemantics(
        child: Container(
          width: widget.compact ? double.infinity : 420,
          margin: EdgeInsets.all(widget.compact ? 0 : 24),
          padding: EdgeInsets.symmetric(
            horizontal: 24,
            vertical: widget.compact ? 20 : 32,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: .4),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(end: stage == 5 ? 1.0 : 0.0),
                duration: Duration(milliseconds: _animate ? 480 : 0),
                builder: (context, opening, _) => SizedBox(
                  height: widget.compact ? 100 : 152,
                  width: 240,
                  child: CustomPaint(
                    painter: _LetterPainter(
                      motion: _motion,
                      stage: stage,
                      opening: opening,
                      primary: colors.primary,
                      paper: colors.surface,
                      tint: colors.primaryContainer,
                      ink: colors.onPrimaryContainer,
                      moving: _animate && _foreground,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: Duration(milliseconds: _animate ? 250 : 0),
                child: Text(
                  _titles[stage],
                  key: ValueKey(stage),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                slow
                    ? (stage == 2 ? '这封信还在写，稍等一会儿就好' : '还在认真挑选，曲库里的惊喜值得找一找')
                    : _details[stage],
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  final current = math.min(stage, 4);
                  return AnimatedContainer(
                    duration: Duration(milliseconds: _animate ? 300 : 0),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: index == current ? 24 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: index <= current
                          ? colors.primary
                          : colors.outlineVariant.withValues(alpha: .5),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LetterPainter extends CustomPainter {
  _LetterPainter({
    required this.motion,
    required this.stage,
    required this.opening,
    required this.primary,
    required this.paper,
    required this.tint,
    required this.ink,
    required this.moving,
  }) : super(repaint: motion);
  final Animation<double> motion;
  final int stage;
  final double opening;
  final Color primary, paper, tint, ink;
  final bool moving;

  @override
  void paint(Canvas canvas, Size size) {
    final t = moving ? motion.value * math.pi * 2 : 0.0;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2 + 8);
    final wave = math.sin(t);
    // A few musical notes drift around the same little envelope throughout.
    for (var i = 0; i < 3; i++) {
      final x = -87.0 + i * 84;
      final y = -32.0 - (i % 2) * 17 + math.sin(t + i * 2) * 5;
      final p = Paint()..color = primary.withValues(alpha: .22);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: 7, height: 5),
        p,
      );
      canvas.drawLine(
        Offset(x + 3, y),
        Offset(x + 3, y - 12),
        Paint()
          ..color = p.color
          ..strokeWidth = 1.5,
      );
    }
    if (stage == 1) {
      for (var i = 2; i >= 0; i--) {
        canvas.save();
        canvas.translate((i - 1) * 24.0, -4 + math.sin(t + i) * 4);
        canvas.rotate((i - 1) * .16);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-33, -32, 66, 66),
            const Radius.circular(8),
          ),
          Paint()
            ..color = i == 0 ? tint : primary.withValues(alpha: .12 + i * .08),
        );
        canvas.drawCircle(Offset.zero, 22, Paint()..color = paper);
        canvas.drawCircle(Offset.zero, 7, Paint()..color = primary);
        canvas.drawCircle(Offset.zero, 2, Paint()..color = paper);
        canvas.restore();
      }
    } else {
      canvas.translate(stage == 4 ? wave * 15 : 0, wave * (stage == 4 ? 5 : 2));
      canvas.rotate(stage == 4 ? -.09 + math.sin(t) * .04 : math.sin(t) * .015);
      if (stage == 4) {
        for (var i = 0; i < 3; i++) {
          canvas.drawLine(
            Offset(-96 - i * 4.0, -15 + i * 15.0),
            Offset(-68, -15 + i * 15.0),
            Paint()
              ..color = primary.withValues(alpha: .25)
              ..strokeWidth = 2
              ..strokeCap = StrokeCap.round,
          );
        }
      }
      final flap = Path()
        ..moveTo(-57, -23)
        ..lineTo(0, -23 - opening * 42)
        ..lineTo(57, -23)
        ..close();
      canvas.drawPath(flap, Paint()..color = tint);
      final lift = stage == 2 || stage == 0 ? 20.0 : opening * 34;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-46, -29 - lift, 92, 61),
          const Radius.circular(5),
        ),
        Paint()..color = paper,
      );
      for (var i = 0; i < 3; i++) {
        final length = stage == 2 && moving
            ? 22 + ((motion.value + i * .28) % 1) * 36
            : 50.0;
        canvas.drawLine(
          Offset(-30, -15 - lift + i * 9),
          Offset(-30 + length, -15 - lift + i * 9),
          Paint()
            ..color = primary.withValues(alpha: .28)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-58, -23, 116, 70),
          const Radius.circular(9),
        ),
        Paint()..color = tint,
      );
      final folds = Path()
        ..moveTo(-55, 43)
        ..lineTo(0, 6)
        ..lineTo(55, 43)
        ..moveTo(-55, -19)
        ..lineTo(0, 18)
        ..lineTo(55, -19);
      canvas.drawPath(
        folds,
        Paint()
          ..color = primary.withValues(alpha: .25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      canvas.drawCircle(const Offset(0, 17), 8, Paint()..color = primary);
      canvas.drawLine(
        const Offset(-3, 17),
        const Offset(3, 17),
        Paint()
          ..color = paper
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
      if (stage == 2) {
        canvas.save();
        canvas.translate(30 + wave * 12, -39 + math.cos(t * 2) * 3);
        canvas.rotate(.55);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-3, -21, 6, 35),
            const Radius.circular(2),
          ),
          Paint()..color = primary,
        );
        canvas.drawPath(
          Path()
            ..moveTo(-3, 14)
            ..lineTo(0, 22)
            ..lineTo(3, 14)
            ..close(),
          Paint()..color = ink,
        );
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LetterPainter oldDelegate) =>
      stage != oldDelegate.stage ||
      opening != oldDelegate.opening ||
      primary != oldDelegate.primary ||
      paper != oldDelegate.paper ||
      tint != oldDelegate.tint ||
      ink != oldDelegate.ink ||
      moving != oldDelegate.moving;
}
