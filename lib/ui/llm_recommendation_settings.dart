import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import 'penpal_cards_page.dart';
import 'penpal_memory_page.dart';
import 'recommendation_settings_section.dart';
import 'settings_page.dart';

class LlmRecommendationSettings extends StatefulWidget {
  const LlmRecommendationSettings({
    super.key,
    required this.app,
    this.disabled = false,
    this.onBusyChanged,
  });
  final SylphyApp app;
  final bool disabled;
  final ValueChanged<bool>? onBusyChanged;

  @override
  State<LlmRecommendationSettings> createState() =>
      _LlmRecommendationSettingsState();
}

class _LlmRecommendationSettingsState extends State<LlmRecommendationSettings> {
  SylphyApp get app => widget.app;
  bool _saving = false;
  bool get _locked => _saving || widget.disabled;

  Future<void> _act(Future<void> Function() action) async {
    if (_locked) return;
    setState(() => _saving = true);
    widget.onBusyChanged?.call(true);
    try {
      await action();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存推荐设置失败，请稍后重试')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  Future<void> _toggle(bool value) => _act(() async {
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('开启 LLM 增强推荐？'),
          content: const Text(
            '候选歌曲的名称、歌手、专辑及有限的听歌统计会发送到你配置的模型服务。开启记忆时还可能发送精简的角色记忆与已保存观点；聊天会发送输入内容。不会发送音源地址、账号或音频文件。第三方接口可能收费。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('开启增强'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    await app.apiSettings.setLlmEnabled(value);
  });

  Widget _mode(String value, String title, String detail, IconData icon) {
    final selected = app.apiSettings.llmMode == value;
    final enabled = app.apiSettings.llmEnabled && !_locked;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.secondaryContainer : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled
            ? () {
                if (!selected) _act(() => app.apiSettings.setLlmMode(value));
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 20,
                    color: enabled ? colors.primary : colors.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(detail, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([app.apiSettings, app.apiSettings.cards]),
    builder: (context, _) {
      final enabled = app.apiSettings.llmEnabled;
      return RecommendationSettingsSection(
        icon: Icons.auto_awesome_outlined,
        title: 'LLM 增强',
        description: '让模型参与选曲、专辑排序和来信，延续音乐笔友的个性。',
        status: enabled ? '已开启' : '未开启',
        children: [
          SwitchListTile(
            key: const ValueKey('recommendation-llm-enabled'),
            title: const Text('启用增强推荐'),
            subtitle: Text(
              enabled ? '当前由模型参与推荐；请求失败时使用基础推荐。' : '可先配置模型和笔友，开启后参与推荐。',
            ),
            value: enabled,
            onChanged: _locked ? null : _toggle,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: const Text('模型连接'),
            subtitle: Text(
              '${app.apiSettings.llmModel} · 接口、密钥与连接测试',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _locked
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsPage.llmConnection(app: app),
                    ),
                  ),
          ),
          Padding(
            key: const ValueKey('recommendation-llm-mode'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('参与方式', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (!enabled)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text('开启增强后可切换参与方式；已选设置会保留。'),
                  ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final assist = _mode(
                      'assist',
                      '辅助选曲',
                      '在基础推荐的候选中重排，并撰写推荐词。',
                      Icons.tune_rounded,
                    );
                    final lead = _mode(
                      'lead',
                      '主导选曲',
                      '从更大的曲库候选中挑选，再组织推荐和来信。',
                      Icons.explore_outlined,
                    );
                    return constraints.maxWidth < 480
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              assist,
                              const SizedBox(height: 10),
                              lead,
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: assist),
                              const SizedBox(width: 10),
                              Expanded(child: lead),
                            ],
                          );
                  },
                ),
              ],
            ),
          ),
          ListTile(
            key: const ValueKey('recommendation-llm-timeout'),
            leading: const Icon(Icons.timer_outlined),
            title: const Text('等待时间'),
            subtitle: const Text('选曲与写信共用；模型较慢时可适当增加'),
            enabled: enabled && !_locked,
            trailing: DropdownButton<int>(
              value: app.apiSettings.llmTimeoutSeconds,
              underline: const SizedBox.shrink(),
              items: [
                for (final seconds in [60, 90, 120])
                  DropdownMenuItem(value: seconds, child: Text('$seconds 秒')),
              ],
              onChanged: !enabled || _locked
                  ? null
                  : (value) {
                      if (value != null)
                        _act(() => app.apiSettings.setLlmTimeoutSeconds(value));
                    },
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            key: const ValueKey('recommendation-llm-user-prompt'),
            leading: const Icon(Icons.badge_outlined),
            title: const Text('音乐笔友与角色卡'),
            subtitle: Text('当前：${app.apiSettings.cards.activeName} · 管理角色与提示词'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _locked
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PenpalCardsPage(app: app),
                    ),
                  ),
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('记忆与相处'),
            subtitle: const Text('管理当前角色的记忆、补充设定与隐私'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _locked
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PenpalMemoryPage(app: app),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              '模型配置变更后，首页会按新设置更新推荐。关闭增强会保留连接、角色和记忆。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (_saving) const LinearProgressIndicator(),
        ],
      );
    },
  );
}
