import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'recommendation_cover_layout.dart';

/// Personal export preferences live in existing AppDb settings, not the letter
/// archive or the technical diagnostic log.
class LetterExportOptions {
  const LetterExportOptions({
    this.covers = true,
    this.reasons = true,
    this.theme = 'app',
    this.width = 1080,
  });

  final bool covers;
  final bool reasons;
  final String theme; // app / light / dark
  final int width; // 1080 / 1440

  static Future<LetterExportOptions> load(SylphyApp app) async {
    final db = app.db;
    final theme = await db.setting('letter_export_theme') ?? 'app';
    return LetterExportOptions(
      covers: await db.setting('letter_export_covers') != 'false',
      reasons: await db.setting('letter_export_reasons') != 'false',
      theme: const ['app', 'light', 'dark'].contains(theme) ? theme : 'app',
      width: await db.setting('letter_export_width') == '1440' ? 1440 : 1080,
    );
  }

  Future<void> save(SylphyApp app) async {
    await app.db.db.transaction((tx) async {
      for (final entry in <String, String>{
        'letter_export_covers': covers.toString(),
        'letter_export_reasons': reasons.toString(),
        'letter_export_theme': theme,
        'letter_export_width': width.toString(),
      }.entries) {
        await tx.rawInsert(
          'INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)',
          [entry.key, entry.value],
        );
      }
    });
  }
}

/// Paints the entire letter independently from the viewport. The cover art
/// selection, normalized positions and rotations are shared with the app UI.
class LetterImage {
  static Future<Uint8List> render({
    required String day,
    required String title,
    required String content,
    required String detailsText,
    required int trackCount,
    required List<Uint8List?> coverBytes,
    required LetterExportOptions options,
    required ColorScheme scheme,
  }) async {
    const layoutWidth = 1080.0;
    const margin = 76.0;
    final textColor = scheme.onSurface;
    final secondaryText = scheme.onSurfaceVariant;
    final accent = scheme.primary;
    final cardBase = scheme.surfaceContainerLow;
    final intro = content.trim();
    TextPainter painter(
      String value,
      double size, {
      FontWeight weight = FontWeight.normal,
      Color? color,
      double height = 1.48,
    }) => TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: size,
          fontWeight: weight,
          height: height,
          color: color ?? textColor,
          fontFamilyFallback: const ['Noto Sans CJK SC', 'Microsoft YaHei'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: layoutWidth - margin * 2);

    final headline = painter(title, 53, weight: FontWeight.w700, height: 1.25);
    final body = painter(intro, 35, height: 1.77);
    final details = options.reasons && detailsText.trim().isNotEmpty
        ? painter(detailsText.trim(), 27, color: secondaryText, height: 1.65)
        : null;
    final displayCovers = options.covers && coverBytes.isNotEmpty;
    final deckSize = displayCovers ? 470.0 : 0.0;
    const topMetaY = 100.0;
    final deckTop = displayCovers ? 163.0 : 0.0;
    final titleY = displayCovers ? deckTop + deckSize + 42 : 174.0;
    final sublineY = titleY + headline.height + 17;
    final bodyY = sublineY + 28;
    final detailsHeadY = details == null ? 0.0 : bodyY + body.height + 58;
    final detailsY = details == null ? 0.0 : detailsHeadY + 59;
    final endOfContent = details == null
        ? bodyY + body.height
        : detailsY + details.height;
    final footerY = endOfContent + 106;
    final layoutHeight = (footerY + 160).ceilToDouble();
    final scale = options.width / layoutWidth;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    final backdrop = Rect.fromLTWH(0, 0, layoutWidth, layoutHeight);
    canvas.drawRect(backdrop, Paint()..color = scheme.surface);
    final card = RRect.fromRectAndRadius(
      Rect.fromLTWH(28, 28, layoutWidth - 56, layoutHeight - 56),
      const Radius.circular(50),
    );
    canvas.drawRRect(
      card,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(40, 40),
          Offset(layoutWidth, layoutHeight),
          [
            Color.alphaBlend(accent.withValues(alpha: .12), cardBase),
            Color.alphaBlend(scheme.secondary.withValues(alpha: .17), cardBase),
            cardBase,
          ],
          const [0, .50, 1],
        ),
    );
    final heading = painter('写给你的音乐 · 每日精选', 25, color: accent);
    heading.paint(canvas, const Offset(margin, topMetaY));
    heading.dispose();

    final resolvedImages = <ui.Image>[];
    try {
      if (displayCovers) {
        final artSize = deckSize * RecommendationCoverLayout.coverRatio;
        final deckLeft = (layoutWidth - deckSize) / 2;
        for (var i = 0; i < coverBytes.length && i < 4; i++) {
          ui.Image? artwork;
          final bytes = coverBytes[i];
          if (bytes != null) {
            try {
              final codec = await ui.instantiateImageCodec(
                bytes,
                targetWidth: 620,
              );
              artwork = (await codec.getNextFrame()).image;
              codec.dispose();
              resolvedImages.add(artwork);
            } catch (_) {
              artwork = null;
            }
          }
          final offset = RecommendationCoverLayout.offsets[i];
          final positionX = coverBytes.length == 1 ? .23 : offset.x;
          final positionY = coverBytes.length == 1 ? .23 : offset.y;
          final angle = coverBytes.length == 1
              ? 0.0
              : RecommendationCoverLayout.angles[i];
          final cx = deckLeft + deckSize * positionX + artSize / 2;
          final cy = deckTop + deckSize * positionY + artSize / 2;
          canvas.save();
          canvas.translate(cx, cy);
          canvas.rotate(angle);
          canvas.translate(-artSize / 2, -artSize / 2);
          final outer = RRect.fromRectAndRadius(
            Rect.fromLTWH(-5, -5, artSize + 10, artSize + 10),
            const Radius.circular(24),
          );
          canvas.drawShadow(
            Path()..addRRect(outer),
            scheme.shadow.withValues(alpha: .28),
            13,
            false,
          );
          canvas.drawRRect(outer, Paint()..color = scheme.surface);
          final inner = RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, artSize, artSize),
            const Radius.circular(18),
          );
          canvas.save();
          canvas.clipRRect(inner);
          if (artwork != null) {
            final sourceSize = artwork.width < artwork.height
                ? artwork.width.toDouble()
                : artwork.height.toDouble();
            final sx = (artwork.width - sourceSize) / 2;
            final sy = (artwork.height - sourceSize) / 2;
            canvas.drawImageRect(
              artwork,
              Rect.fromLTWH(sx, sy, sourceSize, sourceSize),
              Rect.fromLTWH(0, 0, artSize, artSize),
              Paint()..filterQuality = FilterQuality.high,
            );
          } else {
            canvas.drawRRect(inner, Paint()..color = scheme.secondaryContainer);
            final note = painter('♪', 74, color: scheme.onSecondaryContainer);
            note.paint(canvas, Offset(artSize / 2 - 32, artSize / 2 - 57));
            note.dispose();
          }
          canvas.restore();
          canvas.restore();
        }
      }

      headline.paint(canvas, Offset(margin, titleY));
      body.paint(canvas, Offset(margin, bodyY));
      if (details != null) {
        final subtitle = painter('信里提到的几首歌', 31, weight: FontWeight.w600);
        subtitle.paint(canvas, Offset(margin, detailsHeadY));
        subtitle.dispose();
        details.paint(canvas, Offset(margin, detailsY));
      }
      canvas.drawLine(
        Offset(margin, footerY - 25),
        Offset(layoutWidth - margin, footerY - 25),
        Paint()
          ..color = scheme.outlineVariant
          ..strokeWidth = 2,
      );
      final data = await rootBundle.load('assets/icon.png');
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        targetWidth: 128,
      );
      final logo = (await codec.getNextFrame()).image;
      codec.dispose();
      resolvedImages.add(logo);
      canvas.drawImageRect(
        logo,
        Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        Rect.fromLTWH(margin, footerY + 5, 68, 68),
        Paint()..filterQuality = FilterQuality.high,
      );
      final branding = painter(
        '风灵音乐 · Sylphy Music',
        26,
        weight: FontWeight.w600,
      );
      branding.paint(canvas, Offset(margin + 92, footerY + 8));
      branding.dispose();
      final closing = painter(
        '你的音乐 · $trackCount 首 · $day',
        23,
        color: secondaryText,
      );
      closing.paint(canvas, Offset(margin + 92, footerY + 49));
      closing.dispose();

      final picture = recorder.endRecording();
      final image = await picture.toImage(
        options.width,
        (layoutHeight * scale).ceil(),
      );
      picture.dispose();
      try {
        final result = await image.toByteData(format: ui.ImageByteFormat.png);
        if (result == null) throw StateError('无法生成图片');
        return result.buffer.asUint8List(
          result.offsetInBytes,
          result.lengthInBytes,
        );
      } finally {
        image.dispose();
      }
    } finally {
      headline.dispose();
      body.dispose();
      details?.dispose();
      for (final img in resolvedImages) {
        img.dispose();
      }
    }
  }

  static Future<String> save(Uint8List bytes, String day) async {
    final date = day.replaceAll(RegExp(r'[^0-9-]'), '');
    final name =
        'SylphyMusic-letter-$date-${DateTime.now().microsecondsSinceEpoch}.png';
    if (Platform.isAndroid) {
      return await const MethodChannel('music.sylphy/letter_images')
              .invokeMethod<String>('save', {'name': name, 'bytes': bytes}) ??
          (throw StateError('图片保存未完成'));
    }
    if (Platform.isWindows) {
      final path = await const MethodChannel('music.sylphy/desktop')
          .invokeMethod<String>('picturesPath');
      if (path == null || path.isEmpty) throw StateError('无法找到 Pictures 目录');
      final dir = await Directory(p.join(path, 'SylphyMusic'))
          .create(recursive: true);
      final file = File(p.join(dir.path, name));
      try {
        await file.writeAsBytes(bytes, flush: true);
      } catch (_) {
        if (await file.exists()) await file.delete();
        rethrow;
      }
      return file.path;
    }
    throw UnsupportedError('当前平台暂不支持保存音乐信图片');
  }
}

/// Export actions intentionally come after the full letter and its song notes.
class LetterImageActions extends StatefulWidget {
  const LetterImageActions({
    super.key,
    required this.app,
    required this.day,
    required this.title,
    required this.content,
    required this.tracks,
    this.detailsText = '',
    this.trackCount = 0,
    this.additionalActions = const [],
    this.trailingAction,
  });

  final SylphyApp app;
  final String day;
  final String title;
  final String content;
  final String detailsText;
  final List<Track> tracks;
  final int trackCount;
  final List<Widget> additionalActions;
  final Widget? trailingAction;

  @override
  State<LetterImageActions> createState() => _LetterImageActionsState();
}

class _LetterImageActionsState extends State<LetterImageActions> {
  bool _busy = false;
  Future<({LetterExportOptions options, bool share})?> _chooseOptions() async {
    final options = await LetterExportOptions.load(widget.app);
    if (!mounted) return null;
    var covers = options.covers;
    var reasons = options.reasons;
    var theme = options.theme;
    var width = options.width;
    var share = false;
    return showDialog<({LetterExportOptions options, bool share})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('导出音乐信'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.photo_library_outlined),
                    title: Text(Platform.isAndroid ? '默认保存到相册' : '默认保存到图片目录'),
                    subtitle: const Text('Pictures/SylphyMusic'),
                  ),
                  SwitchListTile(
                    title: const Text('音乐封面叠卡'),
                    subtitle: const Text('与 App 内使用相同封面、位置和旋转角度'),
                    value: covers,
                    onChanged: (v) => update(() => covers = v),
                  ),
                  SwitchListTile(
                    title: const Text('附上推荐理由'),
                    subtitle: const Text('在正文后显示信里提到的歌曲'),
                    value: reasons,
                    onChanged: (v) => update(() => reasons = v),
                  ),
                  ListTile(
                    title: const Text('图片主题'),
                    trailing: DropdownButton<String>(
                      value: theme,
                      onChanged: (v) => update(() => theme = v ?? 'app'),
                      items: const [
                        DropdownMenuItem(value: 'app', child: Text('跟随应用')),
                        DropdownMenuItem(value: 'light', child: Text('浅色')),
                        DropdownMenuItem(value: 'dark', child: Text('深色')),
                      ],
                    ),
                  ),
                  ListTile(
                    title: const Text('图片清晰度'),
                    trailing: DropdownButton<int>(
                      value: width,
                      onChanged: (v) => update(() => width = v ?? 1080),
                      items: const [
                        DropdownMenuItem(value: 1080, child: Text('1080 px')),
                        DropdownMenuItem(value: 1440, child: Text('1440 px')),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('保存后分享'),
                    subtitle: const Text('保存成功后打开系统分享面板'),
                    value: share,
                    onChanged: (value) => update(() => share = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (
                options: LetterExportOptions(
                  covers: covers,
                  reasons: reasons,
                  theme: theme,
                  width: width,
                ),
                share: share,
              )),
              child: const Text('导出并保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export() async {
    if (_busy || widget.content.trim().isEmpty) return;
    setState(() => _busy = true);
    var saved = false;
    try {
      final chosen = await _chooseOptions();
      if (chosen == null || !mounted) return;
      final options = chosen.options;
      final share = chosen.share;
      await options.save(widget.app);
      if (!mounted) return;
      final renderBox = context.findRenderObject() as RenderBox?;
      final origin = renderBox == null
          ? null
          : renderBox.localToGlobal(Offset.zero) & renderBox.size;
      final appTheme = Theme.of(context);
      final scheme = options.theme == 'app'
          ? appTheme.colorScheme
          : ColorScheme.fromSeed(
              seedColor: appTheme.colorScheme.primary,
              brightness: options.theme == 'dark'
                  ? Brightness.dark
                  : Brightness.light,
            );
      final day = widget.day;
      final title = widget.title;
      final content = widget.content;
      final details = widget.detailsText;
      final count = widget.trackCount;
      final covers = RecommendationCoverLayout.select(widget.tracks);
      final bytes = <Uint8List?>[];
      if (options.covers) {
        for (final track in covers) {
          try {
            final file = await widget.app.artwork.load(track);
            if (file == null || await file.length() > 8 * 1024 * 1024) {
              bytes.add(null);
            } else {
              bytes.add(await file.readAsBytes());
            }
          } catch (_) {
            bytes.add(null);
          }
        }
      }
      final image = await LetterImage.render(
        day: day,
        title: title,
        content: content,
        detailsText: details,
        trackCount: count,
        coverBytes: bytes,
        options: options,
        scheme: scheme,
      );
      final location = await LetterImage.save(image, day);
      saved = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('图片已保存：$location')));
      if (share) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(image, mimeType: 'image/png')],
            fileNameOverrides: ['SylphyMusic-letter-${day}.png'],
            title: title,
            sharePositionOrigin: origin,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(saved ? '图片已保存，暂时无法打开分享面板' : '图片导出失败，请检查存储权限和图片目录'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _guard(Widget child) => IgnorePointer(
    ignoring: _busy,
    child: Opacity(opacity: _busy ? .5 : 1, child: child),
  );

  @override
  Widget build(BuildContext context) {
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: _busy || widget.content.trim().isEmpty ? null : _export,
          icon: const Icon(Icons.ios_share_rounded),
          label: Text(_busy ? '正在导出…' : '导出'),
        ),
        for (final action in widget.additionalActions) _guard(action),
      ],
    );
    if (widget.trailingAction == null) return actions;
    return Row(
      children: [
        Expanded(child: actions),
        const SizedBox(width: 8),
        _guard(widget.trailingAction!),
      ],
    );
  }
}
