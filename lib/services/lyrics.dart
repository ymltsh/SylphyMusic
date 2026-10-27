class LrcLine {
  const LrcLine(this.at, this.text);
  final Duration at;
  final String text;
}

List<LrcLine> parseLrc(String source) {
  final result = <LrcLine>[];
  final time = RegExp(r'\[(\d{1,6}):(\d{2})(?:\.(\d{1,3}))?\]');
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
    final text = raw.replaceAll(time, '').trim();
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
    if (at == null || end == null || end <= at) continue;
    cues.add((at: at, end: end, text: lines, order: cues.length));
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
    if (i + 1 == grouped.length || grouped[i + 1].at > cue.end) {
      output.add(stamp(cue.end));
    }
  }
  return output.join('\n');
}
