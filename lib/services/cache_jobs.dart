import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:uuid/uuid.dart';

import '../core/models.dart';
import '../data/app_db.dart';
import 'cache.dart';
import 'native_lifecycle.dart';

class CacheJobs {
  CacheJobs(this.db, this.cache) {
    if (Platform.isAndroid) {
      _lifecycle.setMethodCallHandler((call) async {
        if (['pause', 'timeout', 'unavailable'].contains(call.method)) {
          await pause();
        }
      });
    }
  }
  static const _lifecycle = MethodChannel('music.sylphy/cache_lifecycle');
  static const _permissions = MethodChannel(
    'music.sylphy/notification_permission',
  );
  final AppDb db;
  final CacheManager cache;
  final _heartbeat = NativeHeartbeat(_lifecycle);
  final Set<String> _busy = {};
  bool _stopping = false;
  bool _pumping = false;
  bool _requested = false;
  bool paused = false;
  Completer<void>? _idle;
  Future<String> schedule(String title, List<TrackRef> refs) async {
    if (_stopping) throw StateError('缓存调度器已关闭');
    final id = const Uuid().v4();
    // Persist the frozen playlist and its header together, including on crash.
    await db.db.transaction((txn) async {
      await txn.insert('cache_jobs', {
        'id': id,
        'label': title,
        'state': 'pending',
        'created': DateTime.now().millisecondsSinceEpoch,
      });
      final seen = <String>{};
      var i = 0;
      for (final ref in refs) {
        if (!seen.add(ref.key)) continue;
        await txn.insert('cache_job_items', {
          'job_id': id,
          'position': i++,
          'track_key': ref.key,
          'state': 'pending',
          'error': '',
        });
      }
    });
    unawaited(run());
    return id;
  }

  Future<void> run() async {
    if (_stopping || paused) return;
    if (_pumping) {
      _requested = true;
      return;
    }
    _pumping = true;
    _idle = Completer<void>();
    var lifecycleStarted = false;
    try {
      final pending = await db.db.query(
        'cache_jobs',
        columns: ['id'],
        where: "state IN ('pending','running')",
        limit: 1,
      );
      if (pending.isEmpty) return;
      if (Platform.isAndroid) {
        try {
          await _permissions.invokeMethod<void>('request');
        } on MissingPluginException {
          // The auto-resume path may run before MainActivity is attached.
        }
        await _lifecycle.invokeMethod<void>('start');
        lifecycleStarted = true;
        var ready = false;
        for (var i = 0; i < 60; i++) {
          ready = await _lifecycle.invokeMethod<bool>('status') ?? false;
          if (ready || paused || _stopping) break;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        if (!ready) throw PlatformException(code: 'cache_service_not_ready');
        _heartbeat.start();
      }
      do {
        _requested = false;
        final jobs = await db.db.query(
          'cache_jobs',
          where: "state IN ('pending','running')",
          orderBy: 'created',
        );
        for (final job in jobs) {
          if (_stopping || paused) break;
          final id = job['id'] as String;
          if (_busy.add(id)) await _work(id);
        }
      } while (_requested && !_stopping && !paused);
    } on PlatformException {
      paused = true;
    } finally {
      _heartbeat.stop();
      try {
        if (lifecycleStarted) await _lifecycle.invokeMethod<void>('stop');
      } finally {
        _pumping = false;
        _idle?.complete();
        if (_requested && !_stopping && !paused) unawaited(run());
      }
    }
  }

  Future<void> cancelJob(String jobId) async {
    final rows = await db.db.query(
      'cache_job_items',
      where: 'job_id=?',
      whereArgs: [jobId],
    );
    // Publish cancellation before interrupting I/O so a pending worker cannot
    // start the same item between the cancellation request and its DB update.
    await db.db.transaction((txn) async {
      await txn.update(
        'cache_job_items',
        {'state': 'cancelled'},
        where: 'job_id=? AND state!=?',
        whereArgs: [jobId, 'done'],
      );
      await txn.update(
        'cache_jobs',
        {'state': 'cancelled'},
        where: 'id=?',
        whereArgs: [jobId],
      );
    });
    for (final row in rows) {
      if (row['state'] == 'done') continue;
      final ref = TrackRef.parse(row['track_key'] as String);
      final other = await db.db.query(
        'cache_job_items',
        columns: ['job_id'],
        where: "track_key=? AND job_id!=? AND state IN ('pending','running')",
        whereArgs: [ref.key, jobId],
        limit: 1,
      );
      if (other.isEmpty) await cache.cancel(ref);
    }
  }

  Future<void> _work(String jobId) async {
    try {
      final claimed = await db.db.update(
        'cache_jobs',
        {'state': 'running'},
        where: "id=? AND state IN ('pending','running')",
        whereArgs: [jobId],
      );
      if (claimed == 0) return;
      final items = await db.db.query(
        'cache_job_items',
        where: "job_id=? AND state IN ('pending','running')",
        whereArgs: [jobId],
        orderBy: 'position',
      );
      for (final item in items) {
        if (_stopping || paused) break;
        final pos = item['position'] as int;
        final status = await db.db.query(
          'cache_job_items',
          columns: ['state'],
          where: 'job_id=? AND position=?',
          whereArgs: [jobId, pos],
          limit: 1,
        );
        if (status.isEmpty || status.first['state'] == 'cancelled') continue;
        final ref = TrackRef.parse(item['track_key'] as String);
        final itemClaimed = await db.db.update(
          'cache_job_items',
          {'state': 'running'},
          where: "job_id=? AND position=? AND state IN ('pending','running')",
          whereArgs: [jobId, pos],
        );
        if (itemClaimed == 0) continue;
        if (_stopping || paused) {
          await db.db.update(
            'cache_job_items',
            {'state': 'pending'},
            where: "job_id=? AND position=? AND state='running'",
            whereArgs: [jobId, pos],
          );
          break;
        }
        try {
          if (!await cache.contains(ref)) {
            final track = await db.track(ref);
            final source = await db.source(ref.sourceId);
            if (track == null || source == null || !source.enabled) {
              throw StateError('音源不存在或已禁用');
            }
            final current = await db.db.query(
              'cache_job_items',
              columns: ['state'],
              where: 'job_id=? AND position=?',
              whereArgs: [jobId, pos],
            );
            if (_stopping || paused || current.single['state'] != 'running') {
              throw StateError('缓存任务已暂停或取消');
            }
            await cache.fetchWhole(track, source);
          }
          if (!await cache.contains(ref)) throw StateError('整曲缓存尚未完成');
          await db.db.update(
            'cache_job_items',
            {'state': 'done', 'error': ''},
            where: "job_id=? AND position=? AND state='running'",
            whereArgs: [jobId, pos],
          );
        } catch (e) {
          await db.db.update(
            'cache_job_items',
            {
              'state': paused || _stopping ? 'pending' : 'failed',
              'error': paused
                  ? '用户或系统已暂停缓存'
                  : e is HttpException ||
                        e is SocketException ||
                        e is HandshakeException
                  ? '网络音频读取失败，请检查连接后重试'
                  : e.toString(),
            },
            where: "job_id=? AND position=? AND state='running'",
            whereArgs: [jobId, pos],
          );
        }
      }
      await _updateJobState(jobId);
    } finally {
      _busy.remove(jobId);
    }
  }

  Future<void> _updateJobState(String jobId) async {
    final states = await db.db.query(
      'cache_job_items',
      columns: ['state'],
      where: 'job_id=?',
      whereArgs: [jobId],
    );
    final values = states.map((row) => row['state']).toSet();
    final state = values.contains('pending') || values.contains('running')
        ? 'pending'
        : values.contains('failed')
        ? 'failed'
        : values.contains('cancelled')
        ? 'cancelled'
        : 'completed';
    await db.db.update(
      'cache_jobs',
      {'state': state},
      where: "id=? AND state!='cancelled'",
      whereArgs: [jobId],
    );
  }

  Future<void> cancelAffected({
    String? sourceId,
    Set<String>? trackKeys,
  }) async {
    final items = await db.db.query(
      'cache_job_items',
      where: "state IN ('pending','running')",
    );
    for (final row in items) {
      final key = row['track_key'] as String;
      if (sourceId != null && TrackRef.parse(key).sourceId != sourceId) {
        continue;
      }
      if (trackKeys != null && !trackKeys.contains(key)) continue;
      await db.db.update(
        'cache_job_items',
        {'state': 'cancelled'},
        where: 'job_id=? AND position=?',
        whereArgs: [row['job_id'], row['position']],
      );
      await cache.cancel(TrackRef.parse(key));
    }
  }

  Future<void> sourceUnavailable(String id) async {
    final rows =
        (await db.db.query(
              'cache_job_items',
              where: "state IN ('pending','running')",
            ))
            .where(
              (row) =>
                  TrackRef.parse(row['track_key'] as String).sourceId == id,
            )
            .toList();
    final jobs = <String>{}, refs = <TrackRef>{};
    await db.db.transaction((tx) async {
      for (final row in rows) {
        jobs.add(row['job_id'] as String);
        refs.add(TrackRef.parse(row['track_key'] as String));
        await tx.update(
          'cache_job_items',
          {'state': 'failed', 'error': '来源已停用；重新启用后可手动重试'},
          where: "job_id=? AND position=? AND state IN ('pending','running')",
          whereArgs: [row['job_id'], row['position']],
        );
      }
    });
    for (final ref in refs) {
      await cache.cancel(ref);
    }
    for (final job in jobs) {
      await _updateJobState(job);
    }
  }

  void stop() {
    _stopping = true;
  }

  Future<void> retry(String jobId) async {
    paused = false;
    await db.db.update(
      'cache_job_items',
      {'state': 'pending', 'error': ''},
      where: "job_id=? AND state='failed'",
      whereArgs: [jobId],
    );
    await db.db.update(
      'cache_jobs',
      {'state': 'pending'},
      where: 'id=?',
      whereArgs: [jobId],
    );
    unawaited(run());
  }

  Future<void> pause() async {
    paused = true;
    final idle = _idle;
    final items = await db.db.query(
      'cache_job_items',
      where: "state='running'",
    );
    for (final item in items) {
      await cache.cancel(TrackRef.parse(item['track_key'] as String));
    }
    await idle?.future;
  }

  Future<void> resume() async {
    paused = false;
    unawaited(run());
  }

  Future<void> shutdown() async {
    _stopping = true;
    await pause();
    await _idle?.future;
    if (Platform.isAndroid) _lifecycle.setMethodCallHandler(null);
  }
}
