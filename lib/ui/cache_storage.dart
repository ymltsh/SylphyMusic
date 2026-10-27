import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';

class CacheStoragePage extends StatefulWidget {
  const CacheStoragePage({super.key, required this.app});
  final SylphyApp app;
  @override
  State<CacheStoragePage> createState() => _CacheStoragePageState();
}

class _CacheStoragePageState extends State<CacheStoragePage> {
  String? sourceId;
  final selected = <String>{};
  late Future<List<Map<String, Object?>>> records = _load();
  Future<List<Map<String, Object?>>> _load() async {
    final tracks = {
      for (final track in await widget.app.db.tracks(includeMissing: true))
        track.ref.key: track,
    };
    return [
      for (final row in await widget.app.db.db.query(
        'cache',
        orderBy: 'last_used DESC',
      ))
        {
          ...row,
          'title': tracks[row['track_key']]?.title ?? '不可用歌曲',
          'album': tracks[row['track_key']]?.album ?? '',
          'source': TrackRef.parse(row['track_key'] as String).sourceId,
        },
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('缓存空间'),
      actions: [
        IconButton(
          tooltip: '清理选中的完整缓存',
          onPressed: selected.isEmpty ? null : _clear,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: records,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snapshot.data!,
            rows = all
                .where((r) => sourceId == null || r['source'] == sourceId)
                .toList();
        final bytes = all.fold<int>(
          0,
          (sum, row) => sum + (row['bytes'] as int),
        );
        return Column(
          children: [
            ListTile(
              title: Text(
                '${(bytes / 1073741824).toStringAsFixed(2)} / ${(widget.app.cache.maxBytes / 1073741824).toStringAsFixed(1)} GiB',
              ),
              subtitle: Text('${all.length} 首完整歌曲 · 统一 LRU 自动淘汰'),
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
                  ? const Center(child: Text('没有完整缓存'))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index],
                            key = row['track_key'] as String;
                        return CheckboxListTile(
                          value: selected.contains(key),
                          onChanged: (value) => setState(() {
                            if (value == true) {
                              selected.add(key);
                            } else {
                              selected.remove(key);
                            }
                          }),
                          title: Text(
                            row['title'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${row['album']} · ${((row['bytes'] as int) / 1048576).toStringAsFixed(1)} MiB',
                          ),
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
          '清理选中的 ${selected.length} 首歌曲缓存，并取消相关缓存任务。原始音频不受影响；正在读取的文件会在释放后清理。',
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
