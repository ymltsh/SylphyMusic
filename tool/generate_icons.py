#!/usr/bin/env python3
"""Derive Android density icons and the Windows icon from assets/icon.png.

The artwork itself is authored in ``assets/icon.png``; this script only
produces the platform sizes, so no third-party Python packages are needed.
Run from any directory.
"""
from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from png_raster import read_png, resize_rgba, write_ico, write_png  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
DENSITIES = [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]
ICO_SIZES = (16, 20, 24, 32, 40, 48, 64, 128, 256)


def generate(root: Path = ROOT) -> None:
    source = root / 'assets/icon.png'
    width, height, pixels = read_png(source)
    if width != height:
        raise ValueError(f'assets/icon.png must be square (actual: {width}x{height})')
    if width < 256:
        raise ValueError(f'assets/icon.png must be at least 256 px (actual: {width}x{height})')
    for density, size in DENSITIES:
        scaled = resize_rgba(pixels, width, height, size, size)
        write_png(root / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', size, size, scaled)
    frames = [(size, resize_rgba(pixels, width, height, size, size)) for size in ICO_SIZES]
    write_ico(root / 'windows/runner/resources/app_icon.ico', frames)
    print(f'Generated Android launcher icons and Windows icon from assets/icon.png ({width}x{height}).')


if __name__ == '__main__':
    generate()
