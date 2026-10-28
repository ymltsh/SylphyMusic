import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/services/lyrics.dart';

void main() {
  test('offset and active line handle preroll and seeks', () {
    final lines = parseLrc('[offset:100]\n[00:01.00]A\n[00:02.00]B');
    expect(lines.first.at.inMilliseconds, 1100);
    expect(activeLrcIndex(lines, Duration.zero), -1);
    expect(activeLrcIndex(lines, const Duration(milliseconds: 1100)), 0);
    expect(activeLrcIndex(lines, const Duration(seconds: 3)), 1);
    expect(activeLrcIndex(lines, const Duration(seconds: 1)), -1);
  });
  test('LRC tags sort and parse multiple timestamps', () {
    final lines = parseLrc('[00:02.50]B\n[00:01.005]A\n[00:04.3][00:05.3]C');
    expect(lines.length, 4);
    expect(lines.first.text, 'A');
    expect(lines.first.at.inMilliseconds, 1005);
    expect(lines[1].at.inMilliseconds, 2500);
  });
  test(
    'SRT hours, milliseconds, translations and instrumental gaps retain timing',
    () {
      final text = normalizeSubtitleLyrics(
        '1\r\n01:02:03,045 --> 01:02:05,500\r\n<i>Original</i>\r\n译文 &amp; 音乐\r\n\r\n'
        '2\r\n01:02:07,000 --> 01:02:09,000\r\nNext\r\n',
      );
      final lines = parseLrc(text);
      expect(lines.map((e) => e.at.inMilliseconds), [
        3723045,
        3723045,
        3725500,
        3727000,
        3729000,
      ]);
      expect(lines.map((e) => e.text), ['Original', '译文 & 音乐', '', 'Next', '']);
      expect(
        lines[activeLrcIndex(lines, const Duration(milliseconds: 3726000))]
            .text,
        isEmpty,
      );
      expect(
        lines[activeLrcIndex(lines, const Duration(milliseconds: 3728000))]
            .text,
        'Next',
      );
    },
  );
  test('WebVTT cue settings are not treated as lyrics', () {
    final text = normalizeSubtitleLyrics(
      'WEBVTT\n\ncue\n00:01.250 --> 00:03.500 align:start\nHello\n',
    );
    final lines = parseLrc(text);
    expect(lines.first.at.inMilliseconds, 1250);
    expect(lines.first.text, 'Hello');
    expect(lines.last.at.inMilliseconds, 3500);
  });
  test(
    'overlapping translations with the same time use the latest cue end',
    () {
      final text = normalizeSubtitleLyrics(
        '1\n00:00:01,000 --> 00:00:05,000\nOriginal\n\n'
        '2\n00:00:01,000 --> 00:00:03,000\nTranslation\n\n',
      );
      final lines = parseLrc(text);
      expect(lines.map((e) => e.text), ['Original', 'Translation', '']);
      expect(lines.last.at, const Duration(seconds: 5));
    },
  );
  test('reversed Emby SRT end keeps the instrumental notice only', () {
    const subtitle = '1\n00:00:05,000 --> 00:00:00,000\n纯音乐，请欣赏';
    final normalized = normalizeSubtitleLyrics(subtitle);
    expect(normalized, '[00:05.000]纯音乐，请欣赏');
    final lines = parseLrc(normalized);
    expect(lines, hasLength(1));
    expect(lines.single.at, const Duration(seconds: 5));
    expect(lines.single.text, '纯音乐，请欣赏');
  });

  test('zero-duration notice remains visible until the next cue', () {
    final lines = parseLrc(
      normalizeSubtitleLyrics(
        '1\n00:00:05,000 --> 00:00:05,000\nInstrumental\n\n'
        '2\n00:00:10,000 --> 00:00:12,000\nNext line',
      ),
    );
    expect(lines.map((line) => line.at.inSeconds), [5, 10, 12]);
    expect(lines.map((line) => line.text), ['Instrumental', 'Next line', '']);
    expect(
      lines[activeLrcIndex(lines, const Duration(seconds: 8))].text,
      'Instrumental',
    );
  });

  test('Emby instrumental cue with reversed end stays active', () {
    const srt =
        '1\n00:00:00,000 --> 00:00:01,000\n作词 : 无\n\n'
        '2\n00:00:01,000 --> 00:00:05,000\n作曲 : 阿鲲\n\n'
        '3\n00:00:05,000 --> 00:00:00,000\n纯音乐，请欣赏';
    final normalized = normalizeSubtitleLyrics(srt);
    expect(
      normalized,
      '[00:00.000]作词 : 无\n'
      '[00:01.000]作曲 : 阿鲲\n'
      '[00:05.000]纯音乐，请欣赏',
    );
    final lines = parseLrc(normalized);
    expect(lines, hasLength(3));
    expect(
      lines[activeLrcIndex(lines, const Duration(seconds: 12))].text,
      '纯音乐，请欣赏',
    );
  });
  test('plain text and existing LRC remain intact', () {
    expect(
      normalizeSubtitleLyrics('Only text\nSecond line'),
      'Only text\nSecond line',
    );
    expect(
      normalizeSubtitleLyrics('\uFEFF[00:01.20]A\r\n[00:02.00]B'),
      '[00:01.20]A\n[00:02.00]B',
    );
  });
}
