"""Create synthetic, redistributable codec/tag fixtures; never reads user media."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
fixtures = root / 'test' / 'fixtures'
fixtures.mkdir(parents=True, exist_ok=True)

def ffmpeg(*args):
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', *args], cwd=root, check=True)

tags = ['-metadata', 'artist=Test Artist', '-metadata', 'album=Test Album', '-metadata', 'date=2026']
ffmpeg('-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=96000:duration=2',
       *tags, '-metadata', 'title=Sylphy FLAC', '-metadata', 'album_artist=Album Artist',
       '-metadata', 'track=2', '-c:a', 'flac', '-sample_fmt', 's32', str(fixtures / 'tone.flac'))
ffmpeg('-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100:duration=2',
       *tags, '-metadata', 'title=Sylphy MP3', '-metadata', 'track=1',
       '-c:a', 'libmp3lame', '-b:a', '128k', str(fixtures / 'tone.mp3'))
ffmpeg('-f', 'lavfi', '-i', 'color=c=0x528a81:s=64x64', '-frames:v', '1', str(fixtures / 'cover.png'))
ffmpeg('-i', str(fixtures / 'tone.mp3'), '-i', str(fixtures / 'cover.png'),
       '-map', '0:a', '-map', '1:v', '-c', 'copy', '-id3v2_version', '3',
       '-metadata:s:v', 'title=Album cover', '-metadata:s:v', 'comment=Cover (front)', str(fixtures / 'covered.mp3'))
