import 'dart:convert';
import 'dart:typed_data';

/// Only complete, bounded metadata regions are passed here, never audio cache
/// fragments. Parsing is independent of filenames and network credentials.
class EmbeddedTags {
  const EmbeddedTags({this.cover, this.lyrics});
  final Uint8List? cover;
  final String? lyrics;
}

int tagUint(List<int> b, int p, int n, {bool syncSafe = false}) {
  if (p < 0 || p + n > b.length) throw const FormatException('标签截断');
  var value = 0;
  for (var i = p; i < p + n; i++) {
    if (syncSafe && b[i] > 127) throw const FormatException('无效标签长度');
    value = (value << (syncSafe ? 7 : 8)) | b[i];
  }
  return value;
}

String _text(List<int> b, int encoding, {bool? littleEndian}) {
  if (encoding == 0) return latin1.decode(b).replaceAll('\u0000', '').trim();
  if (encoding == 3) return utf8.decode(b).replaceAll('\u0000', '').trim();
  var start = 0;
  var little = littleEndian ?? (encoding == 1);
  if (b.length >= 2) {
    if (b[0] == 255 && b[1] == 254) {
      little = true;
      start = 2;
    }
    if (b[0] == 254 && b[1] == 255) {
      little = false;
      start = 2;
    }
  }
  final units = <int>[];
  for (var p = start; p + 1 < b.length; p += 2) {
    final value = little ? b[p] | b[p + 1] << 8 : b[p] << 8 | b[p + 1];
    if (value != 0) units.add(value);
  }
  return String.fromCharCodes(units).trim();
}

int _terminated(List<int> b, int p, int encoding) {
  final width = encoding == 1 || encoding == 2 ? 2 : 1;
  for (; p + width <= b.length; p += width) {
    if (b[p] == 0 && (width == 1 || b[p + 1] == 0)) return p + width;
  }
  throw const FormatException('标签字符串未终止');
}

Uint8List _unsync(List<int> b) => Uint8List.fromList([
  for (var i = 0; i < b.length; i++)
    if (!(i > 0 && b[i] == 0 && b[i - 1] == 255)) b[i],
]);

EmbeddedTags parseId3Tags(Uint8List input) {
  final version = input[3];
  if (version < 2 || version > 4) return const EmbeddedTags();
  final size = tagUint(input, 6, 4, syncSafe: true);
  var b = Uint8List.sublistView(input, 10, 10 + size);
  // v2.4 frame sizes describe stored bytes; remove unsynchronisation only
  // after locating each frame. v2.3 applies it to the entire tag body.
  if (version < 4 && input[5] & 128 != 0) b = _unsync(b);
  var p = 0;
  if (input[5] & 64 != 0 && version >= 3) {
    final length = tagUint(b, 0, 4, syncSafe: version == 4);
    p = version == 4 ? length : length + 4;
  }
  Uint8List? cover;
  var front = false;
  String? plain, timed;
  final header = version == 2 ? 6 : 10;
  while (p + header <= b.length && b[p] != 0) {
    final id = latin1.decode(b.sublist(p, p + (version == 2 ? 3 : 4)));
    final length = tagUint(
      b,
      p + (version == 2 ? 3 : 4),
      version == 2 ? 3 : 4,
      syncSafe: version == 4,
    );
    final flags = version == 2 ? 0 : tagUint(b, p + 8, 2);
    p += header;
    if (length <= 0 || p + length > b.length) {
      throw const FormatException('标签帧截断');
    }
    var frame = Uint8List.sublistView(b, p, p + length);
    p += length;
    // Compressed/encrypted/grouped frames need additional decoding; do not
    // interpret their prefixes as image or text bytes.
    if ((version == 3 && flags & 0xe0 != 0) ||
        (version == 4 && flags & 0x4d != 0)) {
      continue;
    }
    if (version == 4 && (flags & 2 != 0 || input[5] & 128 != 0)) {
      frame = _unsync(frame);
    }
    try {
      if (frame.isEmpty || frame[0] > 3) continue;
      final enc = frame[0];
      if (id == 'APIC' || id == 'PIC') {
        var q = id == 'PIC' ? 4 : _terminated(frame, 1, 0);
        final type = frame[q++];
        q = _terminated(frame, q, enc);
        if (q < frame.length && (!front || type == 3)) {
          cover = Uint8List.fromList(frame.sublist(q));
          front = type == 3;
        }
      } else if (id == 'USLT' || id == 'ULT') {
        final q = _terminated(frame, 4, enc);
        final text = _text(
          frame.sublist(q),
          enc,
          littleEndian:
              enc == 1 && frame.length > 5 && frame[4] == 254 && frame[5] == 255
              ? false
              : null,
        );
        if (text.isNotEmpty) plain = text;
      } else if (id == 'SYLT' || id == 'SLT') {
        // Timestamp format 2 is milliseconds. MPEG-frame timestamps cannot
        // be converted correctly without audio frame timing.
        if (frame[4] != 2) continue;
        var q = _terminated(frame, 6, enc);
        final lines = <String>[];
        while (q < frame.length) {
          final end = _terminated(frame, q, enc);
          final text = _text(frame.sublist(q, end), enc);
          final ms = tagUint(frame, end, 4);
          lines.add(
            '[${(ms ~/ 60000).toString().padLeft(2, '0')}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}.${(ms % 1000).toString().padLeft(3, '0')}]$text',
          );
          q = end + 4;
        }
        if (lines.isNotEmpty) timed = lines.join('\n');
      } else if (id == 'TXXX' || id == 'TXX') {
        final q = _terminated(frame, 1, enc);
        final name = _text(frame.sublist(1, q), enc).toUpperCase();
        if (['LYRICS', 'UNSYNCEDLYRICS', 'UNSYNCED LYRICS'].contains(name)) {
          plain ??= _text(frame.sublist(q), enc);
        }
      }
    } on FormatException {
      /* A bad optional frame must not hide other tags. */
    } on RangeError {
      /* Ignore malformed optional frames. */
    }
  }
  return EmbeddedTags(cover: cover, lyrics: timed ?? plain);
}

EmbeddedTags parseFlacTags(Uint8List b) {
  Uint8List? cover;
  String? lyrics;
  var p = 4, front = false;
  while (p + 4 <= b.length) {
    final type = b[p] & 127, last = b[p] & 128 != 0;
    final length = tagUint(b, p + 1, 3);
    p += 4;
    final end = p + length;
    if (end > b.length) throw const FormatException('FLAC 标签截断');
    if (type == 4) {
      final data = ByteData.sublistView(b, p, end);
      var q = 4 + data.getUint32(0, Endian.little);
      final count = data.getUint32(q, Endian.little);
      q += 4;
      for (var i = 0; i < count; i++) {
        final n = data.getUint32(q, Endian.little);
        q += 4;
        if (q + n > length) throw const FormatException('Vorbis 标签截断');
        final text = utf8.decode(b.sublist(p + q, p + q + n));
        q += n;
        final eq = text.indexOf('=');
        if (eq < 0) continue;
        final name = text.substring(0, eq).toUpperCase();
        if ([
          'LYRICS',
          'UNSYNCEDLYRICS',
          'UNSYNCED LYRICS',
          'SYNCEDLYRICS',
        ].contains(name)) {
          lyrics = text.substring(eq + 1).trim();
        }
        if (name == 'METADATA_BLOCK_PICTURE') {
          cover ??= _flacPicture(
            Uint8List.fromList(base64Decode(text.substring(eq + 1))),
          ).bytes;
        }
      }
    } else if (type == 6) {
      final image = _flacPicture(Uint8List.sublistView(b, p, end));
      if (!front || image.type == 3) {
        cover = image.bytes;
        front = image.type == 3;
      }
    }
    p = end;
    if (last) break;
  }
  return EmbeddedTags(cover: cover, lyrics: lyrics);
}

({int type, Uint8List bytes}) _flacPicture(Uint8List b) {
  final type = tagUint(b, 0, 4);
  var p = 8 + tagUint(b, 4, 4);
  p += 4 + tagUint(b, p, 4);
  p += 16;
  final n = tagUint(b, p, 4);
  p += 4;
  return (type: type, bytes: Uint8List.fromList(b.sublist(p, p + n)));
}

EmbeddedTags parseMp4Tags(Uint8List b) {
  Uint8List? cover;
  String? lyrics;
  void walk(int start, int end, int depth, [String? parent]) {
    if (depth > 12) throw const FormatException('MP4 标签嵌套过深');
    for (var p = start; p + 8 <= end;) {
      var size = tagUint(b, p, 4), head = 8;
      final type = latin1.decode(b.sublist(p + 4, p + 8));
      if (size == 1) {
        size = tagUint(b, p + 8, 8);
        head = 16;
      }
      if (size == 0) size = end - p;
      if (size < head || p + size > end) {
        throw const FormatException('MP4 标签截断');
      }
      final data = p + head, next = p + size;
      if (type == 'data' && next >= data + 8) {
        if (parent == 'covr') {
          cover ??= Uint8List.fromList(b.sublist(data + 8, next));
        }
        if (parent == '©lyr') {
          lyrics = utf8.decode(b.sublist(data + 8, next)).trim();
        }
      } else if (['moov', 'udta', 'ilst', 'covr', '©lyr'].contains(type)) {
        walk(data, next, depth + 1, type);
      } else if (type == 'meta') {
        walk(data + 4, next, depth + 1, type);
      }
      p = next;
    }
  }

  walk(0, b.length, 0);
  return EmbeddedTags(cover: cover, lyrics: lyrics);
}
