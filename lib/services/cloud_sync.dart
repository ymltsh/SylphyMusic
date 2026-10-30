import 'dart:async';
import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm;

import 'package:uuid/uuid.dart';

import '../core/models.dart';
import '../data/app_db.dart';
import 'sources.dart';

class MergeResult {
  const MergeResult(this.keys, {this.conflict = false, this.reason = ''});
  final List<String> keys;
  final bool conflict;
  final String reason;
}

bool listEqualsExact(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool isPrefix(List<String> prefix, List<String> whole) {
  if (prefix.length > whole.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (prefix[i] != whole[i]) return false;
  }
  return true;
}

/// Conservative three-way merge: only append-only concurrent changes are safe.
/// Unlike set-based merges, repeated tracks remain repeated entries.
MergeResult mergePlaylist(
  List<String> base,
  List<String> local,
  List<String> remote,
) {
  if (listEqualsExact(remote, base)) return MergeResult(local);
  if (listEqualsExact(local, base)) return MergeResult(remote);
  if (isPrefix(base, local) && isPrefix(base, remote)) {
    return MergeResult([
      ...base,
      ...remote.skip(base.length),
      ...local.skip(base.length),
    ]);
  }
  if (listEqualsExact(remote, local)) return MergeResult(remote);
  return const MergeResult(
    [],
    conflict: true,
    reason: '两端删除、重排或修改了重叠区域，需要手动决定',
  );
}

class PlaylistSyncService {
  PlaylistSyncService(this.db, this.factory);
  final AppDb db;
  final AdapterFactory factory;
  final Set<String> busy = {};

  static String cloudFavoriteId(String sourceId) => 'cloud-favorites:$sourceId';

  // Server favorites are distinct from playlists. Keep a source-scoped local
  // mirror so server favorites never overwrite cross-source local favorites.
  Future<void> refreshStarredForSource(SourceProfile source) async {
    if (!source.enabled || !source.kind.cloudFavorites) return;
    final adapter = factory.create(source);
    try {
      final ids = await adapter.fetchStarredIds();
      await db.savePlaylistSnapshot(
        PlaylistModel(
          id: cloudFavoriteId(source.id),
          name: '${source.name} · 云端收藏',
          kind: PlaylistKind.favorites,
          sourceId: source.id,
        ),
        ids.map((id) => TrackRef(source.id, id).key).toList(),
      );
    } finally {
      adapter.close();
    }
  }

  Future<void> refreshCloudForSource(SourceProfile source) async {
    if (!source.kind.cloudPlaylists) return;
    final adapter = factory.create(source);
    try {
      final remote = await adapter.fetchPlaylists();
      final current = await db.playlists();
      for (final meta in remote) {
        final found = current.where(
          (p) =>
              p.kind == PlaylistKind.cloud &&
              p.sourceId == source.id &&
              p.remoteId == meta.id,
        );
        final existing = found.isEmpty ? null : found.first;
        final detail = await adapter.fetchPlaylist(meta.id);
        if (existing == null) {
          final model = PlaylistModel(
            id: const Uuid().v4(),
            name: meta.name,
            kind: PlaylistKind.cloud,
            sourceId: source.id,
            remoteId: meta.id,
            base: detail.tracks,
            status: detail.readonly ? SyncStatus.readonly : SyncStatus.synced,
          );
          await db.putPlaylist(model);
          await db.replacePlaylistKeys(model.id, detail.tracks);
        } else if (!busy.contains(existing.id) &&
            (existing.status == SyncStatus.synced ||
                existing.status == SyncStatus.readonly) &&
            listEqualsExact(
              await db.playlistKeys(existing.id),
              existing.base,
            )) {
          await db.replacePlaylistKeys(existing.id, detail.tracks);
          await db.putPlaylist(
            existing.copyWith(
              name: meta.name,
              baseName: meta.name,
              base: detail.tracks,
              status: detail.readonly ? SyncStatus.readonly : SyncStatus.synced,
            ),
          );
        } else if (detail.readonly) {
          await db.putPlaylist(
            existing.copyWith(
              status: SyncStatus.readonly,
              message: '服务器歌单只读，本地编辑已保留',
            ),
          );
        }
      }
    } finally {
      adapter.close();
    }
  }

  Future<void> editLocal(String playlistId, List<String> trackKeys) async {
    if (busy.contains(playlistId)) throw StateError('歌单正在同步，请稍后再编辑');
    final p = await db.playlist(playlistId);
    if (p == null) throw StateError('歌单不存在');
    if (p.kind == PlaylistKind.cloud) {
      for (final key in trackKeys) {
        if (TrackRef.parse(key).sourceId != p.sourceId) {
          throw StateError('云歌单仅允许添加绑定来源的歌曲');
        }
      }
      if (p.status == SyncStatus.readonly) throw StateError('服务器只读；请先复制为本地歌单');
    }
    await db.savePlaylistSnapshot(
      p.kind == PlaylistKind.cloud
          ? p.copyWith(
              status: p.status == SyncStatus.conflict
                  ? SyncStatus.conflict
                  : SyncStatus.pending,
              message: '',
            )
          : p,
      trackKeys,
    );
  }

  Future<void> removeEntry(String playlistId, String entryId) async {
    if (busy.contains(playlistId)) throw StateError('歌单正在同步，请稍后再编辑');
    final playlist = await db.playlist(playlistId);
    if (playlist == null) throw StateError('歌单不存在');
    if (playlist.kind == PlaylistKind.cloud) {
      final source = await db.source(playlist.sourceId!);
      if (playlist.status == SyncStatus.readonly ||
          source == null ||
          !source.kind.cloudPlaylistWritable) {
        throw StateError('服务器只读；请先复制为本地歌单');
      }
    }
    await db.removePlaylistEntry(playlist, entryId);
  }

  Future<void> renameLocal(String id, String name) async {
    if (busy.contains(id)) throw StateError('歌单正在同步，请稍后再编辑');
    final playlist = await db.playlist(id);
    if (playlist == null ||
        name.trim().isEmpty ||
        playlist.kind == PlaylistKind.favorites) {
      return;
    }
    if (playlist.status == SyncStatus.readonly) throw StateError('服务器歌单只读');
    await db.putPlaylist(
      playlist.copyWith(
        name: name.trim(),
        baseName: playlist.baseName.isEmpty ? playlist.name : playlist.baseName,
        status: playlist.kind == PlaylistKind.cloud
            ? SyncStatus.pending
            : SyncStatus.synced,
      ),
    );
  }

  Future<PlaylistModel> newLocal(
    String name, {
    List<String> keys = const [],
  }) async {
    final p = PlaylistModel(
      id: const Uuid().v4(),
      name: name,
      kind: PlaylistKind.local,
    );
    await db.putPlaylist(p);
    await db.replacePlaylistKeys(p.id, keys);
    return p;
  }

  Future<PlaylistModel> createCloud(
    SourceProfile source,
    String name, {
    List<String> keys = const [],
  }) async {
    if (!source.kind.cloudPlaylists) throw UnsupportedError('此来源使用本地歌单');
    final selected = keys
        .where((k) => TrackRef.parse(k).sourceId == source.id)
        .toList();
    final adapter = factory.create(source);
    try {
      final remote = await adapter.createPlaylist(name); // online-only creation
      final p = PlaylistModel(
        id: const Uuid().v4(),
        name: name,
        kind: PlaylistKind.cloud,
        sourceId: source.id,
        remoteId: remote.id,
        base: const [],
        status: SyncStatus.pending,
      );
      await db.putPlaylist(p);
      await db.replacePlaylistKeys(p.id, selected);
      if (selected.isNotEmpty) {
        await syncOne(p.id);
      }
      return p;
    } finally {
      adapter.close();
    }
  }

  Future<PlaylistModel> copyToLocal(PlaylistModel source, String name) async {
    return newLocal(name, keys: await db.playlistKeys(source.id));
  }

  Future<PlaylistModel> copyToCloud(
    PlaylistModel from,
    SourceProfile to,
    String name,
  ) async {
    return createCloud(to, name, keys: await db.playlistKeys(from.id));
  }

  Future<void> syncOne(String id) async {
    if (!busy.add(id)) return;
    try {
      var p = await db.playlist(id);
      if (p?.status == SyncStatus.conflict) return;
      if (p == null ||
          p.kind != PlaylistKind.cloud ||
          p.remoteId == null ||
          p.sourceId == null) {
        return;
      }
      final source = await db.source(p.sourceId!);
      if (source == null || !source.enabled) return;
      final adapter = factory.create(source);
      try {
        final local = await db.playlistKeys(p.id);
        final remote = await adapter.fetchPlaylist(p.remoteId!);
        final intents = await db.db.query(
          'sync_intents',
          where: 'playlist_id=?',
          whereArgs: [id],
        );
        if (intents.isNotEmpty) {
          final intent = intents.first;
          final desired = List<String>.from(
            jsonDecode(intent['desired_json'] as String) as List,
          );
          final before = List<String>.from(
            jsonDecode(intent['before_json'] as String) as List,
          );
          final priorLocal = List<String>.from(
            jsonDecode(intent['local_json'] as String) as List,
          );
          if (listEqualsExact(remote.tracks, desired) &&
              remote.name == intent['desired_name'] &&
              listEqualsExact(local, priorLocal)) {
            await db.replacePlaylistKeys(id, desired);
            await db.putPlaylist(
              p.copyWith(
                name: remote.name,
                baseName: remote.name,
                base: desired,
                status: SyncStatus.synced,
                message: '',
              ),
            );
            await db.db.delete(
              'sync_intents',
              where: 'playlist_id=?',
              whereArgs: [id],
            );
            return;
          }
          if (!listEqualsExact(remote.tracks, before) ||
              remote.name != intent['before_name']) {
            await db.putPlaylist(
              p.copyWith(
                status: SyncStatus.conflict,
                message: '上次写入尚未确认且远端已改变，保留本地修改并暂停写入',
              ),
            );
            return;
          }
          await db.db.delete(
            'sync_intents',
            where: 'playlist_id=?',
            whereArgs: [id],
          );
        }
        if (remote.readonly) {
          await db.putPlaylist(
            p.copyWith(
              status: SyncStatus.readonly,
              message: '服务器歌单只读，待同步编辑仍留在本机',
            ),
          );
          return;
        }
        final result = mergePlaylist(p.base, local, remote.tracks);
        final baseName = p.baseName.isEmpty ? p.name : p.baseName;
        final renamedHere = p.name != baseName;
        if (renamedHere && remote.name != baseName && remote.name != p.name) {
          await db.putPlaylist(
            p.copyWith(
              status: SyncStatus.conflict,
              message: '两端修改了歌单名称，请选择要保留的版本',
            ),
          );
          return;
        }
        final desiredName = renamedHere ? p.name : remote.name;
        if (result.conflict) {
          await db.putPlaylist(
            p.copyWith(status: SyncStatus.conflict, message: result.reason),
          );
          return;
        }
        await db.putPlaylist(p.copyWith(status: SyncStatus.syncing));
        await db.db.insert('sync_intents', {
          'playlist_id': id,
          'before_json': jsonEncode(remote.tracks),
          'local_json': jsonEncode(local),
          'desired_json': jsonEncode(result.keys),
          'before_name': remote.name,
          'desired_name': desiredName,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        if (desiredName != remote.name) {
          await adapter.renamePlaylist(remote.id, desiredName);
        }
        if (!listEqualsExact(result.keys, remote.tracks)) {
          await adapter.mutatePlaylist(remote, result.keys);
        }
        final verified = await adapter.fetchPlaylist(remote.id);
        if (!listEqualsExact(verified.tracks, result.keys) ||
            verified.name != desiredName) {
          throw StateError('云端回读与提交结果不一致，已保留本地修改');
        }
        await db.replacePlaylistKeys(p.id, result.keys);
        await db.putPlaylist(
          p.copyWith(
            name: desiredName,
            baseName: desiredName,
            base: result.keys,
            status: SyncStatus.synced,
            message: '',
          ),
        );
        await db.db.delete(
          'sync_intents',
          where: 'playlist_id=?',
          whereArgs: [id],
        );
      } finally {
        adapter.close();
      }
    } catch (e) {
      final p = await db.playlist(id);
      if (p != null) {
        await db.putPlaylist(
          p.copyWith(status: SyncStatus.failed, message: e.toString()),
        );
      }
    } finally {
      busy.remove(id);
    }
  }

  Future<void> syncAll() async {
    for (final p in await db.playlists()) {
      if (p.kind == PlaylistKind.cloud &&
          (p.status == SyncStatus.pending || p.status == SyncStatus.failed)) {
        await syncOne(p.id);
      }
    }
  }

  Future<void> resolveConflict(String id, {required bool useLocal}) async {
    final p = await db.playlist(id);
    if (p == null || p.status != SyncStatus.conflict) return;
    await db.db.delete('sync_intents', where: 'playlist_id=?', whereArgs: [id]);
    if (!useLocal) {
      final source = await db.source(p.sourceId!);
      if (source == null) return;
      final adapter = factory.create(source);
      try {
        final remote = await adapter.fetchPlaylist(p.remoteId!);
        // Preserve changes as a separate local draft before choosing server.
        await newLocal('${p.name} · 冲突草稿', keys: await db.playlistKeys(p.id));
        await db.replacePlaylistKeys(p.id, remote.tracks);
        await db.putPlaylist(
          p.copyWith(
            name: remote.name,
            baseName: remote.name,
            base: remote.tracks,
            status: SyncStatus.synced,
            message: '',
          ),
        );
      } finally {
        adapter.close();
      }
    } else {
      // An overwrite after conflict must be explicit; preserving cloud changes as
      // a local draft first avoids silent loss. Underlying API is not atomic.
      final source = await db.source(p.sourceId!);
      if (source == null) return;
      final adapter = factory.create(source);
      try {
        final remote = await adapter.fetchPlaylist(p.remoteId!);
        await newLocal('${p.name} · 服务器冲突备份', keys: remote.tracks);
        await db.putPlaylist(
          p.copyWith(
            base: remote.tracks,
            baseName: remote.name,
            status: SyncStatus.pending,
            message: '用户明确选择本地版本',
          ),
        );
      } finally {
        adapter.close();
      }
      await syncOne(id);
    }
  }

  Future<void> deleteRemoteOnline(PlaylistModel p) async {
    if (p.kind != PlaylistKind.cloud || p.remoteId == null) {
      throw StateError('不是已创建的云歌单');
    }
    final source = await db.source(p.sourceId!);
    if (source == null) throw StateError('来源不存在');
    final adapter = factory.create(source);
    try {
      await adapter.deletePlaylist(p.remoteId!);
      await db.removePlaylist(p.id);
    } finally {
      adapter.close();
    }
  }
}
