import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../data/library_catalog.dart';
import 'cover_art.dart';
import 'library_browser.dart';
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
  late int revision;
  @override
  void initState() {
    super.initState();
    revision = widget.app.catalogRevision;
    albums = _albums();
  }

  Future<CatalogPage> _albums() =>
      widget.app.catalog.page(const CatalogQuery(view: 1), limit: 8);
  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (revision != widget.app.catalogRevision) {
      revision = widget.app.catalogRevision;
      albums = _albums();
    }
  }

  Widget _shortcut(IconData icon, String title, VoidCallback tap) =>
      Card.filled(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: tap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final app = widget.app, scheme = Theme.of(context).colorScheme;
    final current = app.playback.current;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
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
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      app.sources.isEmpty
                          ? '从连接音乐库开始，让喜欢的声音常伴左右。'
                          : '音乐随心，聆听自在。',
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: app.sources.isEmpty
                          ? widget.onSources
                          : () => widget.onLibrary(0),
                      icon: Icon(
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
                    size: 80,
                    color: scheme.primary.withValues(alpha: .5),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, size) {
            final columns = size.maxWidth > 540 ? 4 : 2;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: columns,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: size.maxWidth / columns / 110,
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
        const SizedBox(height: 24),
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
        const SizedBox(height: 10),
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
            return SizedBox(
              height: 208,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: snapshot.data!.rows.length,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  final row = snapshot.data!.rows[index], track = row.track;
                  return SizedBox(
                    width: 144,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(
                              title: Text(
                                track.album.isEmpty ? '未知专辑' : track.album,
                              ),
                            ),
                            body: LibraryBrowser(
                              app: app,
                              query: const CatalogQuery(view: 1)
                                  .songsIn('album', row.key),
                              onAction: widget.onAction,
                            ),
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CoverArt(app: app, track: track, size: 144),
                          const SizedBox(height: 10),
                          Text(
                            track.album.isEmpty ? '未知专辑' : track.album,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            track.albumArtist.isEmpty
                                ? track.artist
                                : track.albumArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
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
                    MaterialPageRoute(builder: (_) => NowPlayingPage(app: app)),
                  ),
          ),
        ),
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
          return ListTile(
            leading: CoverArt(app: widget.app, track: track),
            title: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(track.artist),
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
