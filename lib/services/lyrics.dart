// Some LRC providers append a translation to the original using a Unicode
// thin-space separator instead of a second time-tagged line. Preserve the
// timestamp and let lyric renderers style the second line as a translation.
final _inlineTranslationSeparator = RegExp(r'[\u2009\u200A\u202F]+');
final _lyricLetter = RegExp(r'[A-Za-z\u3040-\u30FF\u3400-\u9FFF\uAC00-\uD7AF]');
final _latinLyricLetters = RegExp(r'[A-Za-z]');
final _cjkLyricLetters = RegExp(r'[\u3040-\u30FF\u3400-\u9FFF\uAC00-\uD7AF]');

String _splitInlineTranslation(String text) {
  for (final separator in _inlineTranslationSeparator.allMatches(text)) {
    final original = text.substring(0, separator.start).trimRight();
    final translation = text.substring(separator.end).trimLeft();
    if (original.isEmpty || translation.isEmpty) continue;
    // Check the scripts directly around the separator, not elsewhere in a
    // mixed-language line (for example, composer credits with Latin names).
    final beforeLetters = _lyricLetter.allMatches(original);
    final afterLetter = _lyricLetter.firstMatch(translation)?.group(0);
    if (beforeLetters.isEmpty || afterLetter == null) continue;
    final beforeLetter = beforeLetters.last.group(0)!;
    if ((_latinLyricLetters.hasMatch(beforeLetter) &&
            _cjkLyricLetters.hasMatch(afterLetter)) ||
        (_cjkLyricLetters.hasMatch(beforeLetter) &&
            _latinLyricLetters.hasMatch(afterLetter))) {
      return '$original\n$translation';
    }
  }
  return text;
}

class LrcLine {
  const LrcLine(this.at, this.text);
  final Duration at;
  final String text;
}

List<LrcLine> parseLrc(String source) {
  final result = <LrcLine>[];
  // Emby can append an end marker, such as [00:00.00-1], to a time tag.
  // LRC display uses the start time; the suffix must not become lyric text.
  final time = RegExp(r'\[(\d{1,6}):(\d{2})(?:\.(\d{1,3}))?(?:-\d+)?\]');
  final offset =
      int.tryParse(
        RegExp(
              r'\[offset:([+-]?\d+)\]',
              caseSensitive: false,
            ).firstMatch(source)?.group(1) ??
            '',
      ) ??
      0;
  for (final raw in source.split(RegExp(r'\r?\n'))) {
    final matches = time.allMatches(raw).toList();
    if (matches.isEmpty) continue;
    final text = _splitInlineTranslation(raw.replaceAll(time, '').trim());
    for (final m in matches) {
      final fraction = m.group(3) ?? '';
      final milli = fraction.isEmpty
          ? 0
          : int.parse(fraction.padRight(3, '0').substring(0, 3));
      result.add(
        LrcLine(
          Duration(
            minutes: int.parse(m.group(1)!),
            seconds: int.parse(m.group(2)!),
            milliseconds: milli + offset,
          ),
          text,
        ),
      );
    }
  }
  final ordered = result.indexed.toList()
    ..sort((a, b) {
      final time = a.$2.at.compareTo(b.$2.at);
      return time == 0 ? a.$1.compareTo(b.$1) : time;
    });
  return ordered.map((entry) => entry.$2).toList();
}

int activeLrcIndex(List<LrcLine> lines, Duration position) {
  var low = 0, high = lines.length - 1, result = -1;
  while (low <= high) {
    final mid = (low + high) ~/ 2;
    if (lines[mid].at <= position) {
      result = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return result;
}

/// Convert Emby's timed subtitle response to the same LRC representation used
/// by local / imported lyrics. Plain text remains readable when no cue exists.
String normalizeSubtitleLyrics(String source) {
  final text = source
      .replaceFirst('\uFEFF', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trim();
  if (parseLrc(text).isNotEmpty) return text;
  final timing = RegExp(
    r'^\s*((?:\d{1,3}:)?\d{2}:\d{2}[,.]\d{1,3})\s*-->\s*((?:\d{1,3}:)?\d{2}:\d{2}[,.]\d{1,3})(?:\s+.*)?$',
  );
  Duration? clock(String value) {
    final parts = value.replaceAll(',', '.').split(':');
    final seconds = double.tryParse(parts.last);
    final minutes = int.tryParse(parts[parts.length - 2]);
    final hours = parts.length == 3 ? int.tryParse(parts.first) : 0;
    if (seconds == null ||
        seconds >= 60 ||
        minutes == null ||
        hours == null ||
        (parts.length == 3 && minutes >= 60)) {
      return null;
    }
    return Duration(
      hours: hours,
      minutes: minutes,
      milliseconds: (seconds * 1000).round(),
    );
  }

  String clean(String value) => value
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .trim();
  final raw = text.split('\n');
  final cues = <({Duration at, Duration end, List<String> text, int order})>[];
  for (var i = 0; i < raw.length; i++) {
    final match = timing.firstMatch(raw[i]);
    if (match == null) continue;
    final at = clock(match[1]!), end = clock(match[2]!);
    final lines = <String>[];
    while (i + 1 < raw.length && raw[i + 1].trim().isNotEmpty) {
      lines.add(clean(raw[++i]));
    }
    if (at == null || end == null) continue;
    // Emby may produce a zero or reversed end time for instrumental notices.
    // Keep the start time and text, but do not synthesize a clear marker.
    cues.add((
      at: at,
      end: end > at ? end : at,
      text: lines,
      order: cues.length,
    ));
  }
  if (cues.isEmpty) return text;
  cues.sort((a, b) {
    final time = a.at.compareTo(b.at);
    return time == 0 ? a.order.compareTo(b.order) : time;
  });
  final grouped = <({Duration at, Duration end, List<String> text})>[];
  for (final cue in cues) {
    if (grouped.isNotEmpty && grouped.last.at == cue.at) {
      final previous = grouped.removeLast();
      grouped.add((
        at: cue.at,
        end: cue.end > previous.end ? cue.end : previous.end,
        text: [...previous.text, ...cue.text],
      ));
    } else {
      grouped.add((at: cue.at, end: cue.end, text: cue.text));
    }
  }
  String stamp(Duration at) =>
      '[${at.inMinutes.toString().padLeft(2, '0')}:${(at.inSeconds % 60).toString().padLeft(2, '0')}.${(at.inMilliseconds % 1000).toString().padLeft(3, '0')}]';
  final output = <String>[];
  for (var i = 0; i < grouped.length; i++) {
    final cue = grouped[i];
    for (final line in cue.text.isEmpty ? [''] : cue.text) {
      output.add('${stamp(cue.at)}$line');
    }
    // Do not keep the last sung line highlighted through an instrumental gap.
    if (cue.end > cue.at &&
        (i + 1 == grouped.length || grouped[i + 1].at > cue.end)) {
      output.add(stamp(cue.end));
    }
  }
  return output.join('\n');
}
