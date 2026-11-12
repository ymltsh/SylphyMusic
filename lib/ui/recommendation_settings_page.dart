import 'package:flutter/material.dart';

import '../core/app_controller.dart';

class RecommendationSettingsPage extends StatefulWidget {
  const RecommendationSettingsPage({super.key, required this.app});
  final SylphyApp app;

  @override
  State<RecommendationSettingsPage> createState() =>
      _RecommendationSettingsPageState();
}

class _RecommendationSettingsPageState
    extends State<RecommendationSettingsPage> {
  late Future<bool> _charts = widget.app.recommendations.onlineChartsEnabled;
  late Future<int> _refreshCount = widget.app.recommendations
      .dailyRefreshCount();
  bool _busy = false;

  Future<void> _changeRefreshCount(int count) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.app.recommendations.setDailyRefreshCount(count);
      if (mounted) setState(() => _refreshCount = Future.value(count));
      // Signal the home page to re-evaluate the current period.
      await widget.app.reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存自动刷新次数失败')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _update(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await widget.app.recommendations.daily(regenerate: true);
      await widget.app.recommendations.albums(regenerate: true);
      await widget.app.reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('操作未完成，请稍后重试')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _charts = widget.app.recommendations.onlineChartsEnabled;
          _busy = false;
        });
      }
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除推荐统计？'),
        content: const Text('将清除收听统计和推荐快照，并重新生成精选。此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _update(widget.app.listeningAnalytics.clearStats);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('推荐设置')),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('个性化推荐'),
                      subtitle: const Text('根据收藏和收听习惯生成精选，关闭后停止新增收听统计'),
                      value: widget.app.listeningAnalytics.enabled,
                      onChanged: _busy
                          ? null
                          : (value) => _update(
                              () => widget.app.listeningAnalytics.setEnabled(
                                value,
                              ),
                            ),
                    ),
                    FutureBuilder<bool>(
                      future: _charts,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return ListTile(
                            title: const Text('在线热度设置读取失败'),
                            trailing: TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      _charts = widget
                                          .app
                                          .recommendations
                                          .onlineChartsEnabled;
                                    }),
                              child: const Text('重试'),
                            ),
                          );
                        }
                        return SwitchListTile(
                          title: const Text('在线热度'),
                          subtitle: const Text('获取公开榜单辅助推荐，不上传个人曲库或收听记录'),
                          value: snapshot.data ?? false,
                          onChanged: _busy || !snapshot.hasData
                              ? null
                              : (value) => _update(
                                  () => widget.app.recommendations
                                      .setOnlineChartsEnabled(value),
                                ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    FutureBuilder<int>(
                      future: _refreshCount,
                      builder: (context, snapshot) => ListTile(
                        leading: const Icon(Icons.schedule_rounded),
                        title: const Text('每日自动换新次数'),
                        subtitle: const Text(
                          '按本地时间均分每天；进入或返回应用时每个时段最多自动生成一轮，错过不补',
                        ),
                        trailing: DropdownButton<int>(
                          value: snapshot.data ?? 3,
                          items: [
                            for (final count in [1, 2, 3, 4, 6])
                              DropdownMenuItem(
                                value: count,
                                child: Text('$count 次'),
                              ),
                          ],
                          onChanged: _busy || !snapshot.hasData
                              ? null
                              : (value) {
                                  if (value != null) _changeRefreshCount(value);
                                },
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: const Text('清除推荐统计'),
                      subtitle: const Text('清除累计收听统计和推荐快照'),
                      enabled: !_busy,
                      onTap: _clear,
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('个性化与在线热度变更会重新生成精选；自动换新次数只影响每日精选，不影响专辑，也不补发错过的时段。'),
              ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    ),
  );
}
