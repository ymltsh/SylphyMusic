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
  const MusicSourceIcon({
    super.key,
    required this.kind,
    this.source,
    this.size = 48,
  });

  final SourceKind kind;
  final SourceProfile? source;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brand = sourceBrandFor(kind, source: source);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          brand.color.withValues(alpha: .10),
          colors.surfaceContainerLow,
        ),
        borderRadius: BorderRadius.circular(size * .3),
      ),
      child: Padding(
        padding: EdgeInsets.all(size * .15),
        child: brand.asset == null
            ? Icon(
                sourceOptionFor(kind).icon,
                color: brand.color,
                size: size * .53,
              )
            : Image.asset(
                brand.asset!,
                fit: BoxFit.contain,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .round()
                    .clamp(1, 512),
                errorBuilder: (_, _, _) =>
                    Icon(sourceOptionFor(kind).icon, color: brand.color),
              ),
      ),
    );
  }
}

/// Brand artwork and its visible accent colors, independent of stored identity.
class MusicSourceBrand {
  const MusicSourceBrand(this.asset, this.color, this.secondary);
  final String? asset;
  final Color color, secondary;
}

const openListSourceBrand = MusicSourceBrand(
  'assets/source/openlist.png',
  Color(0xff75d6cb),
  Color(0xff12add8),
);

MusicSourceBrand sourceBrandFor(SourceKind kind, {SourceProfile? source}) {
  if (kind == SourceKind.webdav && source != null) {
    final uri = Uri.tryParse(source.url);
    if (uri != null &&
        const ['127.0.0.1', 'localhost', '::1'].contains(uri.host) &&
        uri.port == 10486) {
      return openListSourceBrand;
    }
  }
  return switch (kind) {
    SourceKind.emby => const MusicSourceBrand(
      'assets/source/emby.png',
      Color(0xff51b347),
      Color(0xff9ad962),
    ),
    SourceKind.subsonic => const MusicSourceBrand(
      'assets/source/navidrome.png',
      Color(0xff008bfa),
      Color(0xff32b6f2),
    ),
    SourceKind.fnMusic => const MusicSourceBrand(
      'assets/source/fnos.png',
      Color(0xff3273dd),
      Color(0xff77a8f1),
    ),
    SourceKind.webdav => const MusicSourceBrand(
      'assets/source/webdav.png',
      Color(0xff377ef6),
      Color(0xff75b8fa),
    ),
    SourceKind.local => const MusicSourceBrand(
      null,
      Color(0xff9275c5),
      Color(0xffc09edb),
    ),
  };
}
