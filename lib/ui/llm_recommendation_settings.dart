import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../services/api_settings.dart';

/// Recommendation behavior shares persisted settings with the connection page.
class LlmRecommendationSettings extends StatefulWidget {
  const LlmRecommendationSettings({super.key, required this.app});
  final SylphyApp app;
  @override
  State<LlmRecommendationSettings> createState() =>
      _LlmRecommendationSettingsState();
}

class _LlmRecommendationSettingsState extends State<LlmRecommendationSettings> {
  SylphyApp get app => widget.app;
  bool _saving = false;

  Future<void> _act(Future<void> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存推荐设置失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirm(String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('开启 LLM 增强推荐？'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('开启'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _editLlmMode() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('LLM 推荐参与方式'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'assist'),
            child: const Text('辅助推荐 · 重排现有精选并撰写推荐词'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'lead'),
            child: const Text('主导推荐 · 从扩展候选中选择并撰写推荐词'),
          ),
        ],
      ),
    );
    if (value != null && mounted) {
      await _act(() => app.apiSettings.setLlmMode(value));
    }
  }

  Future<void> _editLlmPrompts() async {
    final value = await showDialog<({String system, String user})>(
      context: context,
      builder: (_) => _LlmPromptDialog(
        system: app.apiSettings.llmSystemPrompt,
        user: app.apiSettings.llmUserPrompt,
      ),
    );
    if (value == null || !mounted) return;
    await _act(
      () =>
          app.apiSettings.setLlmPrompts(system: value.system, user: value.user),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app.apiSettings,
    builder: (context, _) => Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'LLM 推荐',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('接口地址、模型和密钥在 API 设置中配置。'),
          ),
          IgnorePointer(
            ignoring: _saving,
            child: Column(
              children: [
                SwitchListTile(
                  key: const ValueKey('recommendation-llm-enabled'),
                  secondary: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('LLM 增强推荐'),
                  subtitle: const Text('可选：AI 参与每日精选和专辑排序，并生成推荐词'),
                  value: app.apiSettings.llmEnabled,
                  onChanged: (value) => _act(() async {
                    if (value &&
                        !await _confirm(
                          '开启后，候选歌曲名称、歌手、专辑及有限的本机听歌统计会发送给你配置的 LLM 服务。聊天时会发送你输入的内容，已选择记住的观点也可能用于后续推荐。不会发送音乐源地址、账号或音频文件；第三方接口可能收费。是否开启？',
                        ))
                      return;
                    await app.apiSettings.setLlmEnabled(value);
                  }),
                ),
                ListTile(
                  key: const ValueKey('recommendation-llm-mode'),
                  leading: const Icon(Icons.tune_outlined),
                  title: const Text('LLM 推荐参与方式'),
                  subtitle: Text(
                    app.apiSettings.llmMode == 'lead'
                        ? '主导：在扩展候选中选歌、重排和撰写推荐词'
                        : '辅助：保留本地候选，LLM 重排并撰写推荐词',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _editLlmMode,
                ),
                ListTile(
                  key: const ValueKey('recommendation-llm-timeout'),
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('LLM 总等待预算'),
                  subtitle: const Text('先选曲、再写信；网络或模型慢时可增加等待时间'),
                  trailing: DropdownButton<int>(
                    value: app.apiSettings.llmTimeoutSeconds,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final seconds in [60, 90, 120])
                        DropdownMenuItem(
                          value: seconds,
                          child: Text('$seconds 秒'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _act(() => app.apiSettings.setLlmTimeoutSeconds(value));
                      }
                    },
                  ),
                ),
                ListTile(
                  key: const ValueKey('recommendation-llm-user-prompt'),
                  leading: const Icon(Icons.edit_note_rounded),
                  title: const Text('自定义 Prompt'),
                  subtitle: Text(
                    app.apiSettings.llmUserPrompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _editLlmPrompts,
                ),
              ],
            ),
          ),
          if (_saving) const LinearProgressIndicator(),
        ],
      ),
    ),
  );
}

class _LlmPromptDialog extends StatefulWidget {
  const _LlmPromptDialog({required this.system, required this.user});
  final String system;
  final String user;

  @override
  State<_LlmPromptDialog> createState() => _LlmPromptDialogState();
}

class _LlmPromptDialogState extends State<_LlmPromptDialog> {
  late final system = TextEditingController(text: widget.system);
  late final user = TextEditingController(text: widget.user);
  String? error;

  @override
  void dispose() {
    system.dispose();
    user.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final value = (
        system: ApiSettings.validateLlmSystemPrompt(system.text),
        user: ApiSettings.validateLlmUserPrompt(user.text),
      );
      Navigator.pop(context, value);
    } on FormatException catch (exception) {
      setState(() => error = exception.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('自定义 Prompt'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('可调整推荐角色、选曲侧重和文案风格。真实候选范围、禁止编造和 JSON 输出格式由应用固定。'),
            const SizedBox(height: 16),
            TextField(
              controller: system,
              minLines: 4,
              maxLines: 7,
              maxLength: ApiSettings.maxLlmSystemPromptLength,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'System Prompt（推荐角色与策略）',
                helperText: '作为 System 指导发送，固定约束仍会追加；留空恢复默认。',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: user,
              minLines: 4,
              maxLines: 7,
              maxLength: 2000,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'User Prompt（个人偏好）',
                hintText: '例如：偏好华语独立音乐；文案带一点诗意。',
                helperText: '随候选数据发送；留空恢复默认。请勿填写密钥。',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text('保存后会重新生成推荐，可能产生 API 费用。'),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          system.text = ApiSettings.defaultLlmSystemPrompt;
          user.text = ApiSettings.defaultLlmUserPrompt;
          setState(() => error = null);
        },
        child: const Text('恢复默认'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存')),
    ],
  );
}
