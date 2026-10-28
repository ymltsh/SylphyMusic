"""Small stdlib-only PNG / ICO codec used by the icon generation scripts.

Only the subset needed by the project icon pipeline is implemented: 8-bit,
non-interlaced PNG input (grayscale, RGB, palette, grayscale + alpha, RGBA)
and RGBA PNG output. Keeping this dependency-free lets
``python tool/generate_icons.py`` run on a stock Python installation.
"""
from __future__ import annotations

import struct
import zlib
from pathlib import Path

PNG_SIGNATURE = b'\x89PNG\r\n\x1a\n'
_CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


def _paeth(left: int, above: int, upper_left: int) -> int:
    estimate = left + above - upper_left
    distance_left = abs(estimate - left)
    distance_above = abs(estimate - above)
    distance_upper_left = abs(estimate - upper_left)
    if distance_left <= distance_above and distance_left <= distance_upper_left:
        return left
    if distance_above <= distance_upper_left:
        return above
    return upper_left


def read_png(path: str | Path) -> tuple[int, int, bytearray]:
    """Return ``(width, height, rgba_bytes)`` for a supported PNG file."""
    data = Path(path).read_bytes()
    if not data.startswith(PNG_SIGNATURE) or data[12:16] != b'IHDR':
        raise ValueError(f'Not a PNG file: {path}')
    position = 8
    width = height = depth = colour_type = interlace = None
    palette = b''
    transparency = b''
    compressed = bytearray()
    while position + 8 <= len(data):
        length = struct.unpack('>I', data[position:position + 4])[0]
        kind = data[position + 4:position + 8]
        payload = data[position + 8:position + 8 + length]
        position += 12 + length
        if kind == b'IHDR':
            width, height, depth, colour_type, compression, filter_method, interlace = \
                struct.unpack('>IIBBBBB', payload)
            if compression != 0 or filter_method != 0:
                raise ValueError(f'Unsupported PNG compression in {path}')
        elif kind == b'PLTE':
            palette = payload
        elif kind == b'tRNS':
            transparency = payload
        elif kind == b'IDAT':
            compressed += payload
        elif kind == b'IEND':
            break
    if interlace != 0:
        raise ValueError(f'Interlaced PNG is not supported: {path}')
    if depth != 8 or colour_type not in _CHANNELS:
        raise ValueError(f'Only 8-bit palette / RGB / gray PNG is supported: {path}')
    if not width or not height:
        raise ValueError(f'Empty PNG: {path}')

    channels = _CHANNELS[colour_type]
    stride = width * channels
    raw = zlib.decompress(bytes(compressed))
    if len(raw) != height * (stride + 1):
        raise ValueError(f'Corrupt PNG data: {path}')

    pixels = bytearray(width * height * 4)
    previous = bytearray(stride)
    for row in range(height):
        start = row * (stride + 1)
        filter_type = raw[start]
        line = bytearray(raw[start + 1:start + 1 + stride])
        if filter_type == 0:
            pass
        elif filter_type == 1:
            for index in range(channels, stride):
                line[index] = (line[index] + line[index - channels]) & 0xFF
        elif filter_type == 2:
            for index in range(stride):
                line[index] = (line[index] + previous[index]) & 0xFF
        elif filter_type == 3:
            for index in range(stride):
                left = line[index - channels] if index >= channels else 0
                line[index] = (line[index] + ((left + previous[index]) >> 1)) & 0xFF
        elif filter_type == 4:
            for index in range(stride):
                left = line[index - channels] if index >= channels else 0
                upper_left = previous[index - channels] if index >= channels else 0
                line[index] = (line[index] + _paeth(left, previous[index], upper_left)) & 0xFF
        else:
            raise ValueError(f'Unknown PNG filter {filter_type} in {path}')

        previous = line
        destination = row * width * 4
        if colour_type == 6:
            pixels[destination:destination + width * 4] = line
        elif colour_type == 2:
            for column in range(width):
                source = column * 3
                target = destination + column * 4
                pixels[target] = line[source]
                pixels[target + 1] = line[source + 1]
                pixels[target + 2] = line[source + 2]
                pixels[target + 3] = 255
        elif colour_type == 3:
            for column in range(width):
                index = line[column]
                if index * 3 + 3 > len(palette):
                    raise ValueError(f'Palette index out of range in {path}')
                target = destination + column * 4
                pixels[target] = palette[index * 3]
                pixels[target + 1] = palette[index * 3 + 1]
                pixels[target + 2] = palette[index * 3 + 2]
                pixels[target + 3] = transparency[index] if index < len(transparency) else 255
        elif colour_type == 4:
            for column in range(width):
                target = destination + column * 4
                pixels[target] = pixels[target + 1] = pixels[target + 2] = line[column * 2]
                pixels[target + 3] = line[column * 2 + 1]
        else:  # colour_type == 0
            for column in range(width):
                target = destination + column * 4
                pixels[target] = pixels[target + 1] = pixels[target + 2] = line[column]
                pixels[target + 3] = 255
    return width, height, pixels


def _weights(source: int, target: int) -> list[tuple[tuple[int, float], ...]]:
    """Triangle-filter weights; wide support when downscaling antialiases."""
    scale = target / source
    downscaling = scale < 1
    radius = 1 / scale if downscaling else 1.0
    table = []
    for index in range(target):
        centre = (index + 0.5) / scale
        first = max(0, int(centre - radius))
        last = min(source, int(centre + radius) + 1)
        samples = []
        for position in range(first, last):
            distance = abs(position + 0.5 - centre) * (scale if downscaling else 1)
            weight = 1 - distance
            if weight > 0:
                samples.append((position, weight))
        total = sum(weight for _, weight in samples)
        if not samples or total <= 0:
            samples = [(min(source - 1, int(centre)), 1.0)]
            total = 1
        table.append(tuple((position, weight / total) for position, weight in samples))
    return table


def resize_rgba(
    pixels: bytearray | bytes,
    width: int,
    height: int,
    target_width: int,
    target_height: int,
) -> bytearray:
    """Resize RGBA pixels with a separable triangle filter."""
    if (width, height) == (target_width, target_height):
        return bytearray(pixels)
    horizontal = bytearray(target_width * height * 4)
    columns = _weights(width, target_width)
    for row in range(height):
        source_row = row * width * 4
        target_row = row * target_width * 4
        for column, samples in enumerate(columns):
            red = green = blue = alpha = 0.0
            for position, weight in samples:
                index = source_row + position * 4
                red += pixels[index] * weight
                green += pixels[index + 1] * weight
                blue += pixels[index + 2] * weight
                alpha += pixels[index + 3] * weight
            target = target_row + column * 4
            horizontal[target] = _byte(red)
            horizontal[target + 1] = _byte(green)
            horizontal[target + 2] = _byte(blue)
            horizontal[target + 3] = _byte(alpha)

    result = bytearray(target_width * target_height * 4)
    rows = _weights(height, target_height)
    for row, samples in enumerate(rows):
        target_row = row * target_width * 4
        for column in range(target_width):
            red = green = blue = alpha = 0.0
            for position, weight in samples:
                index = position * target_width * 4 + column * 4
                red += horizontal[index] * weight
                green += horizontal[index + 1] * weight
                blue += horizontal[index + 2] * weight
                alpha += horizontal[index + 3] * weight
            target = target_row + column * 4
            result[target] = _byte(red)
            result[target + 1] = _byte(green)
            result[target + 2] = _byte(blue)
            result[target + 3] = _byte(alpha)
    return result


def _byte(value: float) -> int:
    return min(255, max(0, int(value + 0.5)))


def _chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack('>I', len(payload))
        + kind
        + payload
        + struct.pack('>I', zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def png_bytes(width: int, height: int, rgba: bytearray | bytes, level: int = 9) -> bytes:
    if len(rgba) != width * height * 4:
        raise ValueError('RGBA buffer size does not match the image size')
    stride = width * 4
    raw = bytearray()
    for row in range(height):
        raw.append(0)
        raw += rgba[row * stride:(row + 1) * stride]
    return (
        PNG_SIGNATURE
        + _chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
        + _chunk(b'IDAT', zlib.compress(bytes(raw), level))
        + _chunk(b'IEND', b'')
    )


def write_png(path: str | Path, width: int, height: int, rgba: bytearray | bytes) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(png_bytes(width, height, rgba))


def _bmp_icon(size: int, rgba: bytearray | bytes) -> bytes:
    header = struct.pack('<IiiHHIIiiII', 40, size, size * 2, 1, 32, 0, size * size * 4, 0, 0, 0, 0)
    pixels = bytearray()
    for row in range(size - 1, -1, -1):
        for column in range(size):
            index = (row * size + column) * 4
            pixels += bytes((rgba[index + 2], rgba[index + 1], rgba[index], rgba[index + 3]))
    mask_stride = ((size + 31) // 32) * 4
    mask = bytearray(mask_stride * size)
    for row in range(size):
        for column in range(size):
            if rgba[((size - 1 - row) * size + column) * 4 + 3] < 128:
                mask[row * mask_stride + column // 8] |= 0x80 >> (column % 8)
    return header + bytes(pixels) + bytes(mask)


def write_ico(path: str | Path, images: list[tuple[int, bytearray | bytes]]) -> None:
    """Write a multi-resolution Windows icon from square RGBA images.

    Sizes below 128 px use uncompressed 32-bit bitmaps for maximum
    compatibility; larger sizes use PNG compression (Windows Vista+).
    """
    if not images:
        raise ValueError('At least one icon size is required')
    frames = []
    for size, rgba in sorted(images):
        if len(rgba) != size * size * 4:
            raise ValueError(f'RGBA buffer size does not match {size}x{size}')
        payload = png_bytes(size, size, rgba) if size >= 128 else _bmp_icon(size, rgba)
        frames.append((size, payload))

    header = struct.pack('<HHH', 0, 1, len(frames))
    offset = 6 + 16 * len(frames)
    directory = bytearray()
    body = bytearray()
    for size, payload in frames:
        directory += struct.pack(
            '<BBBBHHII',
            size if size < 256 else 0,
            size if size < 256 else 0,
            0,
            0,
            1,
            32,
            len(payload),
            offset,
        )
        body += payload
        offset += len(payload)
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(header + bytes(directory) + bytes(body))
