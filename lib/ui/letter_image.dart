import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

/// A complete letter image, independent of the visible viewport or scroll state.
class LetterImage {
  static Future<Uint8List> render(String day, String content) async {
    const width = 1080.0;
    const ink = Color(0xff303c37);
    final body = TextPainter(
      text: TextSpan(
        text: content.trim(),
        style: const TextStyle(
          color: ink,
          fontSize: 34,
          height: 1.85,
          fontFamilyFallback: ['Microsoft YaHei', 'Noto Sans CJK SC'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 888);
    final height = (body.height + 480).ceil();
    final data = await rootBundle.load('assets/icon.png');
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      targetWidth: 128,
    );
    final logo = (await codec.getNextFrame()).image;
    codec.dispose();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    void text(
      String value,
      double x,
      double y,
      double size, {
      Color color = ink,
      FontWeight weight = FontWeight.normal,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(color: color, fontSize: size, fontWeight: weight),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width - x - 72);
      painter.paint(canvas, Offset(x, y));
      painter.dispose();
    }

    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height.toDouble()),
      Paint()..color = const Color(0xfff2eee4),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(32, 32, 1016, height - 64.0),
        const Radius.circular(30),
      ),
      Paint()..color = const Color(0xfffffcf5),
    );
    text(
      'A LETTER FROM YOUR MUSIC',
      96,
      94,
      21,
      color: const Color(0xff8a7961),
    );
    text('写给你的今日音乐信', 96, 138, 52, weight: FontWeight.w600);
    canvas.drawLine(
      const Offset(96, 226),
      const Offset(984, 226),
      Paint()
        ..color = const Color(0xffd8cbb7)
        ..strokeWidth = 2,
    );
    body.paint(canvas, const Offset(96, 264));
    body.dispose();
    final footer = height - 152.0;
    canvas.drawLine(
      Offset(96, footer - 24),
      Offset(984, footer - 24),
      Paint()..color = const Color(0xffd8cbb7),
    );
    canvas.drawImageRect(
      logo,
      Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
      Rect.fromLTWH(96, footer, 72, 72),
      Paint()..filterQuality = FilterQuality.high,
    );
    text('风灵音乐 · Sylphy Music', 190, footer, 28, weight: FontWeight.w500);
    text(day, 190, footer + 42, 23, color: const Color(0xff80776a));
    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height);
    picture.dispose();
    logo.dispose();
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('无法生成图片');
      return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    } finally {
      image.dispose();
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
      final directory = await Directory(p.join(path, 'SylphyMusic'))
          .create(recursive: true);
      final file = File(p.join(directory.path, name));
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

/// Save first; sharing opens the system chooser and leaves the image locally.
class LetterImageActions extends StatefulWidget {
  const LetterImageActions({
    super.key,
    required this.day,
    required this.content,
  });
  final String day;
  final String content;
  @override
  State<LetterImageActions> createState() => _LetterImageActionsState();
}

class _LetterImageActionsState extends State<LetterImageActions> {
  bool _busy = false;
  Future<void> _export(bool share) async {
    if (_busy || widget.content.trim().isEmpty) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    var saved = false;
    try {
      final bytes = await LetterImage.render(widget.day, widget.content);
      final location = await LetterImage.save(bytes, widget.day);
      saved = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('图片已保存：$location')));
      if (share) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(bytes, mimeType: 'image/png')],
            fileNameOverrides: ['SylphyMusic-letter-${widget.day}.png'],
            title: '今日音乐信 · 风灵音乐',
            sharePositionOrigin: origin,
          ),
        );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saved ? '图片已保存，暂时无法打开分享面板' : '图片导出失败，请检查图片目录或存储权限后重试',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      OutlinedButton.icon(
        onPressed: _busy || widget.content.trim().isEmpty
            ? null
            : () => _export(false),
        icon: const Icon(Icons.image_outlined),
        label: Text(_busy ? '正在导出…' : '导出图片'),
      ),
      FilledButton.tonalIcon(
        onPressed: _busy || widget.content.trim().isEmpty
            ? null
            : () => _export(true),
        icon: const Icon(Icons.share_outlined),
        label: const Text('分享图片'),
      ),
    ],
  );
}
