/// One HTTP byte range. Multi-range requests are deliberately rejected.
class ByteRange {
  const ByteRange(this.start, this.end);
  final int start, end;
  int get length => end - start + 1;

  static ByteRange? parse(String? header, int length) {
    if (length <= 0) return null;
    if (header == null) return ByteRange(0, length - 1);
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header);
    if (match == null) return null;
    final first = match.group(1)!;
    final last = match.group(2)!;
    if (first.isEmpty) {
      final suffix = int.tryParse(last);
      if (suffix == null || suffix <= 0) return null;
      return ByteRange(suffix >= length ? 0 : length - suffix, length - 1);
    }
    final start = int.tryParse(first);
    final end = last.isEmpty ? length - 1 : int.tryParse(last);
    if (start == null || end == null || start >= length || end < start) {
      return null;
    }
    return ByteRange(start, end >= length ? length - 1 : end);
  }
}
