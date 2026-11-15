import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerAndroidNativeLicenses() {
  const files = [
    'mpv-android-2026-09-17-NOTICE.md',
    'mpv-android-2026-09-17-Copyright.txt',
    'mpv-GPL-2.txt',
    'mpv-LGPL-2.1.txt',
    'ffmpeg-GPL-3.txt',
    'ffmpeg-LGPL-3.txt',
  ];
  LicenseRegistry.addLicense(() async* {
    for (final name in files) {
      yield LicenseEntryWithLineBreaks([
        'Android mpv / FFmpeg',
      ], await rootBundle.loadString('assets/native_licenses/$name'));
    }
  });
}
