import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/rp_journal_models.dart';
import 'rp_user_profile_card.dart';
import 'design_system/adaptive_collapsing_chrome.dart';

/// Profile editing and management of the three long-term memory tiers.
class RpJournalPage extends StatefulWidget {
  const RpJournalPage({super.key, required this.app, this.embedded = false});
  final SylphyApp app;
  final bool embedded;

  @override
  State<RpJournalPage> createState() => _RpJournalPageState();
}

class _RpJournalPageState extends State<RpJournalPage> {
  late String _card = widget.app.apiSettings.activeCardId;
  late Future<RpJournalSnapshot> _load = _read();
  bool _busy = false;

  Future<RpJournalSnapshot> _read() => widget.app.rpJournal.snapshot(_card);

  @override
  void initState() {
    super.initState();
    widget.app.apiSettings.addListener(_onCardChanged);
    widget.app.rpJournal.addListener(_onJournalChanged);
  }

  void _onCardChanged() {
    final id = widget.app.apiSettings.activeCardId;
    if (!mounted || id == _card) return;
    setState(() {
      _card = id;
      _load = _read();
    });
  }

  void _onJournalChanged() {
    if (mounted) setState(() => _load = _read());
  }

  @override
  void dispose() {
    widget.app.apiSettings.removeListener(_onCardChanged);
    widget.app.rpJournal.removeListener(_onJournalChanged);
    super.dispose();
  }

  Future<void> _delete(RpJournalEntry entry) async {
    if (_busy) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这份记忆？'),
        content: const Text('这份归纳不会再发送给 LLM；已合并的下级记忆不能自动还原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.app.rpJournal.repository.deleteEntry(_card, entry.id);
      if (mounted) setState(() => _load = _read());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('删除未完成，请稍后再试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tier(
    String title,
    String description,
    String level,
    RpJournalSnapshot state,
  ) {
    final entries = state.ofLevel(level).toList();
    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(description),
            trailing: Text('${entries.length}'),
          ),
          for (final entry in entries)
            ExpansionTile(
              key: ValueKey('${entry.level}:${entry.id}'),
              title: Text(
                entry.startDay == entry.endDay
                    ? entry.startDay
                    : '${entry.startDay} — ${entry.endDay}',
              ),
              subtitle: Text(
                entry.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SelectableText(entry.text),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _busy ? null : () => _delete(entry),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除这份记忆'),
                  ),
                ),
              ],
            ),
          if (entries.isEmpty) const ListTile(subtitle: Text('还没有形成这一层记忆')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.embedded
      ? _content()
      : Scaffold(
          appBar: sylphyGradientAppBar(title: const Text('关于我的音乐笔友')),
          body: _content(),
        );

  Widget _content() => FutureBuilder<RpJournalSnapshot>(
    future: _load,
    builder: (context, snapshot) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        RpUserProfileCard(app: widget.app),
        const SizedBox(height: 12),
        if (snapshot.hasError)
          Center(
            child: TextButton(
              onPressed: () => setState(() => _load = _read()),
              child: const Text('记忆读取失败，点击重试'),
            ),
          )
        else if (!snapshot.hasData)
          const Center(child: CircularProgressIndicator())
        else
          ..._journalCards(snapshot.data!),
      ],
    ),
  );

  List<Widget> _journalCards(RpJournalSnapshot state) {
    final progress = widget.app.rpJournal.progress(_card);
    final stateText = switch (progress.phase) {
      'working' => '正在整理经历与历史记忆…',
      'failed' => '上轮整理未完成，原始互动仍已保存',
      'done' => '本轮完成 ${progress.processed} 次记忆整理',
      _ => '下一轮新推荐前，按实际需要自动整理',
    };
    return [
      const Text('笔友会每天记录与你的点点滴滴~'),
      const SizedBox(height: 12),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.auto_stories_outlined),
              title: const Text('记忆整理状态'),
              subtitle: Text('$stateText\n待整理互动 ${state.pending} 段'),
            ),
            if (progress.phase == 'working') const LinearProgressIndicator(),
          ],
        ),
      ),
      const SizedBox(height: 8),
      _tier('日记', '同一天合并为一篇，保留最近交流的细节', 'day', state),
      const SizedBox(height: 8),
      _tier('周记', '日记经过七天后归纳，保留主要变化', 'week', state),
      const SizedBox(height: 8),
      _tier('月记', '四本周记归纳，保留更加稳定的认知', 'month', state),
      const SizedBox(height: 8),
      Card(
        child: Column(
          children: [
            const ListTile(
              title: Text('尚未整理的记忆'),
              subtitle: Text('记录：'),
            ),
            for (final turn in state.drafts.reversed)
              ExpansionTile(
                title: Text(turn.day),
                subtitle: Text(
                  turn.user.isNotEmpty ? turn.user : turn.assistant,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      turn.user.isEmpty
                          ? turn.assistant
                          : '你：${turn.user}\n\n笔友：${turn.assistant}',
                    ),
                  ),
                ],
              ),
            if (state.drafts.isEmpty)
              const ListTile(subtitle: Text('目前没有待整理的交流')),
          ],
        ),
      ),
    ];
  }
}
