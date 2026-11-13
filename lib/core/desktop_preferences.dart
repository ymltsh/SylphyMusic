import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../data/app_db.dart';
import '../services/desktop_fonts.dart';

class DesktopPreferences extends ChangeNotifier {
  DesktopPreferences(this.db);
  final AppDb db;
  bool shortcutsEnabled = true;
  bool showVolume = true;
  bool showExtraControls = true;
  String? fontFamily;
  String fontLabel = '系统默认';
  String? _fontName;
  DesktopFontDownload? _download;
  DesktopFont? downloadingFont;
  double? downloadProgress;
  String downloadStatus = '';
  void cancelFontDownload() => _download?.cancel();
  bool _closed = false;
  Future<void> _work = Future.value();
  static final _managedFont = RegExp(r'^font-[0-9a-f-]+\.(ttf|otf)$');
  Directory get _directory => Directory(p.join(db.root.path, 'desktop_fonts'));

  Future<void> initialize() async {
    shortcutsEnabled = await db.setting('desktop_shortcuts') != 'false';
    showVolume = await db.setting('desktop_volume') != 'false';
    showExtraControls = await db.setting('desktop_extra_controls') != 'false';
    if (!Platform.isWindows) return;
    final name = await db.setting('desktop_font_file');
    if (name == null || !_managedFont.hasMatch(name)) return;
    try {
      await _loadFont(File(p.join(_directory.path, name)), name);
      _fontName = name;
      fontLabel = await db.setting('desktop_font_label') ?? '自定义字体';
    } catch (_) {
      fontFamily = null;
      fontLabel = '系统默认';
    }
  }

  Future<void> update({bool? shortcuts, bool? volume, bool? extraControls}) =>
      _queue(() async {
        await db.db.transaction((tx) async {
          for (final entry in <String, bool?>{
            'desktop_shortcuts': shortcuts,
            'desktop_volume': volume,
            'desktop_extra_controls': extraControls,
          }.entries) {
            if (entry.value != null)
              await tx.rawInsert(
                'INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)',
                [entry.key, '${entry.value}'],
              );
          }
        });
        shortcutsEnabled = shortcuts ?? shortcutsEnabled;
        showVolume = volume ?? showVolume;
        showExtraControls = extraControls ?? showExtraControls;
        if (!_closed) notifyListeners();
      });

  Future<void> _loadFont(File file, String name) async {
    final bytes = await file.readAsBytes();
    if (bytes.length < 12 || bytes.length > 20 * 1024 * 1024)
      throw const FormatException('字体文件大小不合适，请选择 20 MiB 以内的 TTF 或 OTF');
    final signature = ByteData.sublistView(bytes).getUint32(0);
    if (signature != 0x00010000 && signature != 0x4f54544f)
      throw const FormatException('请选择有效的 TTF 或 OTF 字体');
    final family = 'SylphyDesktop-$name';
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    fontFamily = family;
  }

  Future<void> pickFont() async {
    if (!Platform.isWindows || _closed) return;
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf'],
    );
    if (picked == null || _closed) return;
    final size = await picked.length();
    if (size != null && size > 20 * 1024 * 1024)
      throw const FormatException('请选择 20 MiB 以内的字体文件');
    final bytes = await picked.readAsBytes();
    final ext = picked.extension?.toLowerCase();
    if (ext != 'ttf' && ext != 'otf')
      throw const FormatException('请选择 TTF 或 OTF 字体');
    await _queue(() => _installFont(bytes, ext!, picked.name));
  }

  Future<void> downloadFont(DesktopFont font) {
    if (!Platform.isWindows || _closed || _download != null)
      return Future.value();
    final download = DesktopFontDownload();
    _download = download;
    downloadingFont = font;
    downloadProgress = null;
    downloadStatus = '准备下载 ${font.label}';
    notifyListeners();
    return _queue(() async {
      try {
        if (_closed) return;
        await _directory.create(recursive: true);
        final temporary = File(
          p.join(_directory.path, 'download-${const Uuid().v4()}.tmp'),
        );
        final result = await download.fetch(font, temporary, (
          progress,
          status,
        ) {
          downloadProgress = progress;
          downloadStatus = status;
          if (!_closed) notifyListeners();
        });
        if (_closed) return;
        await _installFont(
          result.$1,
          'ttf',
          font.label,
          license: result.$2,
          licenseExtension: font.licenseExtension,
          source: font.url,
        );
      } finally {
        _download = null;
        downloadingFont = null;
        downloadProgress = null;
        if (!_closed) notifyListeners();
      }
    });
  }

  Future<void> _installFont(
    Uint8List bytes,
    String ext,
    String label, {
    Uint8List? license,
    String? licenseExtension,
    String? source,
  }) async {
    await _directory.create(recursive: true);
    final name = 'font-${const Uuid().v4()}.$ext';
    final target = File(p.join(_directory.path, name));
    final temporary = File('${target.path}.tmp');
    final oldFamily = fontFamily;
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
      if (license != null) {
        await File('${target.path}.license.$licenseExtension')
            .writeAsBytes(license, flush: true);
        await File('${target.path}.source.txt').writeAsString(
          '$label\n$source\n字体采用厂商独立许可，不属于 Sylphy Music 的 MIT 授权范围。\n',
          flush: true,
        );
      }
      await _loadFont(target, name);
      await db.db.transaction((tx) async {
        for (final entry in {
          'desktop_font_file': name,
          'desktop_font_label': label,
        }.entries) {
          await tx.rawInsert(
            'INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)',
            [entry.key, entry.value],
          );
        }
      });
    } catch (_) {
      fontFamily = oldFamily;
      if (await temporary.exists()) await temporary.delete();
      await _removeFont(name);
      rethrow;
    }
    final old = _fontName;
    _fontName = name;
    fontLabel = label;
    if (!_closed) notifyListeners();
    await _removeFont(old);
  }

  Future<void> resetFont() => _queue(() async {
    await db.db.transaction((tx) async {
      await tx.delete(
        'settings',
        where: 'key IN (?,?)',
        whereArgs: ['desktop_font_file', 'desktop_font_label'],
      );
    });
    final old = _fontName;
    _fontName = fontFamily = null;
    fontLabel = '系统默认';
    if (!_closed) notifyListeners();
    await _removeFont(old);
  });

  Future<void> _removeFont(String? name) async {
    if (name == null || !_managedFont.hasMatch(name)) return;
    try {
      for (final suffix in [
        '',
        '.license.txt',
        '.license.pdf',
        '.source.txt',
      ]) {
        final file = File(p.join(_directory.path, '$name$suffix'));
        if (await file.exists()) await file.delete();
      }
    } on FileSystemException catch (_) {}
  }

  Future<void> _queue(Future<void> Function() operation) {
    if (_closed) return Future.error(StateError('横屏与 PC 设置已关闭'));
    final next = _work.then((_) => operation());
    _work = next.catchError((Object _) {});
    return next;
  }

  Future<void> shutdown() async {
    _closed = true;
    cancelFontDownload();
    await _work;
    dispose();
  }
}
