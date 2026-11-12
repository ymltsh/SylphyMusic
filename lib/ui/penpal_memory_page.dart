import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/penpal_models.dart';

/// The penpal's memories are transparent and editable by the user.
class PenpalMemoryPage extends StatefulWidget {
  const PenpalMemoryPage({super.key, required this.app});

  final SylphyApp app;

  @override
  State<PenpalMemoryPage> createState() => _PenpalMemoryPageState();
}

class _PenpalMemoryPageState extends State<PenpalMemoryPage> {
  late Future<PenpalMemorySnapshot> _state = widget.app.penpalMemory.snapshot();
  bool _busy = false;

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
      if (mounted) {
        setState(() => _state = widget.app.penpalMemory.snapshot());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('记忆操作失败，请稍后再试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editSoul(String current) async {
    final controller = TextEditingController(text: current);
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('笔友的人格'),
        content: SizedBox(
          width: 540,
          child: TextField(
            controller: controller,
            maxLength: 1000,
            maxLines: 8,
            minLines: 4,
            decoration: const InputDecoration(
              helperText: '这是笔友的稳定性格，不是用户画像；留空恢复默认',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next != null) {
      await _run(() => widget.app.penpalMemory.setSoul(next));
    }
  }

  Future<void> _clear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空笔友记忆？'),
        content: const Text(
          '会删除自我反思、共同记忆、保存过的回复和聊天记录，并将人格恢复默认。'
          '已有来信、曲库及播放统计不会删除；此操作无法撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空记忆'),
          ),
        ],
      ),
    );
    if (yes == true) await _run(widget.app.penpalMemory.clear);
  }

  Widget _memoryGroup(
    String title,
    String description,
    List<PenpalMemoryEntry> memories,
  ) {
    if (memories.isEmpty) return const SizedBox.shrink();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(title: Text(title), subtitle: Text(description)),
          for (final memory in memories.take(40))
            ListTile(
              title: Text(memory.text),
              subtitle: Text(
                '${DateTime.fromMillisecondsSinceEpoch(memory.createdAtMs).toLocal().year}-'
                '${DateTime.fromMillisecondsSinceEpoch(memory.createdAtMs).toLocal().month}-'
                '${DateTime.fromMillisecondsSinceEpoch(memory.createdAtMs).toLocal().day}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '忘记这条记忆',
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => widget.app.penpalMemory.deleteEntry(memory.id),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于我的音乐笔友')),
    body: FutureBuilder<PenpalMemorySnapshot>(
      future: _state,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () =>
                  setState(() => _state = widget.app.penpalMemory.snapshot()),
              child: const Text('读取笔友记忆失败，点击重试'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final self = data.entries.where((e) => e.kind == 'self').toList();
        final bond = data.entries
            .where(
              (e) =>
                  e.kind == 'user_reply' ||
                  e.kind == 'letter_opened' ||
                  e.kind == 'chat_preference',
            )
            .toList();
        final episodes = data.entries
            .where((e) => e.kind == 'letter_written')
            .toList();
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('保留笔友记忆'),
                        subtitle: const Text('关闭后停止写入和使用记忆；已有记忆保留在本机'),
                        value: data.enabled,
                        onChanged: _busy
                            ? null
                            : (v) => _run(
                                () => widget.app.penpalMemory.setEnabled(v),
                              ),
                      ),
                      SwitchListTile(
                        title: const Text('在来信中自然提起往事'),
                        subtitle: const Text('关闭后不在推荐和聊天中传输历史记忆'),
                        value: data.recallEnabled,
                        onChanged: _busy || !data.enabled
                            ? null
                            : (v) => _run(
                                () =>
                                    widget.app.penpalMemory.setRecallEnabled(v),
                              ),
                      ),
                    ],
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.auto_stories_outlined),
                    title: const Text('它是什么样的笔友'),
                    subtitle: Text(data.soul),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: _busy ? null : () => _editSoul(data.soul),
                  ),
                ),
                _memoryGroup('它最近在想', '由真实来信延伸出的有限自我反思', self),
                _memoryGroup('我们记住的事', '记录打开信件、主动回复和选择记住的聊天原话，不猜测感受', bond),
                _memoryGroup('它写过的信', '短摘要；完整内容仍在每日来信存档', episodes),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    '记忆仅存在于本机。开启 LLM 时，精简的人格、聊天观点和记忆可能随选曲、写信或聊天请求'
                    '发送到你配置的模型服务；不会发送整份存档。清空记忆也会删除已保存的聊天记录。',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _clear,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('清空笔友记忆'),
                ),
                if (_busy) const LinearProgressIndicator(),
              ],
            ),
          ),
        );
      },
    ),
  );
}
