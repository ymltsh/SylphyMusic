import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

enum DesktopFont {
  harmony(
    'HarmonyOS Sans',
    '华为 · 简体中文 Regular',
    'https://developer.huawei.com/images/download/general/HarmonyOS-Sans.zip',
    'https://developer.huawei.com/consumer/cn/design/resource/',
    'HarmonyOS Sans/HarmonyOS_Sans_SC/HarmonyOS_Sans_SC_Regular.ttf',
    '297b088424be212207df2ce8b98e335468b782aa6b96832af0b8b773d711e2b1',
    'HarmonyOS Sans/HarmonyOS_Sans_SC/LICENSE.txt',
    'txt',
    '约 50 MiB',
  ),
  miSans(
    'MiSans',
    '小米 · Regular',
    'https://hyperos.mi.com/font-download/MiSans.zip',
    'https://hyperos.mi.com/font/zh/download/',
    'MiSans/ttf/MiSans-Regular.ttf',
    '9c120f0a849bc0aa5048daae2a3c0f6eecd828b5b33fce682a9622833f5feea6',
    'https://hyperos.mi.com/font-download/MiSans%E5%AD%97%E4%BD%93%E7%9F%A5%E8%AF%86%E4%BA%A7%E6%9D%83%E8%AE%B8%E5%8F%AF%E5%8D%8F%E8%AE%AE.pdf',
    'pdf',
    '约 218 MiB',
  );

  const DesktopFont(
    this.label,
    this.description,
    this.url,
    this.licenseUrl,
    this.entry,
    this.digest,
    this.licenseEntry,
    this.licenseExtension,
    this.size,
  );
  final String label,
      description,
      url,
      licenseUrl,
      entry,
      digest,
      licenseEntry,
      licenseExtension,
      size;
}

// Decode only the known font and license. No archive paths are extracted to disk.
Future<(Uint8List, Uint8List?)> _decode((String, DesktopFont) request) async {
  final input = InputFileStream(request.$1);
  try {
    final font = request.$2;
    final archive = ZipDecoder().decodeStream(input);
    Uint8List read(String name, int limit) {
      final entry = archive.findFile(name);
      if (entry == null || !entry.isFile || entry.size > limit) {
        throw const FormatException('官方字体包结构已变更，请使用本地字体导入');
      }
      final bytes = entry.readBytes();
      if (bytes == null || bytes.length > limit) {
        throw const FormatException('字体包内容无效');
      }
      return bytes;
    }

    final bytes = read(font.entry, 20 * 1024 * 1024);
    if (sha256.convert(bytes).toString() != font.digest) {
      throw const FormatException('官方字体版本已变化，请更新应用或使用本地字体导入');
    }
    return (
      bytes,
      font == DesktopFont.harmony ? read(font.licenseEntry, 1024 * 1024) : null,
    );
  } finally {
    await input.close();
  }
}

class DesktopFontDownload {
  HttpClient? _client;
  bool _cancelled = false;
  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  void _check() {
    if (_cancelled) throw StateError('字体下载已取消');
  }

  Future<(Uint8List, Uint8List)> fetch(
    DesktopFont font,
    File temporary,
    void Function(double?, String) progress,
  ) async {
    _client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      await _download(font.url, temporary, 300 * 1024 * 1024, (v) {
        progress(v, '正在下载 ${font.label}');
      });
      _check();
      progress(null, '正在准备字体');
      final decoded = await compute(_decode, (temporary.path, font));
      _check();
      var license = decoded.$2;
      if (license == null) {
        progress(null, '正在下载官方许可');
        await _download(font.licenseEntry, temporary, 4 * 1024 * 1024, (_) {});
        license = await temporary.readAsBytes();
        if (!String.fromCharCodes(license.take(5)).startsWith('%PDF-')) {
          throw const FormatException('无法读取官方字体许可，请稍后重试');
        }
      }
      _check();
      return (decoded.$1, license);
    } finally {
      _client?.close(force: true);
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _download(
    String url,
    File target,
    int limit,
    void Function(double?) progress,
  ) async {
    _check();
    final request = await _client!
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 30));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('字体下载失败（${response.statusCode}）');
    }
    final total = response.contentLength;
    if (total > limit) throw const FormatException('字体包超出大小限制');
    final sink = target.openWrite();
    var received = 0;
    var lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 45))) {
        _check();
        received += chunk.length;
        if (received > limit) throw const FormatException('字体包超出大小限制');
        sink.add(chunk);
        await sink.flush();
        final now = DateTime.now();
        if (now.difference(lastUpdate).inMilliseconds >= 150) {
          progress(total > 0 ? received / total : null);
          lastUpdate = now;
        }
      }
      if (total >= 0 && received != total)
        throw const FormatException('字体包下载不完整');
    } finally {
      await sink.close();
    }
  }
}
