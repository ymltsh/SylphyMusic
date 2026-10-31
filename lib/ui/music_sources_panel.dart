import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'music_source_ui.dart';

/// Music-source management presented as an easy-to-scan collection of cards.
/// Connection, indexing and deletion still go through SylphyApp in the shell.
class MusicSourcesPanel extends StatelessWidget {
  const MusicSourcesPanel({
    super.key,
    required this.app,
    required this.onAdd,
    required this.onSyncAll,
    required this.onImportFiles,
    required this.onImportFolder,
    required this.onSelect,
    required this.onAction,
  });

  final SylphyApp app;
  final VoidCallback onAdd;
  final VoidCallback onSyncAll;
  final VoidCallback onImportFiles;
  final VoidCallback onImportFolder;
  final ValueChanged<SourceProfile> onSelect;
  final Future<void> Function(SourceProfile, String) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text('已连接的音乐源', style: theme.textTheme.titleLarge),
                  ),
                  Text(
                    '${app.sources.length} 个来源',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Card.filled(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 640 ? 4 : 2;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 8) / columns;
                    final style = ButtonStyle(
                      minimumSize: const WidgetStatePropertyAll(Size.zero),
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 10),
                      ),
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    );
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final button in <Widget>[
                          FilledButton.icon(
                            style: style,
                            onPressed: app.busy ? null : onAdd,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('添加来源', maxLines: 1),
                          ),
                          OutlinedButton.icon(
                            style: style,
                            onPressed: app.busy ? null : onSyncAll,
                            icon: const Icon(Icons.sync, size: 18),
                            label: const Text('同步全部', maxLines: 1),
                          ),
                          OutlinedButton.icon(
                            style: style,
                            onPressed: app.busy ? null : onImportFiles,
                            icon: const Icon(
                              Icons.audio_file_outlined,
                              size: 18,
                            ),
                            label: const Text('导入文件', maxLines: 1),
                          ),
                          OutlinedButton.icon(
                            style: style,
                            onPressed: app.busy ? null : onImportFolder,
                            icon: const Icon(
                              Icons.create_new_folder_outlined,
                              size: 18,
                            ),
                            label: const Text('添加文件夹', maxLines: 1),
                          ),
                        ])
                          SizedBox(width: width, height: 48, child: button),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (app.sources.isEmpty)
              Card.outlined(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 40,
                    horizontal: 16,
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.library_music_outlined,
                        color: theme.colorScheme.primary,
                        size: 42,
                      ),
                      const SizedBox(height: 12),
                      Text('还没有音乐来源', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      const Text('添加服务器或导入本地音乐，即可开始聆听。'),
                    ],
                  ),
                ),
              )
            else
              ...app.sources.map(
                (source) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SourceCard(
                    source: source,
                    progress:
                        app.sourceSyncMessages[source.id] ??
                        app.index.progress[source.id]?.message,
                    syncing: app.sourceSyncing(source.id),
                    changing: app.sourceChanging(source.id),
                    canStartSync: !app.busy,
                    onOpen: () => onSelect(source),
                    onAction: (action) => onAction(source, action),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.progress,
    required this.syncing,
    required this.changing,
    required this.canStartSync,
    required this.onOpen,
    required this.onAction,
  });

  final SourceProfile source;
  final String? progress;
  final bool syncing;
  final bool changing, canStartSync;
  final VoidCallback onOpen;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final kind = sourceOptionFor(source.kind);
    final baseDirectory = Uri.parse(source.webdavBasePath).pathSegments
        .join('/');
    final depthDescription = source.webdavMaxDepth < 0
        ? '不限'
        : '${source.webdavMaxDepth}';
    final scanScope = source.kind == SourceKind.webdav
        ? ' · 基础目录: /$baseDirectory · 层级: $depthDescription'
        : '';
    final detail = source.kind == SourceKind.local
        ? '本地音乐'
        : '${source.url}${source.url.startsWith('http:') ? ' · 未加密连接' : ''}$scanScope';
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
            leading: MusicSourceIcon(kind: source.kind, source: source),
            title: Text(
              source.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${kind.title} · ${source.enabled ? '已启用' : '已停用'}\n$detail',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            onTap: onOpen,
            trailing: PopupMenuButton<String>(
              tooltip: '更多来源操作',
              enabled: !changing,
              onSelected: onAction,
              itemBuilder: (context) => [
                if (syncing)
                  const PopupMenuItem(
                    value: 'cancel_sync',
                    child: Text('取消同步'),
                  ),
                if (!changing && !syncing && source.kind != SourceKind.local)
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('编辑连接 / 重新登录'),
                  ),
                if (!changing &&
                    !syncing &&
                    source.kind == SourceKind.local &&
                    source.url != 'file:///')
                  const PopupMenuItem(value: 'scan', child: Text('重新扫描文件夹')),
                if (canStartSync &&
                    !changing &&
                    !syncing &&
                    source.enabled &&
                    source.kind != SourceKind.local)
                  const PopupMenuItem(value: 'sync', child: Text('同步此来源')),
                if (canStartSync &&
                    !changing &&
                    !syncing &&
                    source.enabled &&
                    source.kind == SourceKind.webdav)
                  const PopupMenuItem(
                    value: 'tags',
                    child: Text('补全 WebDAV 标签'),
                  ),
                if (!changing)
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(source.enabled ? '停用来源' : '重新启用'),
                  ),
                if (!changing && !syncing)
                  const PopupMenuItem(value: 'cache', child: Text('清除此来源缓存')),
                if (!changing && !syncing)
                  const PopupMenuItem(value: 'delete', child: Text('删除来源')),
              ],
            ),
          ),
          if (progress != null && progress!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                progress!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Divider(color: colors.outlineVariant, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.library_music_outlined, size: 18),
                  label: const Text('查看曲库'),
                ),
                const Spacer(),
                if (changing) ...[
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  changing
                      ? '处理中'
                      : source.enabled
                      ? '已启用'
                      : '已停用',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Switch.adaptive(
                  value: source.enabled,
                  onChanged: changing ? null : (_) => onAction('toggle'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
