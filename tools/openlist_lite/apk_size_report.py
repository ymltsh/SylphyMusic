#!/usr/bin/env python3
"""Inspect APK download bytes vs installed ELF bytes (read-only)."""
from pathlib import Path
import sys, zipfile


def mb(n):
    return f"{n / 1024 / 1024:.2f} MiB"


def report(apk):
    if not apk.exists():
        raise SystemExit(f"APK not found: {apk}")
    print(f"APK: {apk} | total on disk: {mb(apk.stat().st_size)}")
    with zipfile.ZipFile(apk) as archive:
        entries = sorted((x for x in archive.infolist() if not x.is_dir()),
                         key=lambda x: x.file_size, reverse=True)
        for x in entries[:15]:
            method = 'deflated' if x.compress_type == zipfile.ZIP_DEFLATED else 'stored'
            print(f"{mb(x.file_size):>12} raw  {mb(x.compress_size):>12} in APK  "
                  f"{method:8s}  {x.filename}")
        go = [x for x in entries if x.filename.endswith('/libgojni.so')]
        if go:
            x = go[0]
            print(f"\nGo JNI: uncompressed={mb(x.file_size)}, "
                  f"APK contribution={mb(x.compress_size)}, "
                  f"method={'deflate' if x.compress_type == 8 else 'stored'}")
            print('Caution: shrinking APK bytes is not the same as shrinking Go memory or installed disk bytes.')
        else:
            print('No libgojni.so found in this APK; inspect selected ABI and packaging.')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: python3 tools/openlist_lite/apk_size_report.py PATH_TO_APK')
    report(Path(sys.argv[1]))
