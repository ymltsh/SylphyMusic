import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../data/cache_catalog.dart';
import '../services/unified_cache_quota.dart';

class _CacheListResult {
  const _CacheListResult(this.catalog, this.usage);
  final CacheCatalogResult catalog;
  List<Map<String, Object?>> get rows => catalog.rows;
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
  final _search = TextEditingController();
  String _query = '';
  Timer? _searchDebounce;
  String _sort = 'recent';
  bool _clearing = false;
  final selected = <String>{};
  late Future<_CacheListResult> records = _load();
  String _size(int bytes) {
    if (bytes == 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    if (bytes < 1073741824) {
      return '${(bytes / 1048576).toStringAsFixed(1)} MiB';
    }
    return '${(bytes / 1073741824).toStringAsFixed(2)} GiB';
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  String _sourceName(String id) {
    for (final source in widget.app.sources) {
      if (source.id == id) return source.name;
    }
    return '已移除的来源';
  }

  int _rowBytes(Map<String, Object?> row) =>
      (row['audio_bytes'] as int) +
      (row['cover_bytes'] as int) +
      (row['lyrics_bytes'] as int);

  void _reload() {
    _searchDebounce?.cancel();
    setState(() {
      selected.clear();
      records = _load();
    });
  }

  void _searchChanged(String value) {
    _searchDebounce?.cancel();
    setState(() {
      _query = value.trim();
      selected.clear();
    });
    // Keep the field mounted while typing; coalesce database reads.
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => records = _load());
    });
  }

  Future<_CacheListResult> _load() async {
    final catalog = await CacheCatalog(widget.app.db)
        .query(search: _query, sourceId: sourceId, sort: _sort);
    return _CacheListResult(catalog, await widget.app.cache.quota.usage());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('管理音乐缓存'),
      actions: [
        IconButton(
          tooltip: '刷新缓存',
          onPressed: _clearing ? null : _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 8),
      ],
    ),
    bottomNavigationBar: selected.isEmpty ? null : _selectionBar(),
    body: SafeArea(
      top: false,
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: AbsorbPointer(
            absorbing: _clearing,
            child: FutureBuilder<_CacheListResult>(
              future: records,
              builder: (context, snapshot) {
                if (!snapshot.hasData &&
                    snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _emptyState(
                    Icons.cloud_off_outlined,
                    '暂时无法读取缓存',
                    '请稍后刷新重试',
                    action: TextButton(
                      onPressed: _reload,
                      child: const Text('重试'),
                    ),
                  );
                }
                final data = snapshot.data!;
                final rows = data.rows;
                final loading =
                    snapshot.connectionState != ConnectionState.done ||
                    (_searchDebounce?.isActive ?? false);
                return CustomScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _overview(data),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _search,
                              onChanged: _searchChanged,
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: '搜索歌曲、歌手、专辑或来源',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _search.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: '清空搜索',
                                        onPressed: () {
                                          _search.clear();
                                          _searchChanged('');
                                        },
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                filled: true,
                                fillColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerLow,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _filters(data),
                            const SizedBox(height: 16),
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12,
                              children: [
                                Text(
                                  loading ? '正在搜索…' : '缓存资源 · ${rows.length} 首',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                TextButton.icon(
                                  onPressed: loading || rows.isEmpty
                                      ? null
                                      : () => setState(() {
                                          final allSelected = rows.every(
                                            (r) => selected.contains(
                                              r['track_key'],
                                            ),
                                          );
                                          if (allSelected) {
                                            selected.clear();
                                          } else {
                                            selected.addAll(
                                              rows.map(
                                                (r) => r['track_key'] as String,
                                              ),
                                            );
                                          }
                                        }),
                                  icon: Icon(
                                    rows.isNotEmpty &&
                                            rows.every(
                                              (r) => selected.contains(
                                                r['track_key'],
                                              ),
                                            )
                                        ? Icons.deselect_rounded
                                        : Icons.select_all_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    rows.isNotEmpty &&
                                            rows.every(
                                              (r) => selected.contains(
                                                r['track_key'],
                                              ),
                                            )
                                        ? '取消全选'
                                        : '全选当前结果',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (loading)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (rows.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _emptyState(
                          data.catalog.total == 0
                              ? Icons.library_music_outlined
                              : Icons.search_off_rounded,
                          data.catalog.total == 0 ? '还没有音乐缓存' : '没有找到匹配的缓存',
                          data.catalog.total == 0
                              ? '缓存歌曲后，可在这里查看和管理空间'
                              : '试试其他关键词，或切换来源',
                          action: sourceId != null || _query.isNotEmpty
                              ? TextButton(
                                  onPressed: () {
                                    _search.clear();
                                    setState(() {
                                      sourceId = null;
                                      _query = '';
                                      selected.clear();
                                      _searchDebounce?.cancel();
                                      records = _load();
                                    });
                                  },
                                  child: const Text('重置搜索与筛选'),
                                )
                              : null,
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        sliver: SliverList.builder(
                          itemCount: rows.length,
                          itemBuilder: (context, index) =>
                              _cacheRow(rows[index]),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 24 + MediaQuery.paddingOf(context).bottom,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );

  Widget _overview(_CacheListResult data) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final budget = widget.app.cache.maxBytes;
    final progress = budget <= 0
        ? 0.0
        : (data.usage.total / budget).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.offline_pin_outlined, color: colors.primary, size: 22),
              const SizedBox(width: 8),
              Text('音乐缓存空间', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _size(data.usage.total),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '上限 ${_size(budget)} · ${data.catalog.total} 首关联歌曲',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _usageItem(Icons.audiotrack_outlined, '音频', data.usage.audio),
              _usageItem(Icons.image_outlined, '封面', data.usage.cover),
              _usageItem(Icons.lyrics_outlined, '歌词', data.usage.lyrics),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '到达容量限制后将自动释放旧缓存',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _usageItem(IconData icon, String label, int bytes) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 17,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 6),
      Text(
        '$label ${_size(bytes)}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

  Widget _filters(_CacheListResult data) {
    final sourceIds = <String>{
      for (final source in widget.app.sources) source.id,
      ...data.catalog.sourceIds,
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        PopupMenuButton<String>(
          tooltip: '按来源筛选',
          onSelected: (id) => setState(() {
            sourceId = id.isEmpty ? null : id;
            selected.clear();
            _searchDebounce?.cancel();
            records = _load();
          }),
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: '',
              checked: sourceId == null,
              child: const Text('全部来源'),
            ),
            for (final id in sourceIds)
              CheckedPopupMenuItem(
                value: id,
                checked: sourceId == id,
                child: Text(_sourceName(id)),
              ),
          ],
          child: _filterLabel(
            Icons.filter_alt_outlined,
            sourceId == null ? '全部来源' : _sourceName(sourceId!),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: '排序',
          onSelected: (value) => setState(() {
            _sort = value;
            _searchDebounce?.cancel();
            records = _load();
          }),
          itemBuilder: (_) => [
            for (final item in const {
              'recent': '最近使用',
              'size': '占用从大到小',
              'title': '歌曲名称',
            }.entries)
              CheckedPopupMenuItem(
                value: item.key,
                checked: _sort == item.key,
                child: Text(item.value),
              ),
          ],
          child: _filterLabel(
            Icons.sort_rounded,
            _sort == 'size'
                ? '占用从大到小'
                : _sort == 'title'
                ? '歌曲名称'
                : '最近使用',
          ),
        ),
      ],
    );
  }

  Widget _filterLabel(IconData icon, String label) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.expand_more_rounded, size: 18),
      ],
    ),
  );

  Widget _cacheRow(Map<String, Object?> row) {
    final key = row['track_key'] as String;
    final checked = selected.contains(key);
    final audio = row['audio_bytes'] as int;
    final cover = row['cover_bytes'] as int;
    final lyrics = row['lyrics_bytes'] as int;
    final manual = row['manual_bytes'] as int;
    final colors = Theme.of(context).colorScheme;
    final metadata = [
      row['artist'],
      row['album'],
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: checked
            ? colors.secondaryContainer.withValues(alpha: .5)
            : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          key: PageStorageKey(key),
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          leading: Checkbox(
            value: checked,
            semanticLabel: '选择 ${row['title']}',
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
            style: Theme.of(context).textTheme.titleSmall,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (metadata.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(metadata, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 6),
              Text(
                '${_sourceName(row['source'] as String)} · ${_size(_rowBytes(row))}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.primary),
              ),
            ],
          ),
          children: [
            const Divider(height: 1, indent: 20, endIndent: 20),
            _resourceDetail(Icons.audiotrack_outlined, '歌曲音频', audio),
            _resourceDetail(
              Icons.image_outlined,
              '专辑封面',
              cover,
              note: row['cover_shared'] == 1 ? '共享文件，全局占用只计算一次' : null,
            ),
            _resourceDetail(
              Icons.lyrics_outlined,
              '歌词',
              lyrics,
              note: manual > 0 ? '包含受保护的手动歌词 ${_size(manual)}' : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Text(
                '上方大小为资源引用合计，可能包含共享封面与受保护歌词。',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resourceDetail(
    IconData icon,
    String title,
    int bytes, {
    String? note,
  }) => ListTile(
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    leading: Icon(icon, size: 20),
    title: Text(title),
    subtitle: note == null ? null : Text(note),
    trailing: Text(_size(bytes)),
  );

  Widget _emptyState(
    IconData icon,
    String title,
    String message, {
    Widget? action,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      ),
    ),
  );

  Widget _selectionBar() => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: _clearing ? null : () => setState(selected.clear),
              child: Text('已选 ${selected.length} 首 · 取消'),
            ),
            FilledButton.icon(
              onPressed: _clearing ? null : _clear,
              icon: _clearing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline_rounded),
              label: Text(_clearing ? '正在清理…' : '清理选中缓存'),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _clear() async {
    if (_clearing || selected.isEmpty) return;
    final keys = Set<String>.of(selected);
    setState(() => _clearing = true);
    try {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('清理选中缓存？'),
          content: Text(
            '将清理 ${keys.length} 首歌曲关联的音频、封面和远程歌词，并取消相关任务。'
            '\n\n共享封面仍被其他歌曲引用时保留；手动歌词和原始音乐文件不受影响。',
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
      if (confirm != true || !mounted) return;
      await widget.app.clearCache(keys: keys);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已处理选中的缓存，手动歌词与原始文件已保留')));
    } catch (_) {
      if (mounted) {
        _reload();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('部分缓存未能清理，请刷新后重试')));
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }
}
