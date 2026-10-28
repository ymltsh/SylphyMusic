"""Regression tests for the stdlib icon pipeline (png_raster + tool scripts)."""
import struct
import sys
import tempfile
from pathlib import Path
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tool'))

import generate_icons  # noqa: E402
import generate_launcher_variants  # noqa: E402
import png_raster  # noqa: E402


def solid(width: int, height: int, colour: tuple[int, int, int, int] = (80, 148, 178, 255)) -> bytearray:
    return bytearray(bytes(colour) * (width * height))


def filtered_png(width: int, height: int, rgba: bytes, filter_type: int) -> bytes:
    """Encode RGBA rows with one PNG filter type to exercise the decoder."""
    channels = 4
    stride = width * channels
    previous = bytes(stride)
    encoded = bytearray()
    for row in range(height):
        line = rgba[row * stride:(row + 1) * stride]
        encoded.append(filter_type)
        for index, value in enumerate(line):
            left = line[index - channels] if index >= channels else 0
            above = previous[index]
            upper_left = previous[index - channels] if index >= channels else 0
            if filter_type == 1:
                predictor = left
            elif filter_type == 2:
                predictor = above
            elif filter_type == 3:
                predictor = (left + above) // 2
            elif filter_type == 4:
                predictor = png_raster._paeth(left, above, upper_left)
            else:
                predictor = 0
            encoded.append((value - predictor) & 0xFF)
        previous = line

    def chunk(kind: bytes, payload: bytes) -> bytes:
        return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload) & 0xFFFFFFFF)

    return (
        png_raster.PNG_SIGNATURE
        + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(bytes(encoded)))
        + chunk(b'IEND', b'')
    )


class PngRasterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_png_roundtrip_preserves_pixels(self):
        pixels = bytearray()
        for y in range(6):
            for x in range(4):
                pixels += bytes((x * 40 % 256, y * 30 % 256, (x + y) * 20 % 256, 255 - x * 10))
        target = self.root / 'sample.png'
        png_raster.write_png(target, 4, 6, pixels)
        width, height, decoded = png_raster.read_png(target)
        self.assertEqual((width, height), (4, 6))
        self.assertEqual(decoded, pixels)

    def test_all_png_filters_decode(self):
        pixels = solid(3, 3)
        pixels[0:4] = bytes((255, 0, 0, 128))
        pixels[16:20] = bytes((0, 0, 255, 0))
        for filter_type in range(5):
            target = self.root / f'filter-{filter_type}.png'
            target.write_bytes(filtered_png(3, 3, pixels, filter_type))
            _, _, decoded = png_raster.read_png(target)
            self.assertEqual(decoded, pixels, f'filter {filter_type}')

    def test_rejects_non_png_input(self):
        target = self.root / 'fake.png'
        target.write_bytes(b'GIF89a not a png')
        with self.assertRaises(ValueError):
            png_raster.read_png(target)

    def test_resize_keeps_solid_colour_and_averages_blocks(self):
        scaled = png_raster.resize_rgba(solid(8, 8), 8, 8, 3, 3)
        self.assertEqual(bytes(scaled), bytes((80, 148, 178, 255)) * 9)

        quadrants = bytearray()
        for colour in [(255, 0, 0, 255), (0, 255, 0, 255), (0, 0, 255, 255), (255, 255, 255, 255)]:
            quadrants += bytes(colour)
        average = png_raster.resize_rgba(quadrants, 2, 2, 1, 1)
        self.assertEqual(bytes(average), bytes((128, 128, 128, 255)))

    def test_ico_contains_compatible_frames(self):
        frames = [(size, solid(size, size)) for size in (16, 48, 256)]
        target = self.root / 'app.ico'
        png_raster.write_ico(target, frames)
        data = target.read_bytes()
        reserved, kind, count = struct.unpack('<HHH', data[:6])
        self.assertEqual((reserved, kind, count), (0, 1, 3))
        directory = {}
        for index in range(count):
            width, height, colours, _, planes, depth, length, offset = struct.unpack(
                '<BBBBHHII', data[6 + index * 16:22 + index * 16]
            )
            directory[width] = (planes, depth, length, offset)
        self.assertEqual(sorted(directory), [0, 16, 48])
        self.assertEqual(directory[0][0:2], (1, 32))
        self.assertTrue(data[directory[0][3]:directory[0][3] + 8].startswith(png_raster.PNG_SIGNATURE))
        self.assertEqual(struct.unpack('<I', data[directory[16][3]:directory[16][3] + 4])[0], 40)


class GeneratorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_platform_icons_are_derived_from_the_default_asset(self):
        (self.root / 'assets').mkdir()
        png_raster.write_png(self.root / 'assets/icon.png', 256, 256, solid(256, 256))
        generate_icons.generate(self.root)
        for density, size in generate_icons.DENSITIES:
            target = self.root / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png'
            width, height, _ = png_raster.read_png(target)
            self.assertEqual((width, height), (size, size), density)
        ico = (self.root / 'windows/runner/resources/app_icon.ico').read_bytes()
        self.assertEqual(struct.unpack('<HHH', ico[:6])[2], len(generate_icons.ICO_SIZES))

    def test_alternatives_use_sorted_labels_and_aliases(self):
        (self.root / 'assets/launcher_icons').mkdir(parents=True)
        (self.root / 'android/app/src/main').mkdir(parents=True)
        (self.root / 'android/app/src/main/AndroidManifest.xml').write_text(
            '<manifest>\n'
            + generate_launcher_variants.START
            + '\n'
            + generate_launcher_variants.END
            + '\n</manifest>\n',
            encoding='utf-8',
        )
        for name in ['10.点阵白.png', '2.高气压.png']:
            png_raster.write_png(self.root / 'assets/launcher_icons' / name, 192, 192, solid(192, 192))

        entries = generate_launcher_variants.generate(self.root)
        self.assertEqual([entry['label'] for entry in entries], ['高气压', '点阵白'])
        self.assertEqual([entry['preview'] for entry in entries],
                         ['assets/launcher_icons/2.高气压.png', 'assets/launcher_icons/10.点阵白.png'])
        for entry in entries:
            self.assertTrue((self.root / f"android/app/src/main/res/mipmap-nodpi/ic_launcher_{entry['id']}.png").exists())
        manifest = (self.root / 'android/app/src/main/AndroidManifest.xml').read_text(encoding='utf-8')
        for entry in entries:
            self.assertIn(f'LauncherIcon_{entry["id"]}', manifest)
        catalog = (self.root / 'android/app/src/main/assets/launcher_icons.json').read_text(encoding='utf-8')
        self.assertIn('高气压', catalog)


if __name__ == '__main__':
    unittest.main()
