import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../data/app_db.dart';
import '../data/library_catalog.dart';
import '../services/app_updates.dart';
import '../services/api_settings.dart';
import '../services/cache.dart';
import '../services/cache_jobs.dart';
import '../services/cloud_sync.dart';
import '../services/diagnostic_logs.dart';
import '../services/media_proxy.dart';
import '../services/playback.dart';
import '../services/playback_sleep_timer.dart';
import '../services/sources.dart';
import '../services/desktop.dart';
import '../services/local_library.dart';
import '../services/artwork.dart';
import '../services/media_assets.dart';
import '../services/lrc_api.dart';
import '../services/lyrics_store.dart';
import '../services/webdav_tags.dart';
import '../services/sync_foreground.dart';
import '../services/webdav_metadata_enricher.dart';
import '../services/library_sync.dart';
import '../services/source_connections.dart';
import 'models.dart';
import 'appearance.dart';
import 'listening_history.dart';
import 'player_layout_store.dart';

class SylphyApp extends ChangeNotifier {
  SylphyApp._(
    this.root,
    this.db,
    this.factory,
    this.vault,
    this.cache,
    this.proxy,
    this.playback,
    this.cloud,
    this.jobs,
    this.diagnostics,
  );
  final Directory root;
  final AppDb db;
  final AdapterFactory factory;
  final AuthVault vault;
  final CacheManager cache;
  final DiagnosticLogs diagnostics;
  final MediaProxy proxy;
  final PlaybackCoordinator playback;
  late final sleepTimer = PlaybackSleepTimer(onStop: playback.pause);
  AppLifecycleListener? _sleepLifecycle;
  final PlaylistSyncService cloud;
  final CacheJobs jobs;
  List<SourceProfile> sources = [];
  int catalogRevision = 0;
  late final catalog = LibraryCatalog(db);
  late final appearance = Appearance(db);
  late final apiSettings = ApiSettings(db);
  late final lrcApi = LrcApiClient(apiSettings, vault);
  late final playerLayouts = PlayerLayoutStore(db);
  late final history = ListeningHistory(db, playback);
  List<PlaylistModel> playlists = [];
  Set<String> blacklist = {};
  int _busyOperations = 0;
  Timer? _catalogRefreshTimer;
  bool _foregroundSyncRunning = false;
  Future<void>? _foregroundSyncTask;
  bool _foregroundSyncCancelled = false;
  String? _foregroundSourceId;
  late final syncForeground = SyncForeground(_pauseForegroundSync);
  bool get busy => _busyOperations > 0 || _foregroundSyncRunning;
  bool _disposed = false;
  String? message;
  DesktopControls? desktop;
  late final assets = MediaAssetStore(db, root);
  late final webDavTags = WebDavTags(
    factory,
    cache: cache,
    onTags: (track, tags) async {
      if (await db.putWebDavTags(track, tags)) _scheduleCatalogRefresh();
    },
  );
  late final metadataEnricher = WebDavMetadataEnricher(db, webDavTags);
  late final artwork = ArtworkStore(
    db,
    factory,
    root,
    assets: assets,
    tags: webDavTags,
  );
  late final lyrics = LyricsStore(
    db,
    factory,
    assets,
    cache,
    root,
    lrcApi: lrcApi,
    tags: webDavTags,
  );
  late final index = LibrarySync(db, factory);
  late final connections = SourceConnections(
    db,
    factory,
    onDisabled: _suspendSource,
    onEnabled: (source) async {
      if (_disposed) return;
      if (source.kind != SourceKind.local) {
        await syncSource(source);
      } else if (source.url != 'file:///') {
        await rescanLocal(source);
      }
    },
  );
  static Future<SylphyApp> bootstrap({
    Directory? dataRoot,
    AuthVault? credentialVault,
    bool resumeBackground = true,
    bool platformIntegration = true,
  }) async {
    final root =
        dataRoot ??
        Directory(
          p.join((await getApplicationSupportDirectory()).path, 'sylphy_music'),
        );
    final db = AppDb(root);
    await db.open();
    final diagnostics = DiagnosticLogs(
      Directory(p.join(root.path, 'diagnostics')),
    );
    await diagnostics.initialize(
      enabled: await db.setting('diagnostic_logs_enabled') == 'true',
    );
    diagnostics.record('app', 'bootstrap_started');
    final vault = credentialVault ?? const AuthVault();
    final factory = AdapterFactory(vault);
    final cache = CacheManager(
      db,
      factory,
      Directory(p.join(root.path, 'audio')),
    );
    await cache.initialize();
    final proxy = MediaProxy(db, cache, factory, diagnostics: diagnostics);
    await proxy.start();
    final playback = PlaybackCoordinator(
      db,
      proxy,
      cache,
      diagnostics: diagnostics,
    );
    await playback.initialize();
    final cloud = PlaylistSyncService(db, factory);
    final jobs = CacheJobs(db, cache);
    final app = SylphyApp._(
      root,
      db,
      factory,
      vault,
      cache,
      proxy,
      playback,
      cloud,
      jobs,
      diagnostics,
    );
    await app.assets.initialize();
    app.index.addListener(app._indexChanged);
    app._sleepLifecycle = AppLifecycleListener(
      onResume: () => unawaited(app.sleepTimer.checkDue()),
    );
    await app.appearance.initialize();
    app.apiSettings.addListener(app._apiChanged);
    await app.apiSettings.initialize();
    await app.playerLayouts.initialize();
    await app.history.initialize();
    app.history.addListener(app._indexChanged);
    await app.reload();
    app.playback.setLyricsLoader((track) => app.loadLyrics(track));
    if (platformIntegration) {
      if (Platform.isAndroid) {
        playback.attachNotificationArtwork(app.artwork);
      }
      await playback.attachHandler();
      app.desktop = DesktopControls(playback, app.disposeAsync);
      await app.desktop!.initialize();
    }
    if (resumeBackground) unawaited(app._backgroundResume());
    return app;
  }

  Future<void> _backgroundResume() async {
    try {
      unawaited(jobs.run());
      final interrupted = await index.interruptedSources();
      for (final source in [...sources]) {
        if (source.kind != SourceKind.local &&
            source.enabled &&
            (interrupted.contains(source.id) ||
                DateTime.now().millisecondsSinceEpoch - source.lastSync >
                    6 * 60 * 60 * 1000)) {
          try {
            await syncSource(source);
          } catch (_) {}
        }
      }
      await cloud.syncAll();
      await reload();
      for (final source in sources) {
        if (source.enabled && source.kind == SourceKind.webdav) {
          metadataEnricher.start(source);
        }
      }
    } catch (_) {}
  }

  Future<void> refreshIfStale() async {
    if (busy) return;
    for (final source in [...sources]) {
      if (source.kind != SourceKind.local &&
          source.enabled &&
          DateTime.now().millisecondsSinceEpoch - source.lastSync >
              6 * 60 * 60 * 1000) {
        try {
          await syncSource(source);
        } catch (_) {}
      }
    }
  }

  void _scheduleCatalogRefresh() {
    if (_disposed || _catalogRefreshTimer != null) return;
    _catalogRefreshTimer = Timer(const Duration(seconds: 2), () {
      _catalogRefreshTimer = null;
      if (_disposed) return;
      catalogRevision++;
      notifyListeners();
    });
  }

  Future<void> reload() async {
    if (_disposed) return;
    sources = await db.sources();
    playlists = await db.playlists();
    blacklist = await db.blacklist();
    catalogRevision++;
    notifyListeners();
  }

  void _indexChanged() {
    if (_foregroundSyncRunning && _foregroundSourceId != null) {
      final progress = index.progress[_foregroundSourceId];
      if (progress != null && progress.active) {
        unawaited(
          syncForeground.update(
            '风灵音乐 · 同步索引',
            progress.message,
            done: progress.count,
          ),
        );
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<T> busyRun<T>(Future<T> Function() callback) async {
    _busyOperations++;
    message = null;
    notifyListeners();
    try {
      return await callback();
    } catch (e) {
      message = e.toString();
      rethrow;
    } finally {
      _busyOperations--;
      if (!_disposed) await reload();
    }
  }

  Future<void> addSource({
    required SourceKind kind,
    required String name,
    required String url,
    required String username,
    required String password,
  }) async {
    final source = SourceProfile(
      id: const Uuid().v4(),
      name: name,
      kind: kind,
      url: url,
      username: username,
    );
    final adapter = factory.create(source);
    try {
      await adapter.login(password);
      await db.putSource(source);
    } catch (_) {
      await vault.delete(source.id);
      rethrow;
    } finally {
      adapter.close();
    }
    await reload();
    // Connection creation is an explicit user action: protect the first index.
    await syncSourceForeground(source);
  }

  void _interruptForegroundSync() {
    _foregroundSyncCancelled = true;
    final id = _foregroundSourceId;
    if (id != null) {
      index.cancel(id);
      metadataEnricher.cancel(id);
    }
  }

  Future<void> _pauseForegroundSync() async {
    final id = _foregroundSourceId;
    _interruptForegroundSync();
    if (id != null) {
      await Future.wait([
        index.cancelAndWait(id),
        metadataEnricher.cancelAndWait(id),
      ]);
    }
    await _foregroundSyncTask?.catchError((Object _) {});
  }

  void cancelActiveSync(String sourceId) {
    if (_foregroundSourceId == sourceId) {
      _interruptForegroundSync();
    } else {
      index.cancel(sourceId);
    }
  }

  Future<void> _runForegroundSync(
    List<SourceProfile> selected, {
    bool rescanDirectories = true,
    bool includeCloud = false,
  }) {
    if (_disposed) return Future.error(StateError('应用已关闭'));
    if (_foregroundSyncRunning) return Future.error(StateError('已有前台同步任务正在运行'));
    final task = _performForegroundSync(
      selected,
      rescanDirectories: rescanDirectories,
      includeCloud: includeCloud,
    );
    _foregroundSyncTask = task;
    return task;
  }

  Future<void> _performForegroundSync(
    List<SourceProfile> selected, {
    bool rescanDirectories = true,
    bool includeCloud = false,
  }) async {
    if (_foregroundSyncRunning) throw StateError('已有前台同步任务正在运行');
    if (selected.isEmpty) return;
    _foregroundSyncRunning = true;
    _foregroundSyncCancelled = false;
    notifyListeners();
    try {
      // Must start from a visible, explicit user action; Android 12+ forbids
      // background-initiated FGS starts. Never silently fall back on failure.
      await syncForeground.start();
      for (final source in selected) {
        if (_foregroundSyncCancelled || _disposed) break;
        if (!source.enabled || source.kind == SourceKind.local) continue;
        _foregroundSourceId = source.id;
        await syncForeground.update(
          '风灵音乐 · 同步索引',
          '正在读取 ${source.name}',
          force: true,
        );
        if (rescanDirectories) await syncSource(source);
        if (_foregroundSyncCancelled || _disposed) break;
        if (source.kind == SourceKind.webdav &&
            (!rescanDirectories ||
                index.progress[source.id]?.state == 'completed')) {
          await syncForeground.update(
            '风灵音乐 · 补全标签',
            '${source.name}：准备读取标签',
            force: true,
          );
          await metadataEnricher.complete(
            source,
            onStats: (stats) {
              if (_foregroundSyncCancelled || _disposed) return;
              unawaited(
                syncForeground.update(
                  '风灵音乐 · 补全标签',
                  '${source.name} · ${stats.processed} / ${stats.total} 首'
                      '（成功 ${stats.succeeded}，失败 ${stats.failed}，已缓存 ${stats.skipped}）',
                  done: stats.processed,
                  total: stats.total,
                ),
              );
            },
          );
        }
      }
      if (includeCloud && !_foregroundSyncCancelled && !_disposed) {
        _foregroundSourceId = null;
        await syncForeground.update('风灵音乐 · 同步歌单', '正在同步远程歌单', force: true);
        await cloud.syncAll();
      }
    } finally {
      final interruptedSource = _foregroundSourceId;
      if (_foregroundSyncCancelled && interruptedSource != null) {
        await metadataEnricher.cancelAndWait(interruptedSource);
      }
      _foregroundSourceId = null;
      _foregroundSyncRunning = false;
      try {
        if (!_disposed) await reload();
      } finally {
        await syncForeground.stop();
      }
    }
  }

  Future<void> syncSourceForeground(SourceProfile source) =>
      _runForegroundSync([source]);

  Future<void> enrichSourceForeground(SourceProfile source) {
    if (source.kind != SourceKind.webdav) {
      throw StateError('仅支持 WebDAV 标签补全');
    }
    return _runForegroundSync([source], rescanDirectories: false);
  }

  Future<void> syncAllForeground() =>
      _runForegroundSync([...sources], includeCloud: true);

  Future<void> syncSource(SourceProfile source) async {
    await busyRun(() async {
      await index.sync(source);
      if (_disposed || index.progress[source.id]?.state != 'completed') return;
      artwork.invalidate();
      await cloud.refreshCloudForSource(source);
    });
    if (!_disposed &&
        index.progress[source.id]?.state == 'completed' &&
        source.kind == SourceKind.webdav) {
      metadataEnricher.start(source);
    }
  }

  Future<void> updateConnection(
    SourceProfile source, {
    required String name,
    required String url,
    required String password,
  }) async {
    final target = url.trim();
    if ((source.kind == SourceKind.subsonic ||
            source.kind == SourceKind.webdav) &&
        target != source.url) {
      throw StateError('此协议无法核对服务器稳定身份。更换地址请添加新来源，以隔离旧缓存和歌单');
    }
    // Authenticate in a fresh namespace: old tokens never reach a new endpoint.
    final candidate = SourceProfile(
      id: const Uuid().v4(),
      name: name.trim(),
      kind: source.kind,
      url: target,
      username: source.username,
    );
    final adapter = factory.create(candidate);
    try {
      await adapter.login(password);
      if (source.kind == SourceKind.emby) {
        final oldServer = await vault.read(source.id, 'serverId');
        final newServer = await vault.read(candidate.id, 'serverId');
        final oldUser = await vault.read(source.id, 'userId');
        final newUser = await vault.read(candidate.id, 'userId');
        if ((oldServer != null && oldServer != newServer) ||
            (oldUser != null && oldUser != newUser) ||
            (target != source.url &&
                (oldServer == null || newServer == null))) {
          throw StateError('无法确认是原服务器和原账号，已保留原连接；请添加独立来源');
        }
      }
      if (playback.currentRef?.sourceId == source.id) await playback.pause();
      playback.invalidateSource(source.id);
      for (final key in ['token', 'password', 'userId', 'serverId']) {
        final value = await vault.read(candidate.id, key);
        if (value != null) await vault.write(source.id, key, value);
      }
      await db.putSource(
        SourceProfile(
          id: source.id,
          name: name.trim(),
          kind: source.kind,
          url: target,
          username: source.username,
          enabled: source.enabled,
          lastSync: source.lastSync,
        ),
      );
      artwork.invalidate();
      await reload();
    } finally {
      adapter.close();
      await vault.delete(candidate.id);
    }
  }

  Future<void> syncAll() async {
    var failed = 0;
    for (final s in [...sources]) {
      if (!s.enabled || s.kind == SourceKind.local) continue;
      try {
        await syncSource(s);
      } catch (_) {
        failed++;
      }
    }
    await cloud.syncAll();
    await reload();
    if (failed > 0) throw StateError('$failed 个来源未能完成同步，原索引已保留');
  }

  Future<void> toggleSource(SourceProfile source) async {
    try {
      await connections.toggle(source.id);
    } finally {
      await reload();
    }
  }

  Future<void> _suspendSource(SourceProfile source) async {
    metadataEnricher.cancel(source.id);
    playback.invalidateSource(source.id);
    if (playback.currentRef?.sourceId == source.id) await playback.pause();
    index.cancel(source.id);
    proxy.revokeSource(source.id);
    artwork.suspendSource(source.id);
    lyrics.suspendSource(source.id);
    await jobs.sourceUnavailable(source.id);
    await cache.cancelSource(source.id);
    await index.cancelAndWait(source.id);
  }

  Future<void> deleteSource(SourceProfile source) async {
    await db.db.update(
      'sources',
      {'enabled': 0},
      where: 'id=?',
      whereArgs: [source.id],
    );
    await _suspendSource(source);
    if (playback.currentRef?.sourceId == source.id) {
      await playback.pause();
      await playback.player.stop();
    }
    await jobs.cancelAffected(sourceId: source.id);
    await cache.clear(sourceId: source.id);
    await db.removeSourceData(source.id);
    await artwork.clearSource(source.id);
    await lyrics.clearSource(source.id);
    await vault.delete(source.id);
    await reload();
  }

  Future<void> toggleBlacklist(Track ref) async {
    await db.setBlocked(ref.ref, !blacklist.contains(ref.ref.key));
    await reload();
  }

  Future<void> toggleFavorite(Track ref) async {
    final keys = await db.playlistKeys('favorites');
    if (keys.contains(ref.ref.key)) {
      keys.removeWhere((x) => x == ref.ref.key);
    } else {
      keys.add(ref.ref.key);
    }
    await db.replacePlaylistKeys('favorites', keys);
    await reload();
  }

  Future<void> addPlaylist(String name, {SourceProfile? cloudSource}) async {
    if (cloudSource == null) {
      await cloud.newLocal(name);
    } else {
      await cloud.createCloud(cloudSource, name);
    }
    await reload();
  }

  Future<void> setPlaylistKeys(
    PlaylistModel playlist,
    List<String> keys,
  ) async {
    await cloud.editLocal(playlist.id, keys);
    await reload();
    if (playlist.kind == PlaylistKind.cloud) {
      await cloud.syncOne(playlist.id);
      await reload();
    }
  }

  Future<void> syncPlaylist(PlaylistModel playlist) async {
    await cloud.syncOne(playlist.id);
    await reload();
  }

  Future<void> copyPlaylist(
    PlaylistModel playlist, {
    SourceProfile? target,
  }) async {
    if (target == null) {
      await cloud.copyToLocal(playlist, '${playlist.name} · 本地副本');
    } else {
      await cloud.copyToCloud(playlist, target, '${playlist.name} · 云端副本');
    }
    await reload();
  }

  Future<void> deletePlaylist(
    PlaylistModel playlist, {
    bool remote = false,
  }) async {
    if (remote) {
      await cloud.deleteRemoteOnline(playlist);
    } else {
      await db.removePlaylist(playlist.id);
    }
    await reload();
  }

  Future<void> cachePlaylist(PlaylistModel playlist) async {
    final refs = (await db.playlistKeys(playlist.id))
        .map(TrackRef.parse)
        .where(
          (r) => sources.any(
            (s) => s.id == r.sourceId && s.kind != SourceKind.local,
          ),
        )
        .toList();
    await jobs.schedule(playlist.name, refs);
    notifyListeners();
  }

  Future<String?> loadLyrics(Track track, {bool forceRefresh = false}) =>
      lyrics.load(track, forceRefresh: forceRefresh);
  Future<void> attachLyrics(Track track) async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['lrc', 'txt'],
    );
    if (picked?.path == null) return;
    await importLyricsFile(track, File(picked!.path!));
  }

  Future<void> importLyricsFile(Track track, File original) async {
    await lyrics.importFile(track, original);
    notifyListeners();
  }

  Future<void> cacheTrack(Track track) async {
    final source = await db.source(track.ref.sourceId);
    if (source != null) await jobs.schedule(track.title, [track.ref]);
  }

  Future<UpdateCheck> checkForUpdates({bool beta = false}) =>
      AppUpdates(mirror: apiSettings.githubMirror).check(beta: beta);

  void _apiChanged() {
    if (!_disposed) notifyListeners();
  }

  Future<void> clearCache({String? sourceId, Set<String>? keys}) async {
    await jobs.cancelAffected(sourceId: sourceId, trackKeys: keys);
    await cache.clear(sourceId: sourceId, keys: keys);
    notifyListeners();
  }

  Future<void> importLocalFiles() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'flac', 'ogg', 'opus', 'wav', 'm4a', 'aac'],
    );
    if (picked.isEmpty) return;
    var local = sources.where((s) => s.kind == SourceKind.local).firstOrNull;
    local ??= const SourceProfile(
      id: 'local',
      name: '本地音乐',
      kind: SourceKind.local,
      url: 'file:///',
      username: '',
    );
    await db.putSource(local);
    final old = await db.tracks(sourceId: local.id, includeMissing: true);
    final entries = {for (final t in old) t.ref.id: t};
    for (final item in picked) {
      final path = item.path;
      if (path == null) continue;
      var f = File(path);
      if (!await f.exists()) continue;
      final scanner = LocalLibrary(root);
      f = await scanner.ownAndroidImport(f);
      final track = await scanner.read(f, local.id);
      entries[track.ref.id] = track;
    }
    await db.replaceSourceTracks(local.id, entries.values.toList());
    await reload();
  }

  Future<void> importLocalFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    final id = const Uuid().v4();
    final source = SourceProfile(
      id: id,
      name: p.basename(path),
      kind: SourceKind.local,
      url: Directory(path).uri.toString(),
      username: '',
    );
    await busyRun(() async {
      final tracks = await LocalLibrary(root).scan(Directory(path), id, []);
      await db.putSource(source);
      await db.replaceSourceTracks(id, tracks);
    });
  }

  Future<void> rescanLocal(SourceProfile source) async {
    if (source.url == 'file:///') return;
    await busyRun(() async {
      final old = await db.tracks(sourceId: source.id, includeMissing: true);
      final tracks = await LocalLibrary(root)
          .scan(Directory.fromUri(Uri.parse(source.url)), source.id, old);
      await db.replaceSourceTracks(source.id, tracks);
    });
  }

  Future<void> setDiagnosticLogging(bool value) async {
    if (_disposed) return;
    await db.setSetting('diagnostic_logs_enabled', value.toString());
    await diagnostics.setEnabled(value);
    notifyListeners();
  }

  Future<void> clearDiagnosticLogs() async {
    await diagnostics.clear();
    notifyListeners();
  }

  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    _interruptForegroundSync();
    final metadataStopped = metadataEnricher.shutdown();
    _catalogRefreshTimer?.cancel();
    _sleepLifecycle?.dispose();
    await sleepTimer.shutdown();
    desktop?.dispose();
    history.removeListener(_indexChanged);
    apiSettings.removeListener(_apiChanged);
    lrcApi.dispose();
    apiSettings.dispose();
    await history.shutdown();
    index.removeListener(_indexChanged);
    await index.shutdown();
    await connections.shutdown();
    await jobs.shutdown();
    await playback.shutdown();
    await proxy.dispose();
    await cache.shutdown();
    await webDavTags.shutdown();
    await metadataStopped;
    await _foregroundSyncTask?.catchError((Object _) {});
    await artwork.shutdown();
    await lyrics.shutdown();
    await assets.shutdown();
    await appearance.shutdown();
    await playerLayouts.shutdown();
    await diagnostics.shutdown();
    await db.close();
    await syncForeground.stop();
    syncForeground.dispose();
  }
}
