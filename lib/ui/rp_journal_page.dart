import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/rp_journal_models.dart';

/// Read, edit, and delete a character's own journal and continuity.
class RpJournalPage extends StatefulWidget {
  const RpJournalPage({super.key, required this.app});
  final SylphyApp app;

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
  }

  void _onCardChanged() {
    final id = widget.app.apiSettings.activeCardId;
    if (!mounted || id == _card) return;
    setState(() {
      _card = id;
      _load = _read();
    });
  }

  @override
  void dispose() {
    widget.app.apiSettings.removeListener(_onCardChanged);
    super.dispose();
  }

  Future<void> _act(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
      if (mounted) setState(() => _load = _read());
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('操作未完成，请稍后再试')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _editText(String heading, String initial) async {
    final controller = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(heading),
          content: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 8,
            maxLength: 300,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Widget _continuityField(
    String title,
    String value,
    RpContinuity current,
    RpContinuity Function(String) change,
  ) => ListTile(
    title: Text(title),
    subtitle: Text(
      value.isEmpty ? '尚无记录' : value,
      maxLines: 5,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: const Icon(Icons.edit_outlined),
    onTap: _busy
        ? null
        : () async {
            final next = await _editText(title, value);
            if (next == null || !mounted) return;
            await _act(
              () => widget.app.rpJournal.repository.updateContinuity(
                _card,
                change(next),
              ),
            );
          },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('角色日记与连续记忆')),
    body: FutureBuilder<RpJournalSnapshot>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(
            child: TextButton(
              onPressed: () => setState(() => _load = _read()),
              child: const Text('读取失败，点击重试'),
            ),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final state = snapshot.data!;
        final memory = state.continuity;
        RpContinuity revised({
          String? self,
          String? user,
          String? relationship,
          String? open,
          String? avoid,
        }) => RpContinuity(
          self: self ?? memory.self,
          user: user ?? memory.user,
          relationship: relationship ?? memory.relationship,
          openThreads: open ?? memory.openThreads,
          avoidRepetition: avoid ?? memory.avoidRepetition,
          revision: memory.revision,
        );
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '日记保存角色确实经历过的聊天与剧情；连续记忆每次新会话都会提供给角色。'
              '整理需使用你配置的 LLM，失败不会丢失聊天。',
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.auto_stories_outlined),
                    title: const Text('待整理经历'),
                    subtitle: Text('${state.pending} 条'),
                    trailing: FilledButton.tonal(
                      onPressed: _busy
                          ? null
                          : () => _act(
                              () => widget.app.rpJournal.maybeConsolidate(
                                _card,
                                force: true,
                              ),
                            ),
                      child: const Text('现在写日记'),
                    ),
                  ),
                  if (memory.invalidated)
                    const ListTile(
                      title: Text('连续记忆已撤回'),
                      subtitle: Text('有来源对话或日记被删除，等待依据剩余记录重新整理。'),
                    ),
                  if (_busy) const LinearProgressIndicator(),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  const ListTile(
                    title: Text(
                      '连续记忆',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('默认跨会话生效；点击可纠正模型整理的内容'),
                  ),
                  _continuityField(
                    '角色自己的想法',
                    memory.self,
                    memory,
                    (v) => revised(self: v),
                  ),
                  _continuityField(
                    '关于用户（有证据的事实）',
                    memory.user,
                    memory,
                    (v) => revised(user: v),
                  ),
                  _continuityField(
                    '共同经历与关系',
                    memory.relationship,
                    memory,
                    (v) => revised(relationship: v),
                  ),
                  _continuityField(
                    '未完成的约定',
                    memory.openThreads,
                    memory,
                    (v) => revised(open: v),
                  ),
                  _continuityField(
                    '暂时不主动重提',
                    memory.avoidRepetition,
                    memory,
                    (v) => revised(avoid: v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  const ListTile(
                    title: Text(
                      '角色日记',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  for (final entry in state.entries)
                    ExpansionTile(
                      title: Text(entry.day),
                      subtitle: Text(
                        entry.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(entry.text),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('删除此篇并撤回连续记忆'),
                            onPressed: _busy
                                ? null
                                : () => _act(
                                    () => widget.app.rpJournal.repository
                                        .deleteEntry(_card, entry.id),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  if (state.entries.isEmpty)
                    const ListTile(subtitle: Text('暂时没有日记。交流一段时间后，角色会整理新的经历。')),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}
