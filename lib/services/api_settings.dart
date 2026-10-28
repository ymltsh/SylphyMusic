import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/app_db.dart';

/// User-configurable public endpoints. These URLs never carry music credentials.
class ApiSettings extends ChangeNotifier {
  ApiSettings(this.db, {http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  static const defaultQuoteUrl = 'https://v1.hitokoto.cn/?encode=json';
  static const defaultGitHubMirror = 'https://hub.wgen.top/';
  static const defaultLrcApiUrl = 'https://api.lrc.cx/lyrics';
  static const fallbackQuote = '音乐随心，聆听自在。';
  final AppDb db;
  final http.Client Function() _clientFactory;

  String quoteUrl = defaultQuoteUrl;
  String githubMirror = defaultGitHubMirror;
  bool lrcApiEnabled = false;
  String lrcApiUrl = defaultLrcApiUrl;
  String quote = fallbackQuote;
  String _quoteDay = '';
  int _requestId = 0;
  bool _loading = false;

  static String validateQuoteUrl(String value) {
    final candidate = value.trim().isEmpty ? defaultQuoteUrl : value.trim();
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.fragment.isNotEmpty) {
      throw const FormatException('每日一言 API 需要有效的 HTTPS 地址');
    }
    return uri.toString();
  }

  static String validateGitHubMirror(String value) {
    final candidate = value.trim().isEmpty ? defaultGitHubMirror : value.trim();
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('GitHub 加速 API 需要有效的 HTTPS 前缀地址');
    }
    return '${uri.toString().replaceFirst(RegExp(r'/+$'), '')}/';
  }

  static String validateLrcApiUrl(String value) {
    final candidate = value.trim().isEmpty ? defaultLrcApiUrl : value.trim();
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('LrcApi 需要有效的 HTTP(S) 地址，且不能包含凭据、查询参数或片段');
    }
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    final endpoint = path.isEmpty
        ? '/lyrics'
        : (path.endsWith('/lyrics') || path.endsWith('/jsonapi')
              ? path
              : '$path/lyrics');
    return uri.replace(path: endpoint).toString();
  }

  static String parseQuote(String response) {
    final value = jsonDecode(response);
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is Map) {
      final data = value['data'] is Map ? value['data'] as Map : value;
      for (final key in ['hitokoto', 'text', 'content', 'sentence']) {
        final text = data[key];
        if (text is String && text.trim().isNotEmpty) return text.trim();
      }
    }
    throw const FormatException('每日一言 API 未返回可识别的文本');
  }

  static String _day() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  Future<void> initialize() async {
    try {
      quoteUrl = validateQuoteUrl(await db.setting('api_quote_url') ?? '');
    } on FormatException {
      quoteUrl = defaultQuoteUrl;
    }
    try {
      githubMirror = validateGitHubMirror(
        await db.setting('api_github_mirror') ?? '',
      );
    } on FormatException {
      githubMirror = defaultGitHubMirror;
    }
    try {
      lrcApiUrl = validateLrcApiUrl(await db.setting('api_lrc_url') ?? '');
    } on FormatException {
      lrcApiUrl = defaultLrcApiUrl;
    }
    lrcApiEnabled = await db.setting('api_lrc_enabled') == 'true';
    _quoteDay = await db.setting('api_quote_day') ?? '';
    final cached = await db.setting('api_quote_text');
    quote = cached != null && cached.trim().isNotEmpty ? cached : fallbackQuote;
    notifyListeners();
    unawaited(refreshQuote());
  }

  Future<void> setQuoteUrl(String value) async {
    final next = validateQuoteUrl(value);
    await db.setSetting('api_quote_url', next);
    quoteUrl = next;
    _quoteDay = '';
    ++_requestId; // Invalidate an in-flight request to the old endpoint.
    _loading = false;
    notifyListeners();
    await refreshQuote(force: true);
  }

  Future<void> setGitHubMirror(String value) async {
    final next = validateGitHubMirror(value);
    await db.setSetting('api_github_mirror', next);
    githubMirror = next;
    notifyListeners();
  }

  Future<void> setLrcApiUrl(String value) async {
    final next = validateLrcApiUrl(value);
    await db.setSetting('api_lrc_url', next);
    lrcApiUrl = next;
    notifyListeners();
  }

  Future<void> setLrcApiEnabled(bool value) async {
    await db.setSetting('api_lrc_enabled', value.toString());
    lrcApiEnabled = value;
    notifyListeners();
  }

  /// At most one successful fetch per local day. Failure preserves cached text.
  Future<void> refreshQuote({bool force = false}) async {
    if (!force && (_quoteDay == _day() || _loading)) return;
    final requestId = ++_requestId;
    _loading = true;
    final client = _clientFactory();
    try {
      final response = await client
          .get(
            Uri.parse(quoteUrl),
            headers: const {'Accept': 'application/json, text/plain'},
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || response.bodyBytes.length > 32768) {
        throw const FormatException('每日一言 API 请求失败');
      }
      final text = parseQuote(utf8.decode(response.bodyBytes));
      if (requestId != _requestId) return;
      final day = _day();
      quote = text;
      _quoteDay = day;
      notifyListeners();
      await db.setSetting('api_quote_text', text);
      await db.setSetting('api_quote_day', day);
    } catch (_) {
      // A quote is decorative; network failure must not block music playback.
    } finally {
      client.close();
      if (requestId == _requestId) _loading = false;
    }
  }

  @override
  void dispose() {
    ++_requestId; // Prevent an in-flight response from updating a disposed app.
    super.dispose();
  }
}
