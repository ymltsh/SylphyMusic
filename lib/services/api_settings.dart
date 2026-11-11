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
  static const defaultLlmUrl = 'https://api.openai.com/v1/chat/completions';
  static const defaultLlmModel = 'gpt-4o-mini';
  // Default editable editorial identity. Safety and JSON contracts are
  // appended in LlmRecommendationClient, independent of user preferences.
  static const defaultLlmSystemPrompt =
      '你是一位懂得尊重距离感的音乐笔友，不是算法报告员。'
      '你从读者自己的曲库里挑选自己觉得值得分享的歌，写一封给老朋友的短笺。'
      '口吻亲近、真诚、舒展、自然，不营销、不讨好、不机械罗列。'
      '用曲名、歌手、专辑和已提供的听歌偏好作为书信的真实细节，'
      '可以表达你的好奇与选择理由，但不能假装真的聆听过音频，'
      '也不能编造两人共同经历、个人记忆、歌曲情绪、歌词或背景故事。';
  static const defaultLlmUserPrompt =
      '像一位相识已久但有分寸的笔友写信：开头自然地问候，'
      '讲讲今天翻阅我的曲库时注意到什么、为何挑了这些歌，'
      '结尾留一句不刻意的祝福。可以从每日一言和有证据的公开热度寻找灵感，'
      '但不生硬引用，不写排行榜报告；愿意介绍些我平时不常听的歌。';
  static const fallbackQuote = '音乐随心，聆听自在。';
  final AppDb db;
  final http.Client Function() _clientFactory;

  String quoteUrl = defaultQuoteUrl;
  String githubMirror = defaultGitHubMirror;
  bool lrcApiEnabled = false;
  String lrcApiUrl = defaultLrcApiUrl;
  bool llmEnabled = false;
  String llmUrl = defaultLlmUrl;
  String llmModel = defaultLlmModel;
  String llmMode = 'assist'; // assist or lead
  String llmUserPrompt = defaultLlmUserPrompt;
  String llmSystemPrompt = defaultLlmSystemPrompt;
  int llmRevision = 0;
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

  static bool isLoopbackHost(String host) {
    final h = host.toLowerCase();
    return h == 'localhost' || h == '127.0.0.1' || h == '::1' || h == '[::1]';
  }

  static String validateLlmUrl(String value) {
    final candidate = value.trim().isEmpty ? defaultLlmUrl : value.trim();
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' && isLoopbackHost(uri.host)))) {
      throw const FormatException(
        'LLM 接口需要 HTTPS 地址（本机回环可使用 HTTP），不允许嵌入凭据或查询参数',
      );
    }
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.isEmpty || path == '/') {
      throw const FormatException('请填写完整的 /v1/chat/completions 等兼容接口路径');
    }
    return uri.toString();
  }

  static String validateLlmModel(String value) {
    final model = value.trim();
    if (model.isEmpty ||
        model.length > 100 ||
        model.contains(RegExp(r'[\x00-\x1f]'))) {
      throw const FormatException('请输入有效的 LLM 模型名称');
    }
    return model;
  }

  Future<void> _updateLlmRevision() async {
    llmRevision++;
    await db.setSetting('api_llm_revision', llmRevision.toString());
    notifyListeners();
  }

  Future<void> setLlmEnabled(bool value) async {
    if (llmEnabled == value) return;
    await db.setSetting('api_llm_enabled', value.toString());
    llmEnabled = value;
    await _updateLlmRevision();
  }

  Future<void> setLlmUrl(String value) async {
    final next = validateLlmUrl(value);
    if (llmUrl == next) return;
    await db.setSetting('api_llm_url', next);
    llmUrl = next;
    await _updateLlmRevision();
  }

  Future<void> setLlmModel(String value) async {
    final next = validateLlmModel(value);
    if (llmModel == next) return;
    await db.setSetting('api_llm_model', next);
    llmModel = next;
    await _updateLlmRevision();
  }

  Future<void> setLlmMode(String value) async {
    if (value != 'assist' && value != 'lead') {
      throw const FormatException('未知的 LLM 推荐模式');
    }
    if (llmMode == value) return;
    await db.setSetting('api_llm_mode', value);
    llmMode = value;
    await _updateLlmRevision();
  }

  /// The entire user-authored preference segment of the Chat Completions
  /// user message. Security and output constraints are fixed in system.
  static String validateLlmUserPrompt(String value) {
    final trimmed = value.trim();
    if (trimmed.length > 2000 ||
        RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]').hasMatch(trimmed)) {
      throw const FormatException('用户提示词不得超过 2000 字，且不能包含控制字符');
    }
    return trimmed.isEmpty ? defaultLlmUserPrompt : trimmed;
  }

  static String validateLlmSystemPrompt(String value) {
    final trimmed = value.trim();
    if (trimmed.length > 2000 ||
        RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]').hasMatch(trimmed)) {
      throw const FormatException('System 提示词不得超过 2000 字，且不能包含控制字符');
    }
    return trimmed.isEmpty ? defaultLlmSystemPrompt : trimmed;
  }

  Future<void> setLlmUserPrompt(String value) =>
      setLlmPrompts(system: llmSystemPrompt, user: value);

  Future<void> setLlmPrompts({
    required String system,
    required String user,
  }) async {
    final nextSystem = validateLlmSystemPrompt(system);
    final nextUser = validateLlmUserPrompt(user);
    if (nextSystem == llmSystemPrompt && nextUser == llmUserPrompt) return;
    final revision = llmRevision + 1;
    await db.db.transaction((tx) async {
      for (final entry in {
        'api_llm_system_prompt': nextSystem,
        'api_llm_user_prompt': nextUser,
        'api_llm_revision': revision.toString(),
      }.entries) {
        await tx.rawInsert(
          'INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)',
          [entry.key, entry.value],
        );
      }
    });
    llmSystemPrompt = nextSystem;
    llmUserPrompt = nextUser;
    llmRevision = revision;
    notifyListeners();
  }

  /// Called after a secret change; the secret itself is kept only in AuthVault.
  Future<void> llmCredentialChanged() => _updateLlmRevision();

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
    try {
      llmUrl = validateLlmUrl(await db.setting('api_llm_url') ?? '');
    } on FormatException {
      llmUrl = defaultLlmUrl;
    }
    try {
      llmModel = validateLlmModel(
        await db.setting('api_llm_model') ?? defaultLlmModel,
      );
    } on FormatException {
      llmModel = defaultLlmModel;
    }
    final storedMode = await db.setting('api_llm_mode');
    llmMode = storedMode == 'lead' ? 'lead' : 'assist';
    llmEnabled = await db.setting('api_llm_enabled') == 'true';
    llmRevision = int.tryParse(await db.setting('api_llm_revision') ?? '') ?? 0;
    try {
      llmSystemPrompt = validateLlmSystemPrompt(
        await db.setting('api_llm_system_prompt') ?? defaultLlmSystemPrompt,
      );
    } on FormatException {
      llmSystemPrompt = defaultLlmSystemPrompt;
    }
    try {
      llmUserPrompt = validateLlmUserPrompt(
        await db.setting('api_llm_user_prompt') ?? defaultLlmUserPrompt,
      );
    } on FormatException {
      llmUserPrompt = defaultLlmUserPrompt;
    }
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
