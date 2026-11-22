import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../services/recommendation_service.dart';
import 'llm_recommendation_settings.dart';
import 'recommendation_letters_page.dart';
import 'settings_controls.dart';
import 'design_system/adaptive_collapsing_chrome.dart';

class RecommendationSettingsPage extends StatefulWidget {
  const RecommendationSettingsPage({super.key, required this.app});
  final SylphyApp app;

  @override
  State<RecommendationSettingsPage> createState() =>
      _RecommendationSettingsPageState();
}

class _RecommendationSettingsPageState
    extends State<RecommendationSettingsPage> {
  SylphyApp get app => widget.app;
  late Future<bool> _charts = app.recommendations.onlineChartsEnabled;
  late Future<int> _refreshCount = app.recommendations.dailyRefreshCount();
  bool _busy = false;
  bool _needsRefresh = false;
  bool _llmBusy = false;
  bool get _locked => _busy || _llmBusy;
  String _activity = '';

  void _notice(String message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save(
    Future<void> Function() action, {
    bool affectsSelection = true,
  }) async {
    if (_locked) return;
    setState(() {
      _busy = true;
      _activity = '正在保存设置';
    });
    try {
      await action();
      if (mounted)
        setState(() {
          _charts = app.recommendations.onlineChartsEnabled;
          _refreshCount = app.recommendations.dailyRefreshCount();
          _needsRefresh = _needsRefresh || affectsSelection;
        });
    } catch (_) {
      _notice('保存失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    if (_locked) return;
    setState(() {
      _busy = true;
      _activity = '正在更新每日精选和专辑推荐';
    });
    try {
      await app.recommendations.daily(regenerate: true);
      await app.recommendations.albums(regenerate: true);
      await app.reload();
      if (mounted) setState(() => _needsRefresh = false);
      _notice('推荐已更新');
    } catch (_) {
      _notice('更新未完成，已保存的设置仍然有效，可稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除推荐统计？'),
        content: const Text(
          '将删除累计收听统计和推荐快照。收藏、歌单、笔友记忆及已存来信保留。清除后下次换新会重新生成推荐，此操作无法撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除统计'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _save(app.listeningAnalytics.clearStats);
  }

  Widget _refreshSchedule() => FutureBuilder<int>(
    future: _refreshCount,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return ListTile(
          title: const Text('换新频率读取失败'),
          trailing: TextButton(
            onPressed: _locked
                ? null
                : () => setState(() {
                    _refreshCount = app.recommendations.dailyRefreshCount();
                  }),
            child: const Text('重试'),
          ),
        );
      final count = snapshot.data;
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('每日自动换新'),
            const SizedBox(height: 6),
            const Text('每日精选按本地时间分段，打开或返回应用时更新；错过的时段不补发。'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in RecommendationService.allowedRefreshCounts)
                  ChoiceChip(
                    label: Text('$value 次'),
                    selected: count == value,
                    onSelected: _locked || count == null
                        ? null
                        : (selected) {
                            if (selected && value != count)
                              _save(
                                () => app.recommendations.setDailyRefreshCount(
                                  value,
                                ),
                                affectsSelection: false,
                              );
                          },
                  ),
              ],
            ),
            if (count != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('每 ${24 ~/ count} 小时一个时段 · 仅影响每日精选'),
              ),
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: sylphyGradientAppBar(
      leading: settingsBackButton(context),
      title: const Text('推荐与音乐笔友'),
      bottom: _busy
          ? const PreferredSize(
              preferredSize: Size.fromHeight(4),
              child: LinearProgressIndicator(),
            )
          : null,
    ),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              SettingsGroup(
                title: '基础推荐',
                children: [
                  SwitchListTile(
                    secondary: const SettingsIcon(
                      Icons.favorite_border_rounded,
                    ),
                    title: const Text('根据我的喜好选曲'),
                    subtitle: const Text('参考收藏和收听习惯；关闭后随机探索，并停止新增收听统计。'),
                    value: app.listeningAnalytics.enabled,
                    onChanged: _locked
                        ? null
                        : (value) => _save(
                            () => app.listeningAnalytics.setEnabled(value),
                          ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  FutureBuilder<bool>(
                    future: _charts,
                    builder: (context, snapshot) {
                      if (snapshot.hasError)
                        return ListTile(
                          title: const Text('在线热度设置读取失败'),
                          trailing: TextButton(
                            onPressed: _locked
                                ? null
                                : () => setState(() {
                                    _charts =
                                        app.recommendations.onlineChartsEnabled;
                                  }),
                            child: const Text('重试'),
                          ),
                        );
                      return SwitchListTile(
                        secondary: const SettingsIcon(
                          Icons.trending_up_rounded,
                        ),
                        title: const Text('参考公开热度'),
                        subtitle: const Text('联网获取公开榜单辅助选曲，不上传个人曲库或收听记录。'),
                        value: snapshot.data ?? false,
                        onChanged: _locked || !snapshot.hasData
                            ? null
                            : (value) => _save(
                                () => app.recommendations
                                    .setOnlineChartsEnabled(value),
                              ),
                      );
                    },
                  ),
                ],
              ),
              SettingsGroup(
                title: '每日换新',
                children: [
                  _refreshSchedule(),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('更新每日精选和专辑推荐。开启模型增强时可能产生费用。'),
                        if (_needsRefresh)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('已保存选曲偏好，将在下次换新时生效。'),
                          ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _locked ? null : _refresh,
                          icon: const SettingsIcon(Icons.refresh_rounded),
                          label: Text(_busy ? _activity : '立即更新推荐'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              LlmRecommendationSettings(
                app: app,
                disabled: _busy,
                onBusyChanged: (value) {
                  if (mounted) setState(() => _llmBusy = value);
                },
              ),
              SettingsGroup(
                title: '推荐数据',
                children: [
                  ListTile(
                    key: const ValueKey('recommendation-letters-archive'),
                    leading: const SettingsIcon(
                      Icons.markunread_mailbox_outlined,
                    ),
                    title: const Text('每日推荐文案'),
                    subtitle: const Text('回看已存档的推荐信件和逐曲理由'),
                    trailing: const SettingsIcon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => RecommendationLettersPage(app: app),
                      ),
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const SettingsIcon(Icons.delete_outline),
                    title: const Text('清除推荐统计'),
                    subtitle: const Text('删除收听统计和推荐快照，保留收藏、歌单与笔友内容'),
                    trailing: const SettingsIcon(Icons.chevron_right),
                    onTap: _locked ? null : _clear,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
