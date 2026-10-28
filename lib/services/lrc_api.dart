import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/models.dart';
import 'api_settings.dart';
import 'sources.dart' show AuthVault;

/// Optional online lyric provider used only after the configured source fails
/// to provide lyrics. Authentication is read from the OS-backed AuthVault.
class LrcApiClient {
  LrcApiClient(
    this.settings,
    this.vault, {
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new {
    _configuration = (settings.lrcApiEnabled, settings.lrcApiUrl);
    settings.addListener(_settingsChanged);
  }

  final ApiSettings settings;
  final AuthVault vault;
  final http.Client Function() _clientFactory;

  final _requests =
      <http.Client, ({String sourceId, Completer<void> cancel})>{};
  final _epochs = <String, int>{};
  bool _disposed = false;
  int _revision = 0;
  late (bool, String) _configuration;

  void _settingsChanged() {
    final next = (settings.lrcApiEnabled, settings.lrcApiUrl);
    if (_configuration == next) return;
    _configuration = next;
    _cancelAll();
  }

  void _cancelAll() {
    _revision++;
    for (final entry in _requests.entries.toList()) {
      entry.value.cancel.complete();
      entry.key.close();
      _requests.remove(entry.key);
    }
  }

  void suspendSource(String sourceId) {
    _epochs[sourceId] = (_epochs[sourceId] ?? 0) + 1;
    for (final entry in _requests.entries.toList()) {
      if (entry.value.sourceId != sourceId) continue;
      entry.value.cancel.complete();
      entry.key.close();
      _requests.remove(entry.key);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    settings.removeListener(_settingsChanged);
    _cancelAll();
  }

  Future<String?> fetch(Track track) async {
    final epoch = _epochs[track.ref.sourceId] ?? 0;
    final revision = _revision;
    if (_disposed || !settings.lrcApiEnabled) return null;
    final query = <String, String>{
      if (track.title.trim().isNotEmpty) 'title': track.title.trim(),
      if (track.artist.trim().isNotEmpty) 'artist': track.artist.trim(),
      if (track.album.trim().isNotEmpty) 'album': track.album.trim(),
    };
    if (query.isEmpty) return null;

    final uri = Uri.parse(settings.lrcApiUrl).replace(queryParameters: query);
    final token = (await vault.read('lrcapi', 'token') ?? '').trim();
    if (_disposed ||
        !settings.lrcApiEnabled ||
        revision != _revision ||
        epoch != (_epochs[track.ref.sourceId] ?? 0)) {
      return null;
    }
    if (token.isNotEmpty && uri.scheme != 'https' && !_isLoopback(uri.host)) {
      throw StateError('配置了 LrcApi 鉴权密钥时必须使用 HTTPS（本机回环地址除外）');
    }

    final client = _clientFactory();
    final cancel = Completer<void>();
    _requests[client] = (sourceId: track.ref.sourceId, cancel: cancel);
    Future<String?> read() async {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll(const {
          'Accept': 'application/json, text/plain;q=0.9, */*;q=0.1',
        });
      if (token.isNotEmpty) request.headers['Authorization'] = token;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw StateError('LrcApi 返回了不受支持的 HTTP 重定向');
      }
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        throw StateError('LrcApi 请求失败（HTTP ${response.statusCode}）');
      }
      final bytes = await _readBounded(response.stream)
          .timeout(const Duration(seconds: 12));
      return parseResponse(
        utf8.decode(bytes),
        contentType: response.headers['content-type'],
      );
    }

    try {
      return await Future.any([
        read(),
        cancel.future.then<String?>((_) => null),
      ]);
    } finally {
      _requests.remove(client);
      client.close();
    }
  }

  static bool _isLoopback(String host) {
    final value = host.toLowerCase();
    return value == 'localhost' || value == '127.0.0.1' || value == '::1';
  }

  static Future<List<int>> _readBounded(Stream<List<int>> stream) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > 1024 * 1024) {
        throw StateError('LrcApi 歌词响应超过 1 MiB 限制');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  /// Supports the plain-text /lyrics endpoint and the /jsonapi result list.
  static String? parseResponse(String body, {String? contentType}) {
    final text = body.trim().replaceFirst('\uFEFF', '').trim();
    if (text.isEmpty) return null;
    final type = contentType?.toLowerCase() ?? '';
    final looksJson =
        type.contains('json') ||
        text.startsWith('{') ||
        text.startsWith('"') ||
        RegExp(r'^\[\s*(?:[\{"\]]|$)').hasMatch(text);
    if (!looksJson) return text;
    return _extract(jsonDecode(text));
  }

  static String? _extract(Object? value) {
    if (value is String) {
      final text = value.trim();
      return text.isEmpty ? null : text;
    }
    if (value is List) {
      for (final item in value) {
        final lyrics = _extract(item);
        if (lyrics != null) return lyrics;
      }
    }
    if (value is Map) {
      for (final key in ['lyrics', 'lrc', 'text', 'content']) {
        if (value.containsKey(key)) {
          final lyrics = _extract(value[key]);
          if (lyrics != null) return lyrics;
        }
      }
      for (final key in ['data', 'result', 'results', 'items']) {
        if (value.containsKey(key)) {
          final lyrics = _extract(value[key]);
          if (lyrics != null) return lyrics;
        }
      }
    }
    return null;
  }
}
