import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../services/unified_cache_quota.dart';
import 'settings_controls.dart';

class SettingsCacheOverview extends StatefulWidget {
  const SettingsCacheOverview({
    super.key,
    required this.app,
    required this.onManage,
    required this.onTasks,
    required this.onLimit,
    required this.onClearAll,
  });

  final SylphyApp app;
  final Future<void> Function() onManage;
  final Future<void> Function() onTasks;
  final Future<void> Function() onLimit;
  final Future<void> Function() onClearAll;

  @override
  State<SettingsCacheOverview> createState() => _SettingsCacheOverviewState();
}

class _SettingsCacheOverviewState extends State<SettingsCacheOverview> {
  late Future<CacheUsage> _usage = widget.app.cache.quota.usage();
  bool _busy = false;

  @override
  void didUpdateWidget(covariant SettingsCacheOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != widget.app) _usage = widget.app.cache.quota.usage();
  }

  void _refresh() => setState(() => _usage = widget.app.cache.quota.usage());

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _usage = widget.app.cache.quota.usage();
        });
      }
    }
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    if (bytes < 1073741824)
      return '${(bytes / 1048576).toStringAsFixed(1)} MiB';
    return '${(bytes / 1073741824).toStringAsFixed(2)} GiB';
  }

  Widget _usageCard(CacheUsage? usage, bool loading) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final limit = widget.app.cache.maxBytes;
    final fraction = usage == null || limit <= 0 ? null : usage.total / limit;
    final percent = fraction == null ? null : '${(fraction * 100).round()}%';
    return Card(
      margin: EdgeInsets.zero,
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: colors.onPrimaryContainer),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: SettingsIcon(
                  Icons.storage_outlined,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '缓存空间',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                usage == null ? '—' : _size(usage.total),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              if (fraction != null || loading)
                LinearProgressIndicator(
                  value: fraction?.clamp(0.0, 1.0),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(6),
                  semanticsLabel: '缓存额度使用率',
                  semanticsValue: percent,
                ),
              const SizedBox(height: 8),
              Text('上限 ${_size(limit)}${percent == null ? '' : ' · $percent'}'),
              const SizedBox(height: 4),
              const Text('应用缓存配额'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shortcut({
    required Key key,
    required IconData icon,
    required String title,
    required String description,
    required Future<void> Function() action,
  }) {
    final theme = Theme.of(context);
    return Card(
      key: key,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _busy ? null : () => _run(action),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SettingsIcon(icon, color: theme.colorScheme.primary),
                  const SettingsIcon(Icons.chevron_right, size: 18),
                ],
              ),
              const SizedBox(height: 8),
              Text(title, style: theme.textTheme.titleSmall),
              Text(description, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dashboard(CacheUsage? usage, bool loading) {
    final space = _usageCard(usage, loading);
    final shortcuts = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _shortcut(
          key: const ValueKey('cache-shortcut-tasks'),
          icon: Icons.download_outlined,
          title: '下载任务',
          description: '查看任务进度',
          action: widget.onTasks,
        ),
        const SizedBox(height: 12),
        _shortcut(
          key: const ValueKey('cache-shortcut-limit'),
          icon: Icons.tune_rounded,
          title: '缓存上限',
          description: '调整空间限制',
          action: widget.onLimit,
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 320 ||
            MediaQuery.textScalerOf(context).scale(16) > 20;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [space, const SizedBox(height: 12), shortcuts],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 11, child: space),
              const SizedBox(width: 12),
              Expanded(flex: 10, child: shortcuts),
            ],
          ),
        );
      },
    );
  }

  Widget _usageRow(IconData icon, String name, int? bytes) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: [
        SettingsIcon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(name)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            bytes == null ? '—' : _size(bytes),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FutureBuilder<CacheUsage>(
        future: _usage,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState != ConnectionState.done;
          final usage = snapshot.data;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _dashboard(usage, loading),
              const SizedBox(height: 12),
              SettingsGroup(
                children: [
                  ListTile(
                    title: const Text('缓存构成'),
                    trailing: IconButton(
                      tooltip: '刷新缓存统计',
                      onPressed: loading || _busy ? null : _refresh,
                      icon: const SettingsIcon(Icons.refresh),
                    ),
                  ),
                  if (snapshot.hasError && !loading)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        '读取缓存占用失败，请刷新重试。',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  _usageRow(Icons.audiotrack_outlined, '音频缓存', usage?.audio),
                  _usageRow(Icons.image_outlined, '封面缓存', usage?.cover),
                  _usageRow(Icons.lyrics_outlined, '歌词缓存', usage?.lyrics),
                ],
              ),
            ],
          );
        },
      ),
      SettingsGroup(
        children: [
          ListTile(
            key: const ValueKey('cache-manage'),
            leading: const SettingsIcon(Icons.library_music_outlined),
            title: const Text('管理音乐缓存'),
            subtitle: const Text('按歌曲、来源查看和清理缓存'),
            trailing: const SettingsIcon(Icons.chevron_right),
            onTap: _busy ? null : () => _run(widget.onManage),
          ),
          ListTile(
            key: const ValueKey('cache-clear-all'),
            leading: SettingsIcon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('清理所有缓存资源'),
            subtitle: const Text('保留原始音乐和手动歌词'),
            trailing: const SettingsIcon(Icons.chevron_right),
            onTap: _busy ? null : () => _run(widget.onClearAll),
          ),
        ],
      ),
    ],
  );
}
