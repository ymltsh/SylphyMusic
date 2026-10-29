import 'package:flutter/material.dart';

import '../core/models.dart';

/// Display metadata only. Never use labels as persisted source identities.
class MusicSourceOption {
  const MusicSourceOption(this.kind, this.title, this.description, this.icon);

  final SourceKind kind;
  final String title;
  final String description;
  final IconData icon;
}

const musicSourceOptions = <MusicSourceOption>[
  MusicSourceOption(
    SourceKind.emby,
    'Emby',
    '连接 Emby 私人媒体服务器',
    Icons.dns_outlined,
  ),
  MusicSourceOption(
    SourceKind.subsonic,
    'Navidrome / OpenSubsonic',
    '连接兼容 OpenSubsonic 协议的音乐库',
    Icons.cloud_outlined,
  ),
  MusicSourceOption(
    SourceKind.fnMusic,
    '飞牛音乐（fnOS）',
    '连接 NAS 上的原生飞牛音乐曲库',
    Icons.library_music_outlined,
  ),
  MusicSourceOption(
    SourceKind.webdav,
    'WebDAV',
    '读取远程音乐文件与文件夹',
    Icons.folder_shared_outlined,
  ),
  MusicSourceOption(
    SourceKind.local,
    '本地音乐',
    '导入音频文件或添加本地文件夹',
    Icons.folder_outlined,
  ),
];

MusicSourceOption sourceOptionFor(SourceKind kind) =>
    musicSourceOptions.firstWhere((option) => option.kind == kind);

/// Compact rounded icon container, styled by the active Sylphy theme.
class MusicSourceIcon extends StatelessWidget {
  const MusicSourceIcon({super.key, required this.kind, this.size = 48});

  final SourceKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(size * .3),
      ),
      child: Icon(
        sourceOptionFor(kind).icon,
        color: colors.onPrimaryContainer,
        size: size * .53,
      ),
    );
  }
}
