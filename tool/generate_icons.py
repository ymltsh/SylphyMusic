"""Render the project's code-defined wind/music mark without external libraries."""
from pathlib import Path
import math
import struct
import zlib

root = Path(__file__).resolve().parents[1]

def png(size):
    raw = bytearray()
    for row in range(size):
        raw.append(0)
        for column in range(size):
            x, y = (column + .5) / size, (row + .5) / size
            base = [int(34 + 28 * (1-y)), int(87 + 38 * (1-y)), int(82 + 36 * x)]
            coverage = 0
            for left, right, height in [(.17,.56,.30),(.12,.51,.43),(.20,.48,.56)]:
                if left <= x <= right:
                    curve = height + .025 * math.sin((x-left)/(right-left)*math.pi)
                    coverage = max(coverage, min(1, max(0, (.022-abs(y-curve))*size+0.5)))
            stem = .64 <= x <= .69 and .25 <= y <= .70
            head = ((x-.60)/.09)**2 + ((y-.70)/.065)**2 <= 1
            flag = .67 <= x <= .82 and abs(y-(.25+(x-.67)*.4)) <= .023
            if stem or head or flag:
                coverage = 1
            raw.extend([int(value*(1-coverage)+239*coverage) for value in base] + [255])
    def chunk(kind, data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b'')

for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    (root/f'android/app/src/main/res/mipmap-{density}/ic_launcher.png').write_bytes(png(size))
image=png(256)
(root/'windows/runner/resources/app_icon.ico').write_bytes(struct.pack('<HHH',0,1,1)+struct.pack('<BBBBHHII',0,0,0,0,1,32,len(image),22)+image)
(root/'assets').mkdir(exist_ok=True)
(root/'assets/icon.png').write_bytes(png(192))
print('Generated Sylphy Music Android, Windows and shared icons.')
