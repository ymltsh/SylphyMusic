import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_updates.dart';

/// A project-focused About page with a hidden, music-themed constellation.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final Future<AppVersion> _version;

  @override
  void initState() {
    super.initState();
    _version = AppVersion.installed();
  }

  Future<void> _openLink(Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开链接，请稍后重试')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开链接，请检查设备上的浏览器')));
      }
    }
  }

  Future<void> _showConstellation() async {
    var releaseLine = '1.0';
    try {
      final version = await _version;
      releaseLine = version.version.split('.').take(2).join('.');
    } catch (_) {
      // The hidden sequence remains available if package metadata is absent.
    }
    if (!mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierColor: const Color(0xFF02050C),
      barrierDismissible: false,
      barrierLabel: '风灵音乐版本星图',
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, animation, secondaryAnimation) =>
          _LyraConstellationDialog(releaseLine: releaseLine),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('关于风灵音乐')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          scheme.primaryContainer.withValues(alpha: .82),
                          scheme.surfaceContainerHighest,
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    child: Column(
                      children: [
                        _AboutLogoEasterEgg(onUnlocked: _showConstellation),
                        const SizedBox(height: 18),
                        Text(
                          '风灵音乐',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'SYLPHY MUSIC',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: muted,
                                letterSpacing: 3.2,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '让音乐库回归简单，让每一首歌自由流动。',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(height: 1.55),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: const [
                            _AboutPill(
                              icon: Icons.library_music_outlined,
                              label: '多音源',
                            ),
                            _AboutPill(
                              icon: Icons.album_outlined,
                              label: '专注聆听',
                            ),
                            _AboutPill(icon: Icons.code_rounded, label: '开源项目'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '关于项目',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '风灵音乐是一款基于 Flutter 与 Material 3 的多音源音乐播放器。你可以连接 Emby、Navidrome、OpenSubsonic、WebDAV 或本地音乐，在同一个音乐库里浏览、管理歌单与聆听收藏。',
                          style: TextStyle(height: 1.65),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '为自己的音乐收藏留一片自由、安静的空间。',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: muted, height: 1.55),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _AboutSectionHeader(
                        title: '项目与社区',
                        subtitle: '了解项目、查看源码或获取更新',
                      ),
                      _linkTile(
                        icon: Icons.public_rounded,
                        title: '官方网站',
                        url: 'https://sylphy.ymltsh.com',
                        subtitle: 'sylphy.ymltsh.com',
                      ),
                      const Divider(height: 1, indent: 72, endIndent: 16),
                      _linkTile(
                        icon: Icons.code_rounded,
                        title: 'GitHub 源码仓库',
                        url: 'https://github.com/ymltsh/SylphyMusic',
                        subtitle: '查看源码、问题与贡献指南',
                      ),
                      const Divider(height: 1, indent: 72, endIndent: 16),
                      _linkTile(
                        icon: Icons.system_update_alt_rounded,
                        title: '版本发布与下载',
                        url: AppUpdates.releasePage,
                        subtitle: '查看最新版本与更新说明',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _AboutSectionHeader(title: '应用信息', subtitle: '版本与许可证'),
                      FutureBuilder<AppVersion>(
                        future: _version,
                        builder: (context, snapshot) => ListTile(
                          leading: const _AboutLeadingIcon(
                            icon: Icons.info_outline_rounded,
                          ),
                          title: const Text('当前版本'),
                          subtitle: Text(
                            snapshot.hasError
                                ? '暂时无法读取版本信息'
                                : snapshot.hasData
                                ? snapshot.data.toString()
                                : '正在读取版本…',
                          ),
                        ),
                      ),
                      const Divider(height: 1, indent: 72, endIndent: 16),
                      ListTile(
                        leading: const _AboutLeadingIcon(
                          icon: Icons.article_outlined,
                        ),
                        title: const Text('开源许可证'),
                        subtitle: const Text('查看本应用及依赖项的许可信息'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => showLicensePage(
                          context: context,
                          applicationName: '风灵音乐 · Sylphy Music',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  '一段旋律，也有自己的星轨。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: muted, letterSpacing: 1.1),
                ),
                const SizedBox(height: 6),
                Text(
                  'MADE WITH MUSIC & CURIOSITY',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: muted.withValues(alpha: .72),
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _linkTile({
    required IconData icon,
    required String title,
    required String url,
    required String subtitle,
  }) => ListTile(
    leading: _AboutLeadingIcon(icon: icon),
    title: Text(title),
    subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: const Icon(Icons.open_in_new_rounded, size: 20),
    onTap: () => _openLink(Uri.parse(url)),
  );
}

class _AboutLogoEasterEgg extends StatefulWidget {
  const _AboutLogoEasterEgg({required this.onUnlocked});

  final Future<void> Function() onUnlocked;

  @override
  State<_AboutLogoEasterEgg> createState() => _AboutLogoEasterEggState();
}

class _AboutLogoEasterEggState extends State<_AboutLogoEasterEgg> {
  static const _requiredTaps = 7;

  Timer? _resetTimer;
  var _tapCount = 0;
  var _unlocked = false;

  Future<void> _handleTap() async {
    if (_unlocked) return;
    _resetTimer?.cancel();
    setState(() => _tapCount++);
    if (_tapCount >= _requiredTaps) {
      _unlocked = true;
      try {
        await widget.onUnlocked();
      } finally {
        if (mounted) {
          setState(() {
            _tapCount = 0;
            _unlocked = false;
          });
        }
      }
      return;
    }
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _tapCount = 0);
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '风灵音乐图标，连续点击七次解锁隐藏星图',
      button: true,
      child: GestureDetector(
        key: const ValueKey('about-logo-easter-egg'),
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              key: ValueKey(_tapCount),
              duration: const Duration(milliseconds: 170),
              tween: Tween(begin: .88, end: 1),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Container(
                width: 100,
                height: 100,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surface.withValues(alpha: .68),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: .3),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: .16),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Image.asset('assets/icon.png', fit: BoxFit.contain),
              ),
            ),
            if (_tapCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '星图解锁 · $_tapCount / $_requiredTaps',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: scheme.primary, letterSpacing: 1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AboutPill extends StatelessWidget {
  const _AboutPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .64),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.primary),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _AboutSectionHeader extends StatelessWidget {
  const _AboutSectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class _AboutLeadingIcon extends StatelessWidget {
  const _AboutLeadingIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: Icon(icon, size: 20),
    );
  }
}

class _LyraConstellationDialog extends StatefulWidget {
  const _LyraConstellationDialog({required this.releaseLine});

  final String releaseLine;

  @override
  State<_LyraConstellationDialog> createState() =>
      _LyraConstellationDialogState();
}

class _LyraConstellationDialogState extends State<_LyraConstellationDialog>
    with TickerProviderStateMixin {
  late final AnimationController _revealController;
  late final AnimationController _ambientController;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6200),
    )..forward();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat();
  }

  double _reveal(double start, double end) => Interval(
    start,
    end,
    curve: Curves.easeOut,
  ).transform(_revealController.value);

  @override
  void dispose() {
    _revealController.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF030712),
    child: AnimatedBuilder(
      animation: Listenable.merge([_revealController, _ambientController]),
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _StarfieldPainter(
              revealProgress: _reveal(0, .28),
              ambientProgress: _ambientController.value,
            ),
          ),
          CustomPaint(
            painter: _LyraConstellationPainter(
              starProgress: _reveal(.24, .52),
              lineProgress: _reveal(.48, .76),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth > constraints.maxHeight;
                return Stack(
                  children: [
                    Align(
                      alignment: wide
                          ? Alignment.centerRight
                          : Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 64, 24, 28),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: wide ? constraints.maxWidth * .5 : 560,
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _FadeUp(
                                  progress: _reveal(.76, .84),
                                  child: Text(
                                    'VERSION CONSTELLATION  ·  ${widget.releaseLine}',
                                    style: const TextStyle(
                                      color: Color(0xFF8BD5FF),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 2.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _FadeUp(
                                  progress: _reveal(.81, .9),
                                  child: const Column(
                                    children: [
                                      Text(
                                        'LYRA',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                          letterSpacing: 8,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        '天琴座',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 40,
                                          fontWeight: FontWeight.w300,
                                          letterSpacing: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _FadeUp(
                                  progress: _reveal(.87, .96),
                                  child: const Text(
                                    '让每一段旋律，都拥有自己的星轨。',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xD9FFFFFF),
                                      fontSize: 15,
                                      height: 1.7,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _FadeUp(
                                  progress: _reveal(.93, 1),
                                  child: const Text(
                                    'SYLPHY MUSIC  ·  SOUND & STARDUST',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 9,
                                      letterSpacing: 1.8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 12,
                      child: IconButton(
                        tooltip: '关闭星图',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white60,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter({
    required this.revealProgress,
    required this.ambientProgress,
  });

  final double revealProgress;
  final double ambientProgress;

  static final _stars = _createStars();

  static List<_StarPoint> _createStars() {
    final random = math.Random(0x53594C50);
    return List.generate(
      180,
      (_) => _StarPoint(
        x: random.nextDouble(),
        y: random.nextDouble(),
        radius: .25 + random.nextDouble() * .95,
        phase: random.nextDouble() * math.pi * 2,
        alpha: .14 + random.nextDouble() * .42,
        depth: .3 + random.nextDouble() * .7,
      ),
      growable: false,
    );
  }

  double _wrap(double value, double limit) => ((value % limit) + limit) % limit;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF08172A), Color(0xFF030916), Color(0xFF02050D)],
        ).createShader(bounds),
    );

    final cycle = ambientProgress * math.pi * 2;
    for (final star in _stars) {
      final driftX = math.sin(cycle + star.phase) * 4 * star.depth;
      final driftY = math.cos(cycle * .7 + star.phase) * 3 * star.depth;
      final center = Offset(
        _wrap(star.x * size.width + driftX, size.width),
        _wrap(star.y * size.height + driftY, size.height),
      );
      final twinkle = .62 + .38 * ((math.sin(cycle * .7 + star.phase) + 1) / 2);
      final alpha = (revealProgress * star.alpha * twinkle)
          .clamp(0.0, 1.0)
          .toDouble();
      canvas.drawCircle(
        center,
        star.radius,
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter oldDelegate) =>
      revealProgress != oldDelegate.revealProgress ||
      ambientProgress != oldDelegate.ambientProgress;
}

class _StarPoint {
  const _StarPoint({
    required this.x,
    required this.y,
    required this.radius,
    required this.phase,
    required this.alpha,
    required this.depth,
  });

  final double x;
  final double y;
  final double radius;
  final double phase;
  final double alpha;
  final double depth;
}

class _LyraConstellationPainter extends CustomPainter {
  const _LyraConstellationPainter({
    required this.starProgress,
    required this.lineProgress,
  });

  final double starProgress;
  final double lineProgress;

  static const _stars = <Offset>[
    Offset(.72, .07),
    Offset(.53, .25),
    Offset(.30, .36),
    Offset(.36, .62),
    Offset(.62, .59),
    Offset(.55, .35),
  ];

  static const _links = <(int, int)>[
    (0, 1),
    (1, 2),
    (2, 3),
    (3, 4),
    (4, 5),
    (5, 1),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final wide = size.width > size.height;
    final field = Rect.fromCenter(
      center: Offset(
        size.width * (wide ? .25 : .5),
        size.height * (wide ? .5 : .28),
      ),
      width: math.min(size.width * (wide ? .44 : .78), 560).toDouble(),
      height: math.min(size.height * (wide ? .78 : .35), 310).toDouble(),
    );
    final points = _stars
        .map(
          (star) => Offset(
            field.left + star.dx * field.width,
            field.top + star.dy * field.height,
          ),
        )
        .toList(growable: false);

    final scaledStars = starProgress * points.length;
    for (var i = 0; i < points.length; i++) {
      final opacity = (scaledStars - i).clamp(0.0, 1.0).toDouble();
      if (opacity == 0) continue;
      final point = points[i];
      canvas.drawCircle(
        point,
        i == 0 ? 15 : 11,
        Paint()
          ..color = const Color(0xFF8BD5FF).withValues(alpha: .22 * opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawCircle(
        point,
        (i == 0 ? 3.6 : 2.4) * opacity,
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
    }

    final scaledLines = lineProgress * _links.length;
    final linePaint = Paint()
      ..color = const Color(0xCC8BD5FF)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < _links.length; i++) {
      final progress = (scaledLines - i).clamp(0.0, 1.0).toDouble();
      if (progress == 0) continue;
      final (from, to) = _links[i];
      canvas.drawLine(
        points[from],
        Offset.lerp(points[from], points[to], progress)!,
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LyraConstellationPainter oldDelegate) =>
      starProgress != oldDelegate.starProgress ||
      lineProgress != oldDelegate.lineProgress;
}

class _FadeUp extends StatelessWidget {
  const _FadeUp({required this.progress, required this.child});

  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: progress,
    child: Transform.translate(
      offset: Offset(0, 12 * (1 - progress)),
      child: child,
    ),
  );
}
