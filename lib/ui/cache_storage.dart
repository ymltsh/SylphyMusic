import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../services/unified_cache_quota.dart';

class _CacheListResult {
  const _CacheListResult(this.rows, this.usage);
  final List<Map<String, Object?>> rows;
  final CacheUsage usage;
}

class CacheStoragePage extends StatefulWidget {
  const CacheStoragePage({super.key, required this.app});
  final SylphyApp app;
  @override
  State<CacheStoragePage> createState() => _CacheStoragePageState();
}

class _CacheStoragePageState extends State<CacheStoragePage> {
  String? sourceId;
  final selected = <String>{};
  late Future<_CacheListResult> records = _load();
  String _size(int bytes) => bytes < 1048576
      ? '${(bytes / 1024).toStringAsFixed(1)} KiB'
      : '${(bytes / 1048576).toStringAsFixed(2)} MiB';

  Future<_CacheListResult> _load() async {
    final db = widget.app.db.db;
    final indexed = <String, Map<String, Object?>>{};
    Map<String, Object?> rowFor(String key) => indexed.putIfAbsent(
      key,
      () => {
        'track_key': key,
        'source': TrackRef.parse(key).sourceId,
        'title': '不可用歌曲',
        'album': '',
        'audio_bytes': 0,
        'cover_bytes': 0,
        'lyrics_bytes': 0,
        'manual_bytes': 0,
        'cover_shared': false,
        'last_used': 0,
      },
    );
    for (final audio in await db.query('cache')) {
      final row = rowFor(audio['track_key'] as String);
      row['audio_bytes'] = audio['bytes'];
      row['last_used'] = audio['last_used'];
    }
    final links = await db.rawQuery('''
      SELECT l.track_key,l.kind,l.source_id,l.asset_key,
             a.bytes,a.last_used,a.relative_file
      FROM cache_asset_links l JOIN media_assets a
      ON l.source_id=a.source_id AND l.asset_key=a.asset_key
    ''');
    final users = <String, Set<String>>{};
    for (final link in links) {
      final assetId = '${link['source_id']}/${link['asset_key']}';
      users
          .putIfAbsent(assetId, () => <String>{})
          .add(link['track_key'] as String);
    }
    for (final link in links) {
      final row = rowFor(link['track_key'] as String);
      final kind = link['kind'] as String;
      final bytes = link['bytes'] as int;
      final field = kind == 'cover' ? 'cover_bytes' : 'lyrics_bytes';
      row[field] = (row[field] as int) + bytes;
      if (kind == 'manual') {
        row['manual_bytes'] = (row['manual_bytes'] as int) + bytes;
      }
      if (kind == 'cover') {
        final assetId = '${link['source_id']}/${link['asset_key']}';
        if ((users[assetId]?.length ?? 0) > 1) row['cover_shared'] = true;
      }
      final at = link['last_used'] as int;
      if (at > (row['last_used'] as int)) row['last_used'] = at;
    }
    // Read only cached tracks' display metadata; never load the whole library.
    final refs = indexed.keys.map(TrackRef.parse).toList();
    for (var i = 0; i < refs.length; i += 150) {
      final batch = refs.skip(i).take(150).toList();
      final matches = List.filled(
        batch.length,
        '(source_id=? AND id=?)',
      ).join(' OR ');
      final tracks = await db.query(
        'tracks',
        columns: ['source_id', 'id', 'title', 'album'],
        where: matches,
        whereArgs: [
          for (final ref in batch) ...[ref.sourceId, ref.id],
        ],
      );
      for (final track in tracks) {
        final key = TrackRef(
          track['source_id'] as String,
          track['id'] as String,
        ).key;
        final row = indexed[key];
        if (row == null) continue;
        row['title'] = track['title'] ?? '未知歌曲';
        row['album'] = track['album'] ?? '';
      }
    }
    final rows = indexed.values.toList()
      ..sort(
        (a, b) => (b['last_used'] as int).compareTo(a['last_used'] as int),
      );
    return _CacheListResult(rows, await widget.app.cache.quota.usage());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('缓存空间'),
      actions: [
        IconButton(
          tooltip: '清理选中的音频、封面和远程歌词',
          onPressed: selected.isEmpty ? null : _clear,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
    body: FutureBuilder<_CacheListResult>(
      future: records,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snapshot.data!.rows;
        final usage = snapshot.data!.usage;
        final rows = all
            .where((r) => sourceId == null || r['source'] == sourceId)
            .toList();
        final bytes = usage.total;
        return Column(
          children: [
            ListTile(
              title: Text(
                '${(bytes / 1073741824).toStringAsFixed(2)} / ${(widget.app.cache.maxBytes / 1073741824).toStringAsFixed(1)} GiB',
              ),
              subtitle: Text(
                '${all.length} 首关联歌曲 · 音频 ${_size(usage.audio)} · '
                '封面 ${_size(usage.cover)} · 歌词 ${_size(usage.lyrics)}',
              ),
              trailing: PopupMenuButton<String>(
                tooltip: '按来源筛选',
                icon: const Icon(Icons.filter_list),
                onSelected: (id) =>
                    setState(() => sourceId = id == 'all' ? null : id),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'all', child: Text('全部来源')),
                  ...widget.app.sources.map(
                    (s) => PopupMenuItem(value: s.id, child: Text(s.name)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(
                value: (bytes / widget.app.cache.maxBytes).clamp(0, 1),
              ),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(
                    () => selected.addAll(
                      rows.map((r) => r['track_key'] as String),
                    ),
                  ),
                  child: const Text('选择当前列表'),
                ),
                TextButton(
                  onPressed: () => setState(selected.clear),
                  child: const Text('取消选择'),
                ),
                Text('已选 ${selected.length} 首'),
              ],
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('没有缓存资源'))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final key = row['track_key'] as String;
                        final audio = row['audio_bytes'] as int;
                        final cover = row['cover_bytes'] as int;
                        final lyrics = row['lyrics_bytes'] as int;
                        final manual = row['manual_bytes'] as int;
                        return ExpansionTile(
                          key: ValueKey(key),
                          leading: Checkbox(
                            value: selected.contains(key),
                            onChanged: (value) => setState(() {
                              if (value == true) {
                                selected.add(key);
                              } else {
                                selected.remove(key);
                              }
                            }),
                          ),
                          title: Text(
                            row['title'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${row['album']} · 资源引用 ${_size(audio + cover + lyrics)}',
                          ),
                          children: [
                            ListTile(
                              title: const Text('歌曲音频'),
                              trailing: Text(_size(audio)),
                            ),
                            ListTile(
                              title: const Text('专辑封面'),
                              subtitle: row['cover_shared'] == true
                                  ? const Text('共享文件，全局占用只计算一次')
                                  : null,
                              trailing: Text(_size(cover)),
                            ),
                            ListTile(
                              title: const Text('歌词'),
                              subtitle: manual > 0
                                  ? Text('包含受保护的手动歌词 ${_size(manual)}')
                                  : null,
                              trailing: Text(_size(lyrics)),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
  Future<void> _clear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理缓存'),
        content: Text(
          '清理选中的 ${selected.length} 首歌曲关联的音频、封面和远程歌词，并取消相关任务。'
          '共享封面仍被其他歌曲引用时保留；手动歌词和原始文件不受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await widget.app.clearCache(keys: {...selected});
    if (mounted) {
      setState(() {
        selected.clear();
        records = _load();
      });
    }
  }
}
