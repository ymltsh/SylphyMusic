These fixtures contain only a synthetic 440 Hz sine wave and a solid color cover,
generated locally with FFmpeg. No user music or server metadata is included.

- tone.mp3: two seconds, MP3 128 kbps / 44.1 kHz, ID3 tags.
- tone.flac: two seconds, FLAC / 96 kHz, Vorbis tags.
- covered.mp3: tone.mp3 plus the attached cover.png image.

Regenerate with `python tool/generate_test_media.py` (requires FFmpeg on PATH).
