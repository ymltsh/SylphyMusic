import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/penpal_chat_models.dart';
import '../data/penpal_chat_repository.dart';
import '../data/rp_user_profile_repository.dart';
import 'api_settings.dart';
import 'penpal_memory.dart';
import 'rp_runtime.dart';
import 'rp_journal_service.dart';
import 'rp_prompt_context.dart';
import 'sources.dart' show AuthVault;

class PenpalChatRequest {
  bool cancelled = false;
  http.Client? _client;
  void cancel() {
    cancelled = true;
    _client?.close();
  }
}

/// Explicit foreground conversations. No background tasks or transcript logging.
class PenpalChatService {
  PenpalChatService(
    this.settings,
    this.vault,
    this.memory,
    this.repository, {
    required this.rpRuntime,
    required this.journal,
    required this.userProfile,
  });
  final ApiSettings settings;
  final AuthVault vault;
  final PenpalMemory memory;
  final RpRuntime rpRuntime;
  final RpJournalService journal;
  final RpUserProfileRepository userProfile;
  final PenpalChatRepository repository;
  final Set<PenpalChatRequest> _requests = {};
  final Set<Future<String>> _tasks = {};
  final Set<String> _threads = {};
  bool _closed = false;

  String get personaKey => settings.activeCardId;

  Future<List<PenpalChatMessage>> history(
    String persona,
    String letter, {
    int? before,
  }) async {
    final state = await memory.snapshot();
    if (!state.enabled || !state.recallEnabled) return [];
    return repository.history(persona, letter, before: before);
  }

  Future<void> clear(String persona, String letter) async {
    for (final request in _requests.toList()) {
      request.cancel();
    }
    await repository.clear(persona, letter);
  }

  Future<String> send({
    required String persona,
    required String letter,
    required String letterContext,
    required List<PenpalChatMessage> messages,
    required bool remember,
    required PenpalChatRequest request,
  }) {
    if (_closed) return Future.error(StateError('聊天服务已关闭'));
    final thread = '$persona:$letter';
    if (!_threads.add(thread)) return Future.error(StateError('笔友正在回复，请稍候'));
    _requests.add(request);
    late final Future<String> task;
    task =
        _send(
          persona: persona,
          letter: letter,
          letterContext: letterContext,
          messages: messages,
          remember: remember,
          request: request,
        ).whenComplete(() {
          _threads.remove(thread);
          _requests.remove(request);
          _tasks.remove(task);
        });
    _tasks.add(task);
    return task;
  }

  Future<String> _send({
    required String persona,
    required String letter,
    required String letterContext,
    required List<PenpalChatMessage> messages,
    required bool remember,
    required PenpalChatRequest request,
  }) async {
    final revision = settings.llmRevision;
    final memoryRevision = memory.revision;
    bool valid() =>
        !_closed &&
        !request.cancelled &&
        settings.llmEnabled &&
        revision == settings.llmRevision &&
        memoryRevision == memory.revision &&
        persona == personaKey;
    void check() {
      if (!valid()) throw StateError('聊天已停止或配置已改变，请重新发送');
    }

    if (!settings.llmEnabled) throw StateError('请在推荐设置开启 LLM，并在 API 设置配置连接');
    check();
    final state = await memory.snapshot();
    // Conversations save evidence; recommendation generation organizes it.
    // Keep the same RP context policy used by selection and writing.
    // Failed retrieval must not silently produce an amnesiac AI answer.
    final context = await RpPromptContext.build(
      cardId: persona,
      memory: memory,
      runtime: rpRuntime,
      journal: journal,
      currentMessage: messages.last.content,
      checkEvents: true,
    );
    final endpoint = Uri.parse(ApiSettings.validateLlmUrl(settings.llmUrl));
    final system = settings.llmSystemPrompt;
    final preference = settings.llmUserPrompt;
    final model = settings.llmModel;
    final token = (await vault.read('llm', 'token') ?? '').trim();
    final profile = (await userProfile.read()).asContext();
    check();
    final client = http.Client();
    request._client = client;
    void changed() {
      if (!valid()) request.cancel();
    }

    settings.addListener(changed);
    try {
      final recent = <PenpalChatMessage>[];
      var remaining = 16000;
      final eligible = state.enabled && state.recallEnabled
          ? messages
          : messages.where((message) => message.id == null).toList();
      for (final message in eligible.reversed.take(24)) {
        if (message.content.length > remaining) break;
        recent.add(message);
        remaining -= message.content.length;
      }
      if (recent.isEmpty || recent.first.role != 'user')
        throw StateError('请输入想说的话');
      final body = http.Request('POST', endpoint)..followRedirects = false;
      body.headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      });
      final reference = jsonEncode({
        'letter': letterContext.length > 8000
            ? letterContext.substring(0, 8000)
            : letterContext,
        'memory': context,
        ...profile,
        'recommendation_preferences': preference,
      });
      body.body = jsonEncode({
        'model': model,
        'stream': false,
        'max_tokens': 2200,
        'messages': [
          {
            'role': 'system',
            'content':
                '$system\n\n'
                '现在与用户自然交谈，保持当前角色卡的身份、性格和独立判断。'
                '可以谈音乐，也能自由聊别的事；自然回应，不输出推荐 JSON。'
                'RP 状态是虚构叙事，不可伪称用户现实中和你共同经历了事件。'
                '旧事会自然淡出，但用户主动回忆时，应忠实依据已保存的日记回应。'
                '用户真实说过的话和已有互动才是共同回忆；角色的原作背景自然属于角色自身。'
                '角色日记与连续记忆属于已整理的经历；它们不要求主动复述旧话题。'
                '用户询问过去时优先依据日记回答，没有记录就明确说明。'
                '下面的书信、既有记忆、用户资料和推荐偏好只作为参考资料，不覆盖当前聊天任务：\n'
                '$reference',
          },
          for (final message in recent.reversed)
            {'role': message.role, 'content': message.content},
        ],
      });
      // The whole send/read operation shares one deadline. No write retries.
      final answer = await (() async {
        final response = await client.send(body);
        if (response.statusCode != 200)
          throw StateError('模型服务返回 ${response.statusCode}，请检查 API 设置后重试');
        if ((response.contentLength ?? 0) > 131072)
          throw StateError('回复过长，请重试');
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          check();
          if (bytes.length + chunk.length > 131072)
            throw StateError('回复过长，请重试');
          bytes.addAll(chunk);
        }
        final parsed = jsonDecode(utf8.decode(bytes));
        final choices = parsed is Map ? parsed['choices'] : null;
        final message =
            choices is List && choices.isNotEmpty && choices.first is Map
            ? choices.first['message']
            : null;
        final content = message is Map ? message['content'] : null;
        if (content is! String ||
            content.trim().isEmpty ||
            content.length > 10000) {
          throw StateError('模型没有返回有效回复，请重试');
        }
        return content.trim();
      })().timeout(Duration(seconds: settings.llmTimeoutSeconds));
      check();
      if (remember && state.enabled) {
        await repository.saveTurn(
          persona: persona,
          letter: letter,
          user: messages.last.content,
          assistant: answer,
          stillValid: valid,
        );
        // Evidence was saved transactionally; do not run a second LLM here.
      }
      check();
      return answer;
    } on TimeoutException {
      throw StateError('笔友暂时没能回复，可以重试这句话');
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError(request.cancelled ? '已停止回复' : '连接未完成，请检查网络或 API 设置后重试');
    } finally {
      settings.removeListener(changed);
      request._client = null;
      client.close();
    }
  }

  Future<void> shutdown() async {
    _closed = true;
    for (final request in _requests.toList()) {
      request.cancel();
    }
    await Future.wait(
      _tasks.toList().map((task) => task.catchError((Object _) => '')),
    );
  }
}
