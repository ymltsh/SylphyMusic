import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/recommendation_models.dart';
import 'recommendation_letters_page.dart';
import 'playing_song_tile.dart';
import 'recommendation_showcase.dart';
import 'recommendation_delivery.dart';
import 'penpal_chat_page.dart';
import 'route_player_bar.dart';

/// A dated, independent queue snapshot: regeneration never edits a playing queue.
class DailyMixPage extends StatefulWidget {
  const DailyMixPage({super.key, required this.app});
  final SylphyApp app;

  @override
  State<DailyMixPage> createState() => _DailyMixPageState();
}

class _DailyMixPageState extends State<DailyMixPage>
    with WidgetsBindingObserver {
  late Future<DailyMix> _mix = widget.app.recommendations.daily();
  bool _working = false;
  final Set<String> _openedLetters = {};
  int _llmRevision = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _llmRevision = widget.app.apiSettings.llmRevision;
    widget.app.apiSettings.addListener(_settingsChanged);
  }

  void _settingsChanged() {
    final updated = widget.app.apiSettings.llmRevision;
    if (!mounted || _llmRevision == updated) return;
    _llmRevision = updated;
    setState(() => _mix = widget.app.recommendations.daily());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => _mix = widget.app.recommendations.daily());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.app.apiSettings.removeListener(_settingsChanged);
    super.dispose();
  }

  Future<void> _reply(DailyMix mix) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => PenpalChatPage(
        app: widget.app,
        letterKey: '${mix.day}:${mix.generation}',
        letterTitle: mix.title,
        letterContext:
            '${mix.title}\n${mix.introduction}\n'
            '${mix.items.map((item) => '${item.track.title} · ${item.track.artist}：${item.reason}').join('\n')}',
      ),
    ),
  );

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
      if (action == 'chat') {
        await _reply(mix);
      } else if (action == 'refresh') {
        final pending = widget.app.recommendations.daily(regenerate: true);
        setState(() => _mix = pending);
        await pending;
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
    appBar: AppBar(
      title: const Text('每日精选'),
      actions: [
        IconButton(
          icon: const Icon(Icons.markunread_mailbox_outlined),
          tooltip: '每日推荐文案',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RecommendationLettersPage(app: widget.app),
            ),
          ),
        ),
      ],
    ),
    floatingActionButton: RoutePlayerFab(app: widget.app),
    body: RecommendationDeliveryBuilder(
      future: _mix,
      service: widget.app.recommendations,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('生成精选失败，请稍后重试'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final mix = snapshot.data!;
        if (mix.items.isNotEmpty &&
            _openedLetters.add('${mix.day}:${mix.generation}')) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              unawaited(
                widget.app.penpalMemory
                    .recordOpenedDailyMix(mix)
                    .catchError((Object _) {}),
              );
            }
          });
        }
        if (mix.items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('音乐库暂无可以推荐的歌曲，先添加来源或导入音乐吧。'),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 116),
          itemCount: mix.items.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                child: RecommendationShowcase(
                  app: widget.app,
                  mix: mix,
                  detailed: true,
                  footerActions: [
                    FilledButton.icon(
                      onPressed: _working ? null : () => unawaited(_play(mix)),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('播放全部'),
                    ),
                  ],
                  footerTrailingAction: PopupMenuButton<String>(
                    enabled: !_working,
                    tooltip: '更多',
                    onSelected: (action) => unawaited(_action(action, mix)),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'chat', child: Text('与笔友聊天')),
                      PopupMenuItem(value: 'refresh', child: Text('换一批')),
                      PopupMenuItem(value: 'save', child: Text('保存为本地歌单')),
                    ],
                  ),
                ),
              );
            }
            final trackIndex = index - 1;
            final item = mix.items[trackIndex];
            return PlayingSongTile(
              app: widget.app,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              track: item.track,
              title: item.track.title,
              subtitle: '${item.track.artist} · ${item.reason}',
              onTap: () => unawaited(_play(mix, start: trackIndex)),
              trailing: PopupMenuButton<String>(
                tooltip: '推荐反馈',
                onSelected: (value) async {
                  if (value != 'hide') return;
                  await widget.app.recommendations.hide(item.track.ref);
                  if (mounted) {
                    setState(() => _mix = widget.app.recommendations.daily());
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'hide', child: Text('不再推荐这首')),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}
