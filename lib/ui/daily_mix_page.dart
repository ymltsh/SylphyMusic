import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/recommendation_models.dart';
import 'playing_song_tile.dart';

/// A dated, independent queue snapshot: regeneration never edits a playing queue.
class DailyMixPage extends StatefulWidget {
  const DailyMixPage({super.key, required this.app});
  final SylphyApp app;

  @override
  State<DailyMixPage> createState() => _DailyMixPageState();
}

class _DailyMixPageState extends State<DailyMixPage> {
  late Future<DailyMix> _mix = widget.app.recommendations.daily();
  bool _working = false;

  Future<void> _play(DailyMix mix, {int start = 0}) async {
    if (mix.items.isEmpty) return;
    try {
      await widget.app.playback.setQueue(mix.refs, start: start);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂时无法播放，请检查音乐来源')));
      }
    }
  }

  Future<void> _action(String action, DailyMix mix) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      if (action == 'refresh') {
        final next = await widget.app.recommendations.daily(regenerate: true);
        if (mounted) setState(() => _mix = Future.value(next));
      } else if (action == 'save') {
        await widget.app.cloud.newLocal(
          '每日精选 · ${mix.day}',
          keys: mix.refs.map((ref) => ref.key).toList(),
        );
        await widget.app.reload();
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('已保存为本地歌单')));
        }
      } else if (action == 'personal') {
        final enabled = widget.app.listeningAnalytics.enabled;
        await widget.app.listeningAnalytics.setEnabled(!enabled);
        if (mounted) {
          setState(
            () => _mix = widget.app.recommendations.daily(regenerate: true),
          );
        }
      } else if (action == 'clear') {
        await widget.app.listeningAnalytics.clearStats();
        if (mounted) {
          setState(
            () => _mix = widget.app.recommendations.daily(regenerate: true),
          );
        }
      } else if (action == 'charts') {
        final old = await widget.app.recommendations.onlineChartsEnabled;
        await widget.app.recommendations.setOnlineChartsEnabled(!old);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                old ? '已关闭在线热度；下次生成将使用本地数据' : '已开启在线热度；下次生成将尝试获取公开榜单',
              ),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('操作未完成，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('每日精选')),
    body: FutureBuilder<DailyMix>(
      future: _mix,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('生成精选失败，请稍后重试'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final mix = snapshot.data!;
        if (mix.items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('音乐库暂无可以推荐的歌曲，先添加来源或导入音乐吧。'),
            ),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mix.day,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          '${mix.items.length} 首 · 属于你的音乐',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _working ? null : () => unawaited(_play(mix)),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('播放全部'),
                  ),
                  PopupMenuButton<String>(
                    enabled: !_working,
                    tooltip: '精选操作',
                    onSelected: (action) => unawaited(_action(action, mix)),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'refresh', child: Text('换一批')),
                      PopupMenuItem(value: 'save', child: Text('保存为本地歌单')),
                      PopupMenuItem(value: 'charts', child: Text('切换在线热度开关')),
                      PopupMenuItem(value: 'personal', child: Text('切换个性化推荐')),
                      PopupMenuItem(
                        value: 'clear',
                        child: Text('清除推荐统计（不可撤销）'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: mix.items.length,
                itemBuilder: (context, index) {
                  final item = mix.items[index];
                  return PlayingSongTile(
                    app: widget.app,
                    track: item.track,
                    title: item.track.title,
                    subtitle: '${item.track.artist} · ${item.reason}',
                    onTap: () => unawaited(_play(mix, start: index)),
                    trailing: PopupMenuButton<String>(
                      tooltip: '推荐反馈',
                      onSelected: (value) async {
                        if (value != 'hide') return;
                        await widget.app.recommendations.hide(item.track.ref);
                        if (mounted) {
                          setState(
                            () => _mix = widget.app.recommendations.daily(),
                          );
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'hide', child: Text('不再推荐这首')),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    ),
  );
}
