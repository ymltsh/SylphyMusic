import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Opt-in, privacy-preserving diagnostics, intentionally separate from logcat.
///
/// All event names and detail keys/values are restricted to short, machine-
/// readable tokens. Never pass URLs, IDs, metadata, paths, exception messages,
/// stack traces or any credentials to [record].
class DiagnosticLogs {
  DiagnosticLogs(
    this.directory, {
    this.maxFileBytes = 512 * 1024,
    this.retainedFiles = 3,
  }) : assert(maxFileBytes > 128),
       assert(retainedFiles >= 1);

  final Directory directory;
  final int maxFileBytes;
  final int retainedFiles;
  bool enabled = false;
  bool _closed = false;
  Future<void> _pending = Future<void>.value();

  static final RegExp _safeToken = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,47}$');
  static const Set<String> _detailKeys = {
    'autoplay',
    'attempt',
    'buffering',
    'http_status',
    'index',
    'manual',
    'playing',
    'queue_size',
    'source_kind',
    'stage',
    'state',
    'system',
    'type',
  };

  File _file(int index) => File(
    '${directory.path}${Platform.pathSeparator}'
    'diagnostic${index == 0 ? '' : '.$index'}.jsonl',
  );

  Future<void> initialize({required bool enabled}) async {
    if (_closed) return;
    this.enabled = enabled;
    if (enabled) record('diagnostics', 'session_started');
  }

  /// No raw free-form messages. Only allowlisted structured fields are saved.
  void record(
    String scope,
    String event, {
    Map<String, Object?> details = const {},
  }) {
    if (_closed || !enabled) return;
    if (!_safeToken.hasMatch(scope) || !_safeToken.hasMatch(event)) return;
    final safeDetails = <String, Object>{};
    for (final item in details.entries) {
      if (!_detailKeys.contains(item.key)) continue;
      final value = item.value;
      if (value is bool) {
        safeDetails[item.key] = value;
      } else if (value is int && value >= 0 && value <= 1000000000) {
        safeDetails[item.key] = value;
      } else if (value is String && _safeToken.hasMatch(value)) {
        safeDetails[item.key] = value;
      }
    }
    final line =
        '${jsonEncode({'utc': DateTime.now().toUtc().toIso8601String(), 'scope': scope, 'event': event, ...safeDetails})}\n';
    // The queue preserves event order and never delays playback callbacks.
    unawaited(
      _serialize(() => _append(line)).catchError((Object _) {
        // Diagnostics must not interrupt music or crash the application.
      }),
    );
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    // Keep the shared queue healthy even if a single action fails, while
    // returning the actual failure to explicit export/clear callers.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _append(String line) async {
    await directory.create(recursive: true);
    final file = _file(0);
    final incomingBytes = utf8.encode(line).length;
    if (await file.exists() &&
        await file.length() + incomingBytes > maxFileBytes) {
      final oldest = _file(retainedFiles - 1);
      if (await oldest.exists()) await oldest.delete();
      for (var i = retainedFiles - 2; i >= 0; i--) {
        final from = _file(i);
        if (await from.exists()) await from.rename(_file(i + 1).path);
      }
    }
    await file.writeAsString(line, mode: FileMode.append);
  }

  Future<void> flush() => _pending;

  Future<void> setEnabled(bool value) async {
    if (_closed || enabled == value) return;
    if (value) {
      enabled = true;
      record('diagnostics', 'enabled');
    } else {
      record('diagnostics', 'disabled');
      enabled = false;
    }
    await flush();
  }

  String get exportFileName {
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[-:.]'), '')
        .replaceAll('T', '_');
    return 'SylphyMusic-diagnostics-$stamp.txt';
  }

  Future<Uint8List> exportBytes() => _serialize(() async {
    final output = StringBuffer(
      'SylphyMusic diagnostics (UTC, opt-in)\n'
      'Contains only allowlisted event names and fields. '
      'Does not include Android logcat or native crash dumps.\n\n',
    );
    for (var i = retainedFiles - 1; i >= 0; i--) {
      final file = _file(i);
      if (await file.exists()) output.write(await file.readAsString());
    }
    return Uint8List.fromList(utf8.encode(output.toString()));
  });

  Future<void> clear() => _serialize(() async {
    for (var i = 0; i < retainedFiles; i++) {
      final file = _file(i);
      if (await file.exists()) await file.delete();
    }
    if (enabled) {
      // Record only that a deletion happened, never the deleted contents.
      final line =
          '${jsonEncode({'utc': DateTime.now().toUtc().toIso8601String(), 'scope': 'diagnostics', 'event': 'cleared'})}\n';
      await _append(line);
    }
  });

  Future<void> shutdown() async {
    if (_closed) return;
    if (enabled) record('diagnostics', 'session_stopped');
    _closed = true;
    enabled = false;
    await flush();
  }
}
