class LrcLine {
  const LrcLine(this.at, this.text);
  final Duration at;
  final String text;
}

List<LrcLine> parseLrc(String source) {
  final result = <LrcLine>[];
  final time = RegExp(r'\[(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?\]');
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
  result.sort((a, b) => a.at.compareTo(b.at));
  return result;
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
