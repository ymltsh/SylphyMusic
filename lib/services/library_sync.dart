import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/models.dart';
import '../data/app_db.dart';
import 'sources.dart';

class IndexProgress {
  const IndexProgress(this.state, this.count, this.message);
  final String state, message;
  final int count;
  bool get active => state == 'reading' || state == 'committing';
}

class _IndexRun {
  _IndexRun(this.adapter);
  final MusicAdapter adapter;
  bool cancelled = false;
  late Future<void> future;
}

/// A remote scan holds one page of metadata at a time. SQLite staging remains
/// invisible until a complete, validated server snapshot commits atomically.
class LibrarySync extends ChangeNotifier {
  LibrarySync(this.db, this.factory);
  final AppDb db;
  final AdapterFactory factory;
  final Map<String, _IndexRun> _runs = {};
  final Map<String, IndexProgress> progress = {};
  bool _stopped = false;

  Future<Set<String>> interruptedSources() async =>
      (await db.db.query('index_runs'))
          .map((row) => row['source_id'] as String)
          .toSet();

  Future<void> sync(SourceProfile source) {
    if (_stopped) throw StateError('索引服务已关闭');
    final existing = _runs[source.id];
    if (existing != null) return existing.future;
    final run = _IndexRun(factory.create(source));
    _runs[source.id] = run;
    run.future = _scan(source, run);
    return run.future;
  }

  void _publish(String id, String state, int count, String message) {
    progress[id] = IndexProgress(state, count, message);
    notifyListeners();
  }

  Future<void> _scan(SourceProfile source, _IndexRun run) async {
    await Future<void>.value();
    final id = const Uuid().v4();
    var count = 0;
    _publish(source.id, 'reading', count, '正在读取索引');
    try {
      await db.db.rawInsert(
        'INSERT OR REPLACE INTO index_runs(source_id,run_id) VALUES (?,?)',
        [source.id, id],
      );
      await for (final page in run.adapter.libraryPages()) {
        if (run.cancelled) break;
        await db.stageIndexPage(id, source.id, page);
        count += page.length;
        _publish(source.id, 'reading', count, '已读取 $count 首，旧索引仍可浏览');
      }
      if (run.cancelled) {
        _publish(source.id, 'cancelled', count, '已取消，保留原索引');
        return;
      }
      _publish(source.id, 'committing', count, '正在提交完整索引');
      await db.commitIndex(id, source);
      _publish(source.id, 'completed', count, '已同步 $count 首');
    } catch (_) {
      if (run.cancelled) {
        _publish(source.id, 'cancelled', count, '已取消，保留原索引');
        return;
      }
      _publish(source.id, 'failed', count, '索引未完成，已保留原数据；可重试');
      throw StateError('索引同步失败，已保留原数据；请检查连接或重新登录后重试');
    } finally {
      run.adapter.close();
      await db.discardIndex(id);
      await db.db.delete(
        'index_runs',
        where: 'source_id=? AND run_id=?',
        whereArgs: [source.id, id],
      );
      _runs.remove(source.id);
    }
  }

  void cancel(String sourceId) {
    if (progress[sourceId]?.state == 'committing') return;
    final run = _runs[sourceId];
    if (run == null) return;
    run.cancelled = true;
    run.adapter.close();
  }

  Future<void> cancelAndWait(String sourceId) async {
    final run = _runs[sourceId];
    cancel(sourceId);
    if (run != null) await run.future.catchError((Object _) {});
  }

  Future<void> shutdown() async {
    _stopped = true;
    final runs = _runs.values.toList();
    for (final id in _runs.keys.toList()) {
      cancel(id);
    }
    await Future.wait(runs.map((run) => run.future.catchError((Object _) {})));
  }
}
