import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/app_controller.dart';

/// The selection describes *where* to append tracks. The caller owns writes,
/// so single-track and batch actions keep their existing source restrictions.
class PlaylistPickerChoice {
  const PlaylistPickerChoice.existing(PlaylistModel value)
    : playlist = value,
      newLocalName = null;

  const PlaylistPickerChoice.newLocal(String name)
    : playlist = null,
      newLocalName = name;

  final PlaylistModel? playlist;
  final String? newLocalName;
}

/// Append without changing cloud restrictions or the identity of playlist entries.
/// Ordinary playlists retain duplicate songs; favorites behave like a set.
Future<void> appendToPlaylistChoice(
  SylphyApp app,
  PlaylistPickerChoice choice,
  List<TrackRef> tracks,
) async {
  if (tracks.isEmpty) return;
  if (choice.newLocalName != null) {
    await app.cloud.newLocal(
      choice.newLocalName!,
      keys: tracks.map((track) => track.key).toList(),
    );
    await app.reload();
    return;
  }
  final target = choice.playlist!;
  final keys = await app.db.playlistKeys(target.id);
  if (target.kind == PlaylistKind.favorites) {
    final seen = keys.toSet();
    for (final track in tracks) {
      if (seen.add(track.key)) keys.add(track.key);
    }
  } else {
    keys.addAll(tracks.map((track) => track.key));
  }
  await app.setPlaylistKeys(target, keys);
}

/// A shared, spacious mobile-first alternative to SimpleDialog.
///
/// Only playlists the caller has determined writable should be passed in.
Future<PlaylistPickerChoice?> showPlaylistPickerSheet(
  BuildContext context, {
  required List<PlaylistModel> candidates,
  required List<SourceProfile> sources,
  required int trackCount,
  String? trackTitle,
}) {
  return showModalBottomSheet<PlaylistPickerChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _PlaylistPickerContent(
      candidates: candidates,
      sources: sources,
      trackCount: trackCount,
      trackTitle: trackTitle,
    ),
  );
}

class _PlaylistPickerContent extends StatefulWidget {
  const _PlaylistPickerContent({
    required this.candidates,
    required this.sources,
    required this.trackCount,
    this.trackTitle,
  });

  final List<PlaylistModel> candidates;
  final List<SourceProfile> sources;
  final int trackCount;
  final String? trackTitle;

  @override
  State<_PlaylistPickerContent> createState() => _PlaylistPickerContentState();
}

class _PlaylistPickerContentState extends State<_PlaylistPickerContent> {
  final TextEditingController _name = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _create() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(PlaylistPickerChoice.newLocal(name));
  }

  String _subtitle(PlaylistModel playlist) {
    if (playlist.kind == PlaylistKind.favorites) return '本地收藏';
    if (playlist.kind == PlaylistKind.local) return '本地歌单';
    final sourceName = <String, String>{
      for (final source in widget.sources) source.id: source.name,
    }[playlist.sourceId];
    final name = sourceName == null || sourceName.isEmpty
        ? '云端歌单'
        : '$sourceName · 云端歌单';
    return switch (playlist.status) {
      SyncStatus.pending => '$name · 待同步',
      SyncStatus.conflict => '$name · 需处理冲突',
      SyncStatus.failed => '$name · 同步异常',
      _ => name,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final media = MediaQuery.of(context);
    final availableHeight =
        media.size.height - media.padding.top - media.viewInsets.bottom;
    final favorite = widget.candidates.where(
      (p) => p.kind == PlaylistKind.favorites && p.sourceId == null,
    );
    final localFavorite = favorite.isEmpty ? null : favorite.first;
    final playlists = [
      for (final p in widget.candidates)
        if (p != localFavorite) p,
    ];
    final caption =
        widget.trackCount == 1 &&
            widget.trackTitle != null &&
            widget.trackTitle!.trim().isNotEmpty
        ? '将《${widget.trackTitle}》保存到歌单'
        : '为 ${widget.trackCount} 首歌曲选择目标歌单';

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: availableHeight * .84,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView.builder(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 28),
              itemCount: playlists.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '添加到歌单',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (_creating) ...[
                        TextField(
                          autofocus: true,
                          controller: _name,
                          maxLength: 80,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _create(),
                          decoration: InputDecoration(
                            labelText: '新歌单名称',
                            hintText: '给这份音乐起个名字',
                            prefixIcon: const Icon(Icons.playlist_add_rounded),
                            filled: true,
                            fillColor: scheme.surfaceContainerLow,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    setState(() => _creating = false),
                                child: const Text('返回选择'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _create,
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('创建并添加'),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 56,
                                child: FilledButton.tonalIcon(
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: () =>
                                      setState(() => _creating = true),
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('新建歌单'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 56,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: localFavorite == null
                                      ? null
                                      : () => Navigator.of(context).pop(
                                          PlaylistPickerChoice.existing(
                                            localFavorite,
                                          ),
                                        ),
                                  icon: const Icon(
                                    Icons.favorite_border_rounded,
                                  ),
                                  label: const Text('我的收藏'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        '我的歌单',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (playlists.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 30),
                          child: Center(
                            child: Text(
                              '还没有可添加的歌单，可以先新建一个',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                }
                final p = playlists[index - 1];
                final isCloud = p.kind == PlaylistKind.cloud;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      leading: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: scheme.secondaryContainer,
                        ),
                        child: Icon(
                          isCloud
                              ? Icons.cloud_outlined
                              : Icons.queue_music_rounded,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                      title: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          _subtitle(p),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                      onTap: () =>
                          Navigator.of(context)
                              .pop(PlaylistPickerChoice.existing(p)),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
