import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../data/library_catalog.dart';
import '../core/recommendation_models.dart';
import 'daily_mix_page.dart';
import 'cover_art.dart';
import 'library_browser.dart';
import 'playing_song_tile.dart';
import 'now_playing.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.app,
    required this.onLibrary,
    required this.onFavorites,
    required this.onDownloads,
    required this.onSources,
    required this.onAction,
  });
  final SylphyApp app;
  final void Function(int) onLibrary;
  final VoidCallback onFavorites, onDownloads, onSources;
  final Future<void> Function(String, Track) onAction;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<CatalogPage> albums;
  late Future<DailyMix> dailyMix;
  final Map<String, String> _albumReasons = {};
  late int revision;
  int _albumRefreshEpoch = 0;

  @override
  void initState() {
    super.initState();
    revision = widget.app.catalogRevision;
    albums = _albums();
    dailyMix = widget.app.recommendations.daily();
    widget.app.catalogListenable.addListener(_catalogChanged);
  }

  Future<CatalogPage> _albums() async {
    final recommended = await widget.app.recommendations.albums();
    if (recommended.isNotEmpty) {
      _albumReasons
        ..clear()
        ..addEntries(
          recommended.map(
            (item) => MapEntry(
              '${item.representative.ref.sourceId}|${item.groupKey}',
              item.reason,
            ),
          ),
        );
      return CatalogPage([
        for (final item in recommended)
          CatalogRow({
            ...item.representative.toRow(),
            'catalog_key': item.groupKey,
            'catalog_count': item.trackCount,
            'catalog_sources': 1,
          }),
      ], recommended.length);
    }
    final named = await widget.app.catalog.page(
      const CatalogQuery(view: 1, namedAlbumsOnly: true),
      limit: 8,
    );
    if (named.rows.isNotEmpty) return named;
    return widget.app.catalog.page(const CatalogQuery(view: 1), limit: 8);
  }

  void _catalogChanged() {
    if (!mounted || revision == widget.app.catalogRevision) return;
    revision = widget.app.catalogRevision;
    unawaited(_refreshAlbums(++_albumRefreshEpoch));
  }

  Future<void> _refreshAlbums(int epoch) async {
    try {
      final updated = await _albums();
      if (!mounted || epoch != _albumRefreshEpoch) return;
      // Retain the visible cards while WebDAV tags are being written.
      setState(() {
        albums = SynchronousFuture(updated);
        dailyMix = widget.app.recommendations.daily();
      });
    } catch (_) {
      // A failed background refresh must not replace the current cards.
    }
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.app, widget.app)) {
      oldWidget.app.catalogListenable.removeListener(_catalogChanged);
      widget.app.catalogListenable.addListener(_catalogChanged);
    }
    if (!identical(oldWidget.app, widget.app) ||
        revision != widget.app.catalogRevision) {
      ++_albumRefreshEpoch;
      revision = widget.app.catalogRevision;
      albums = _albums();
      dailyMix = widget.app.recommendations.daily();
    }
  }

  @override
  void dispose() {
    widget.app.catalogListenable.removeListener(_catalogChanged);
    super.dispose();
  }

  bool _exploring = false;

  Future<void> _exploreLibrary() async {
    final app = widget.app;
    if (_exploring) return;
    if (app.sources.isEmpty) {
      widget.onSources();
      return;
    }
    setState(() => _exploring = true);
    try {
      final tracks = await app.catalog.queue(const CatalogQuery());
      if (!mounted) return;
      if (tracks.isEmpty) {
        widget.onLibrary(0);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('音乐库暂无可播放的歌曲')));
        return;
      }
      tracks.shuffle(Random());
      await app.playback.setQueue(tracks);
      if (mounted) widget.onLibrary(0);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('随机播放失败，请检查音乐来源')));
      }
    } finally {
      if (mounted) setState(() => _exploring = false);
    }
  }

  Widget _shortcut(IconData icon, String title, VoidCallback tap) {
    final desktop = MediaQuery.sizeOf(context).width > 750;
    final content = InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: tap,
      child: Padding(
        padding: EdgeInsets.all(desktop ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            SizedBox(height: desktop ? 7 : 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
    return desktop
        ? Card.outlined(margin: EdgeInsets.zero, child: content)
        : Card.filled(margin: EdgeInsets.zero, child: content);
  }

  Widget _albumCard(CatalogRow row, double size) {
    final app = widget.app, track = row.track;
    final artist = track.albumArtist.isEmpty ? track.artist : track.albumArtist;
    final album = track.album.trim().isNotEmpty
        ? track.album
        : (artist.trim().isNotEmpty ? '未分类 · $artist' : '未知专辑');
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(album)),
            body: LibraryBrowser(
              app: app,
              query: CatalogQuery(
                view: 1,
                sourceId: track.ref.sourceId,
                sort: 'track_number',
              ).songsIn('album', row.key),
              onAction: widget.onAction,
            ),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoverArt(app: app, track: track, size: size, borderRadius: 12),
          const SizedBox(height: 6),
          Text(
            album,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            _albumReasons['${track.ref.sourceId}|${row.key}'] == null
                ? artist
                : '$artist · ${_albumReasons['${track.ref.sourceId}|${row.key}']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app, scheme = Theme.of(context).colorScheme;
    final desktop = MediaQuery.sizeOf(context).width > 750;
    final current = app.playback.current;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        desktop ? 24 : 20,
        desktop ? 8 : 12,
        desktop ? 24 : 20,
        desktop ? 24 : 110,
      ),
      children: [
        Container(
          padding: EdgeInsets.all(desktop ? 18 : 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(desktop ? 20 : 28),
            gradient: LinearGradient(
              colors: [
                scheme.primaryContainer,
                scheme.secondaryContainer.withValues(alpha: .45),
              ],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '属于你的音乐时光',
                      style:
                          (desktop
                                  ? Theme.of(context).textTheme.titleLarge
                                  : Theme.of(context).textTheme.headlineSmall)
                              ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: desktop ? 6 : 10),
                    Text(
                      app.apiSettings.quote,
                      maxLines: desktop ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: desktop ? 12 : 20),
                    FilledButton.icon(
                      onPressed: _exploring ? null : _exploreLibrary,
                      icon: _exploring
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              app.sources.isEmpty
                                  ? Icons.add_link
                                  : Icons.play_arrow_rounded,
                            ),
                      label: Text(app.sources.isEmpty ? '连接音乐库' : '探索音乐库'),
                    ),
                  ],
                ),
              ),
              if (MediaQuery.sizeOf(context).width > 460)
                Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: Icon(
                    Icons.air_rounded,
                    size: desktop ? 56 : 80,
                    color: scheme.primary.withValues(alpha: .5),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: desktop ? 14 : 20),
        LayoutBuilder(
          builder: (context, size) {
            final columns = size.maxWidth > 540 ? 4 : 2;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: columns,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: size.maxWidth / columns / (desktop ? 86 : 110),
              children: [
                _shortcut(
                  Icons.queue_music,
                  '最近播放',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('最近播放')),
                        body: ListeningHistoryPage(app: app),
                      ),
                    ),
                  ),
                ),
                _shortcut(Icons.favorite_outline, '我的收藏', widget.onFavorites),
                _shortcut(
                  Icons.library_music_outlined,
                  '全部音乐',
                  () => widget.onLibrary(0),
                ),
                _shortcut(Icons.download_outlined, '本地下载', widget.onDownloads),
              ],
            );
          },
        ),
        SizedBox(height: desktop ? 16 : 24),
        Row(
          children: [
            Expanded(
              child: Text(
                '每日精选',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DailyMixPage(app: app)),
              ),
              child: const Text('查看全部'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<DailyMix>(
          future: dailyMix,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return SizedBox(
                height: 104,
                child: Center(
                  child: snapshot.hasError
                      ? const Text('每日精选暂时不可用')
                      : const CircularProgressIndicator(),
                ),
              );
            }
            final mix = snapshot.data!;
            if (mix.items.isEmpty) {
              return Card.filled(
                child: ListTile(
                  title: const Text('开始聆听，发现曲库里的好音乐'),
                  subtitle: const Text('添加来源或播放歌曲后，精选会更懂你'),
                  onTap: () => widget.onLibrary(0),
                ),
              );
            }
            final first = mix.items.first.track;
            return Card.filled(
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: CoverArt(app: app, track: first, size: 64),
                title: const Text('今天，听点喜欢的'),
                subtitle: Text(
                  '${mix.items.length} 首 · 熟悉的旋律与新的发现',
                  maxLines: 2,
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DailyMixPage(app: app)),
                ),
                trailing: IconButton(
                  tooltip: '播放每日精选',
                  icon: const Icon(Icons.play_circle_fill_rounded),
                  onPressed: () => unawaited(
                    app.playback.setQueue(mix.refs).catchError((Object _) {}),
                  ),
                ),
              ),
            );
          },
        ),
        SizedBox(height: desktop ? 16 : 24),
        Row(
          children: [
            Expanded(
              child: Text(
                '专辑精选',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton(
              onPressed: () => widget.onLibrary(1),
              child: const Text('查看全部'),
            ),
          ],
        ),
        SizedBox(height: desktop ? 6 : 10),
        FutureBuilder<CatalogPage>(
          future: albums,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Text('专辑加载失败，请刷新音乐库后重试。'),
              );
            }
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 170,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.data!.rows.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.album_outlined, size: 36),
                    SizedBox(height: 12),
                    Text('你的下一张心爱专辑，就在这里'),
                    SizedBox(height: 6),
                    Text(
                      '添加来源或导入本地音乐后，专辑会自动出现在这里。',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }
            final rows = snapshot.data!.rows;
            if (!desktop) {
              return SizedBox(
                height: 208,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 16),
                  itemBuilder: (_, index) =>
                      SizedBox(width: 144, child: _albumCard(rows[index], 144)),
                ),
              );
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final columns = (constraints.maxWidth / 152).floor().clamp(
                  3,
                  8,
                );
                final size =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                return SizedBox(
                  height: size + 56,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < columns; i++) ...[
                        if (i != 0) const SizedBox(width: 12),
                        Expanded(
                          child: i < rows.length
                              ? _albumCard(rows[i], size)
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
        // The desktop footer already shows the current track and its controls.
        if (!desktop) ...[
          const SizedBox(height: 24),
          Text('继续播放', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Card.filled(
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: current == null
                  ? const Icon(Icons.headphones_rounded, size: 40)
                  : CoverArt(app: app, track: current, size: 56),
              title: Text(
                current?.title ?? '留一点时间，听喜欢的歌',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(current?.artist ?? '从音乐库中选择一首歌曲开始'),
              trailing: const Icon(Icons.chevron_right),
              onTap: current == null
                  ? () => widget.onLibrary(0)
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NowPlayingPage(app: app),
                      ),
                    ),
            ),
          ),
        ],
      ],
    );
  }
}

class ListeningHistoryPage extends StatefulWidget {
  const ListeningHistoryPage({super.key, required this.app});
  final SylphyApp app;
  @override
  State<ListeningHistoryPage> createState() => _ListeningHistoryPageState();
}

class _ListeningHistoryPageState extends State<ListeningHistoryPage> {
  late Future<List<Track>> tracks = widget.app.history.tracks();
  void _changed() {
    if (mounted) setState(() => tracks = widget.app.history.tracks());
  }

  @override
  void initState() {
    super.initState();
    widget.app.history.addListener(_changed);
    widget.app.addListener(_changed);
  }

  @override
  void dispose() {
    widget.app.history.removeListener(_changed);
    widget.app.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Track>>(
    future: tracks,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('播放记录加载失败，请稍后重试'));
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final items = snapshot.data!;
      if (items.isEmpty) return const Center(child: Text('还没有播放记录，去音乐库听听吧。'));
      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final track = items[index];
          return PlayingSongTile(
            app: widget.app,
            track: track,
            title: track.title,
            subtitle: track.artist,
            onTap: () async {
              try {
                await widget.app.playback.setQueue(
                  items.map((t) => t.ref).toList(),
                  start: index,
                );
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('播放失败，请检查来源状态')));
                }
              }
            },
          );
        },
      );
    },
  );
}
