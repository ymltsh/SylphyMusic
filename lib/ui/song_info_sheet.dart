import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';

typedef _InfoEntry = ({String label, String value});

/// Details of the indexed track, not the current playback proxy/cache file.
/// Missing server metadata is omitted instead of guessing a local file path.
class SongInfoSheet extends StatelessWidget {
  const SongInfoSheet({super.key, required this.track, this.source});

  final Track track;
  final SourceProfile? source;

  static String? _text(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _number(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String? _duration(int milliseconds) {
    if (milliseconds <= 0) return null;
    final duration = Duration(milliseconds: milliseconds);
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    final minutes = duration.inMinutes % 60;
    return duration.inHours > 0
        ? '${duration.inHours}:${minutes.toString().padLeft(2, '0')}:$seconds'
        : '${duration.inMinutes}:$seconds';
  }

  static String? _size(Object? value) {
    final count = _number(value);
    if (count == null || count <= 0) return null;
    if (count < 1024) return '$count B';
    var amount = count.toDouble();
    var unit = 0;
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    while (amount >= 1024 && unit < units.length - 1) {
      amount /= 1024;
      unit++;
    }
    return '${amount.toStringAsFixed(amount >= 100 ? 0 : 1)} ${units[unit]}';
  }

  static String? _sampleRate(Object? value) {
    final hertz = _number(value);
    if (hertz == null || hertz <= 0) return null;
    if (hertz < 1000) return '$hertz Hz';
    final kHz = hertz / 1000;
    return '${kHz.toStringAsFixed(hertz % 1000 == 0 ? 0 : 1)} kHz';
  }

  static String? _bitRate(Object? value) {
    final bps = _number(value);
    if (bps == null || bps <= 0) return null;
    if (bps < 1000) return '$bps bps';
    final kbps = bps / 1000;
    return '${kbps.toStringAsFixed(bps % 1000 == 0 ? 0 : 1)} kbps';
  }

  static String? _genres(Object? value) {
    if (value is! List) return null;
    final genres = value
        .map((item) => item is Map ? _text(item['Name']) : _text(item))
        .whereType<String>()
        .toList();
    return genres.isEmpty ? null : genres.join(' / ');
  }

  static String? _filename(String? path) {
    if (path == null) return null;
    final separator = path.lastIndexOf('/') > path.lastIndexOf('\\')
        ? path.lastIndexOf('/')
        : path.lastIndexOf('\\');
    return _text(path.substring(separator + 1));
  }

  static String? _directory(String? path) {
    if (path == null) return null;
    final separator = path.lastIndexOf('/') > path.lastIndexOf('\\')
        ? path.lastIndexOf('/')
        : path.lastIndexOf('\\');
    if (separator < 0) return null;
    if (separator == 0) return path.substring(0, 1);
    if (separator == 2 && path.length >= 3 && path[1] == ':') {
      return path.substring(0, 3);
    }
    return path.substring(0, separator);
  }

  String? _path(Map? media) {
    if (source?.kind == SourceKind.webdav) {
      try {
        final segments = Uri.parse(track.ref.id).pathSegments;
        return segments.isEmpty ? null : segments.join('/');
      } on FormatException {
        return null;
      }
    }
    final path =
        _text(track.remote['Path']) ??
        _text(media?['Path']) ??
        _text(track.remote['path']);
    // Never display an authenticated streaming URL as an original file path.
    if (path != null &&
        RegExp(r'^https?://', caseSensitive: false).hasMatch(path)) {
      return null;
    }
    return path;
  }

  static void _add(List<_InfoEntry> target, String label, Object? value) {
    final text = _text(value);
    if (text != null) target.add((label: label, value: text));
  }

  Widget _section(
    BuildContext context,
    String title,
    List<_InfoEntry> entries, {
    bool allowCopy = false,
  }) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: colors.primary, fontWeight: FontWeight.w600),
          ),
        ),
        for (final entry in entries)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(entry.label),
            subtitle: SelectableText(entry.value),
            trailing: allowCopy
                ? IconButton(
                    tooltip: '复制${entry.label}',
                    icon: const Icon(Icons.copy_outlined, size: 20),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: entry.value)),
                  )
                : null,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final remote = track.remote;
    final media = (remote['MediaSources'] as List?)
        ?.whereType<Map>()
        .firstOrNull;
    final streams = (remote['MediaStreams'] ?? media?['MediaStreams']) as List?;
    final audio = streams
        ?.whereType<Map>()
        .where((stream) => stream['Type'] == 'Audio')
        .firstOrNull;
    final path = _path(media);
    final filename =
        _text(remote['FileName']) ??
        _text(remote['fileName']) ??
        _filename(path);

    final basics = <_InfoEntry>[];
    _add(basics, '歌曲', track.title);
    _add(basics, '艺术家', track.artist);
    _add(basics, '专辑', track.album);
    _add(basics, '专辑艺术家', track.albumArtist);
    _add(basics, '时长', _duration(track.durationMs));
    if (track.year > 0) _add(basics, '年份', track.year);
    if (track.disc > 0) _add(basics, '碟号', track.disc);
    if (track.number > 0) _add(basics, '曲号', track.number);
    _add(basics, '流派', _genres(remote['Genres'] ?? remote['genre']));

    final quality = <_InfoEntry>[];
    _add(
      quality,
      '格式',
      _text(remote['format'])?.toUpperCase() ??
          _text(remote['Container'])?.toUpperCase() ??
          _text(media?['Container'])?.toUpperCase(),
    );
    _add(quality, '编码', _text(audio?['Codec'])?.toUpperCase());
    _add(
      quality,
      '采样率',
      _sampleRate(remote['sampleRate'] ?? audio?['SampleRate']),
    );
    _add(
      quality,
      '比特率',
      _bitRate(remote['bitrate'] ?? audio?['BitRate'] ?? media?['Bitrate']),
    );
    final bitDepth = _number(remote['bitDepth'] ?? audio?['BitDepth']);
    if (bitDepth != null && bitDepth > 0) _add(quality, '位深', '$bitDepth bit');
    final channels = _number(audio?['Channels']);
    if (channels != null && channels > 0) _add(quality, '声道数', '$channels');
    _add(quality, '声道布局', audio?['ChannelLayout']);
    _add(
      quality,
      '文件大小',
      _size(remote['size'] ?? remote['Size'] ?? media?['Size']),
    );

    final files = <_InfoEntry>[];
    _add(files, '原始文件名', filename);
    _add(files, '所在目录', _directory(path));
    _add(files, source?.kind == SourceKind.webdav ? '来源内相对路径' : '文件路径', path);

    const kindNames = {
      SourceKind.emby: 'Emby',
      SourceKind.subsonic: 'OpenSubsonic',
      SourceKind.local: '本地音乐',
      SourceKind.webdav: 'WebDAV',
      SourceKind.fnMusic: '飞牛音乐',
    };
    final origin = <_InfoEntry>[];
    _add(origin, '音源名称', source?.name);
    _add(origin, '音源类型', source == null ? null : kindNames[source!.kind]);
    _add(origin, '歌曲 ID', track.ref.id);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
              children: [
                Text('歌曲信息', style: Theme.of(context).textTheme.titleLarge),
                _section(context, '基本信息', basics),
                _section(context, '音频信息', quality),
                _section(context, '文件信息', files, allowCopy: true),
                _section(context, '来源信息', origin),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
