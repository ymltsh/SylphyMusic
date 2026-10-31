import '../core/models.dart';
import '../data/app_db.dart';
import 'sources.dart';

class SourceConnections {
  SourceConnections(
    this.db,
    this.factory, {
    required this.onDisabled,
    required this.onEnabled,
  });
  final AppDb db;
  final AdapterFactory factory;
  final Future<void> Function(SourceProfile) onDisabled, onEnabled;
  final Map<String, Future<void>> _pending = {};
  final Map<String, MusicAdapter> _validators = {};
  bool _stopped = false;

  SourceProfile _enabled(SourceProfile source, bool enabled) => SourceProfile(
    id: source.id,
    name: source.name,
    kind: source.kind,
    url: source.url,
    username: source.username,
    remoteUserId: source.remoteUserId,
    enabled: enabled,
    lastSync: source.lastSync,
    webdavBasePath: source.webdavBasePath,
    webdavMaxDepth: source.webdavMaxDepth,
  );

  Future<void> toggle(String id) {
    if (_stopped) throw StateError('来源连接服务已关闭');
    final existing = _pending[id];
    if (existing != null) return existing;
    final future = _toggle(id);
    _pending[id] = future;
    return future.whenComplete(() => _pending.remove(id));
  }

  Future<void> _toggle(String id) async {
    final source = await db.source(id);
    if (_stopped) throw StateError('来源连接服务已关闭');
    if (source == null) throw StateError('来源已移除');
    if (source.enabled) {
      // Reject new work before closing existing connections.
      final disabled = _enabled(source, false);
      await db.putSource(disabled);
      await onDisabled(disabled);
      return;
    }
    if (source.kind != SourceKind.local) {
      final adapter = factory.create(source);
      _validators[id] = adapter;
      try {
        await adapter.validateConnection();
      } finally {
        adapter.close();
        _validators.remove(id);
      }
    }
    if (_stopped) throw StateError('来源连接服务已关闭');
    final current = await db.source(id);
    if (_stopped) throw StateError('来源连接服务已关闭');
    if (current == null ||
        current.url != source.url ||
        current.username != source.username ||
        current.kind != source.kind ||
        current.webdavBasePath != source.webdavBasePath ||
        current.webdavMaxDepth != source.webdavMaxDepth) {
      throw StateError('来源连接已变更，请重新操作');
    }
    final enabled = _enabled(current, true);
    await db.putSource(enabled);
    await onEnabled(enabled);
  }

  Future<void> shutdown() async {
    _stopped = true;
    for (final adapter in _validators.values.toList()) {
      adapter.close();
    }
    await Future.wait(
      _pending.values.toList().map(
        (future) => future.catchError((Object _) {}),
      ),
    );
  }
}
