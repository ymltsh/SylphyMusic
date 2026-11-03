import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';

/// Selection is expressed as explicit IDs or "all in this query except IDs".
/// It never requires loading every SQLite row merely to show checked state.
class BatchSelection extends ChangeNotifier {
  bool active = false;
  bool all = false;
  int total = 0;
  final Set<String> _selected = {};
  final Set<String> _excluded = {};

  int get count => all
      ? (total - _excluded.length).clamp(0, total).toInt()
      : _selected.length;

  bool contains(String key) =>
      active && (all ? !_excluded.contains(key) : _selected.contains(key));

  void begin(String key) {
    active = true;
    all = false;
    _selected
      ..clear()
      ..add(key);
    _excluded.clear();
    notifyListeners();
  }

  void toggle(String key) {
    if (!active) {
      begin(key);
      return;
    }
    final target = all ? _excluded : _selected;
    if (!target.add(key)) target.remove(key);
    notifyListeners();
  }

  void selectAll(int count) {
    active = true;
    all = true;
    total = count;
    _selected.clear();
    _excluded.clear();
    notifyListeners();
  }

  void deselectAll() {
    all = false;
    _selected.clear();
    _excluded.clear();
    notifyListeners();
  }

  void clear() {
    if (!active && _selected.isEmpty && _excluded.isEmpty) return;
    active = false;
    all = false;
    total = 0;
    _selected.clear();
    _excluded.clear();
    notifyListeners();
  }

  Set<String> get selectedKeys => Set.of(_selected);
  Set<String> get excludedKeys => Set.of(_excluded);

  List<String> applyTo(Iterable<String> available) => [
    for (final key in available)
      if (contains(key)) key,
  ];
}

/// Present one batch menu for both library and playlist routes. A resolver is
/// intentionally lazy: "select all" stores only exceptions until execution.
Future<bool> showBatchTrackActions(
  BuildContext context,
  SylphyApp app, {
  required int count,
  required Future<List<TrackRef>> Function() resolve,
  String countUnit = '首',
  String? removalPlaylistId,
  Future<Set<String>> Function()? resolveRemovalEntries,
}) async {
  if (count == 0) return false;
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Text(
              '批量操作 · $count $countUnit',
              style: Theme.of(sheet).textTheme.titleMedium,
            ),
          ),
          for (final item in const [
            ('play', Icons.play_arrow_rounded, '播放选中歌曲'),
            ('next', Icons.playlist_play_rounded, '下一首播放'),
            ('queue', Icons.queue_music_rounded, '添加到播放队列'),
            ('playlist', Icons.playlist_add_rounded, '添加到歌单'),
            ('favorite', Icons.favorite_border_rounded, '添加到收藏'),
            ('cache', Icons.download_outlined, '缓存选中歌曲'),
            ('block', Icons.visibility_off_outlined, '屏蔽选中歌曲'),
          ])
            ListTile(
              leading: Icon(item.$2),
              title: Text(item.$3),
              onTap: () => Navigator.pop(sheet, item.$1),
            ),
          if (removalPlaylistId != null && resolveRemovalEntries != null)
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('从当前歌单移除'),
              onTap: () => Navigator.pop(sheet, 'remove'),
            ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return false;

  if (action == 'remove' || action == 'block') {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(action == 'remove' ? '从歌单移除' : '屏蔽歌曲'),
        content: Text(
          action == 'remove'
              ? '确定从当前歌单移除选中的 $count 条记录？不会删除音乐文件。'
              : '确定屏蔽选中的 $count 首歌曲？不会删除音乐文件。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (agreed != true) return false;
  }

  try {
    if (action == 'remove') {
      if (removalPlaylistId == null || resolveRemovalEntries == null) {
        return false;
      }
      final playlist = await app.db.playlist(removalPlaylistId);
      if (playlist == null) throw StateError('歌单已不存在');
      final selectedEntries = await resolveRemovalEntries();
      if (selectedEntries.isEmpty) return false;
      final entries = await app.db.playlistEntries(removalPlaylistId);
      // Filter entry IDs, NOT track keys: duplicate songs remain independent.
      final keep = [
        for (final entry in entries)
          if (!selectedEntries.contains(entry.id)) entry.key,
      ];
      await app.setPlaylistKeys(playlist, keep);
    } else {
      final refs = await resolve();
      if (refs.isEmpty) return false;
      switch (action) {
        case 'play':
          await app.playback.setQueue(refs);
        case 'next':
          await app.playback.enqueueNextAll(refs);
        case 'queue':
          await app.playback.enqueueAll(refs);
        case 'playlist':
          final candidates = app.playlists.where(
            (p) =>
                (p.kind != PlaylistKind.favorites || p.sourceId == null) &&
                (p.kind != PlaylistKind.cloud ||
                    (p.status != SyncStatus.readonly &&
                        p.status != SyncStatus.syncing &&
                        refs.every((ref) => ref.sourceId == p.sourceId) &&
                        app.sources.any(
                          (s) =>
                              s.id == p.sourceId &&
                              s.enabled &&
                              s.kind.cloudPlaylistWritable,
                        ))),
          );
          if (!context.mounted) return false;
          final chosen = await showDialog<PlaylistModel>(
            context: context,
            builder: (dialog) => SimpleDialog(
              title: const Text('添加到歌单'),
              children: [
                for (final p in candidates)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(dialog, p),
                    child: Text(p.name),
                  ),
              ],
            ),
          );
          if (chosen == null) return false;
          final keys = await app.db.playlistKeys(chosen.id);
          keys.addAll(refs.map((ref) => ref.key));
          await app.setPlaylistKeys(chosen, keys);
        case 'cache':
          final online = [
            for (final ref in refs)
              if (app.sources.any(
                (s) => s.id == ref.sourceId && s.kind != SourceKind.local,
              ))
                ref,
          ];
          if (online.isNotEmpty) {
            await app.jobs.schedule('批量缓存 · ${online.length} 首', online);
          }
        case 'block':
          for (final ref in refs) {
            await app.db.setBlocked(ref, true);
          }
          await app.reload();
        case 'favorite':
          // Write local favorites in one transaction; remote stars still use
          // their authenticated per-track API instead of silently editing a
          // server playlist or toggling already-favorited songs off.
          final localKeys = await app.db.playlistKeys('favorites');
          final localSet = localKeys.toSet();
          var localChanged = false;
          final remoteSeen = <String, Set<String>>{};
          for (final ref in refs) {
            final track = await app.db.track(ref);
            if (track == null) continue;
            final id = app.favoritePlaylistId(track);
            if (id == 'favorites') {
              if (localSet.add(ref.key)) {
                localKeys.add(ref.key);
                localChanged = true;
              }
            } else {
              final existing = remoteSeen[id] ??= (await app.db.playlistKeys(
                id,
              )).toSet();
              if (existing.add(ref.key)) await app.toggleFavorite(track);
            }
          }
          if (localChanged) {
            await app.db.replacePlaylistKeys('favorites', localKeys);
            await app.reload();
          }
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('批量操作已完成')));
    }
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('批量操作失败：$error')));
    }
    return false;
  }
}
