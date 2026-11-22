import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/rp_models.dart';
import 'rp_journal_page.dart';
import 'design_system/adaptive_collapsing_chrome.dart';

/// Character-scoped RP controls. No network calls or generated autobiography.
class RpManagementPage extends StatefulWidget {
  const RpManagementPage({super.key, required this.app});
  final SylphyApp app;

  @override
  State<RpManagementPage> createState() => _RpManagementPageState();
}

class _RpManagementPageState extends State<RpManagementPage> {
  late Future<RpSnapshot> _load = _read();
  bool _busy = false;
  late String _currentCard = widget.app.apiSettings.activeCardId;
  String get _id => widget.app.apiSettings.activeCardId;
  Future<RpSnapshot> _read() => widget.app.rpRuntime.snapshot(_id);

  @override
  void initState() {
    super.initState();
    widget.app.apiSettings.addListener(_cardChanged);
  }

  void _cardChanged() {
    if (!mounted || _currentCard == _id) return;
    _currentCard = _id;
    setState(() => _load = _read());
  }

  @override
  void dispose() {
    widget.app.apiSettings.removeListener(_cardChanged);
    super.dispose();
  }

  Future<void> _act(Future<void> Function() task) async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      await task();
      if (mounted) setState(() => _load = _read());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('操作没有完成，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _text(
    String title,
    String initial, {
    int maxLength = 240,
  }) async {
    final ctrl = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 500,
            child: TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: maxLength,
              maxLines: 5,
              minLines: 2,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _addLore(String kind) async {
    final title = await _text(
      kind == 'event' ? '事件标题' : '世界书标题',
      '',
      maxLength: 60,
    );
    if (!mounted || title == null || title.isEmpty) return;
    final content = await _text('内容（写清楚这是角色世界中的设定）', '', maxLength: 500);
    if (!mounted || content == null || content.isEmpty) return;
    final words = kind == 'lore'
        ? await _text('触发词（用英文逗号分隔，空白表示不自动触发）', '', maxLength: 160)
        : '';
    if (!mounted || words == null) return;
    await _act(() async {
      await widget.app.rpRuntime.repository.addLore(
        _id,
        kind: kind,
        title: title,
        content: content,
        triggers: words
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .take(12)
            .toList(),
      );
    });
  }

  Future<void> _clearAllMemory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空当前角色的 RP 记忆？'),
        content: const Text(
          '清除当前角色的日记、连续认知和已发生事件；保留角色卡、世界书与场景设置。聊天原文单独管理。此操作不可撤销。',
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
    if (!mounted || confirmed != true) return;
    await _act(() => widget.app.rpRuntime.repository.clearMemories(_id));
  }

  Widget _section(String title, List<Widget> children, {Widget? action}) =>
      Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: [
            ListTile(
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: action,
            ),
            ...children,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: sylphyGradientAppBar(
        title: const Text('关于我的音乐笔友'),
        bottom: const TabBar(
          tabs: [
            Tab(text: '日记与记忆'),
            Tab(text: '状态与世界书'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          RpJournalPage(app: widget.app, embedded: true),
          FutureBuilder<RpSnapshot>(
            future: _load,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: () => setState(() => _load = _read()),
                    child: const Text('读取失败，点击重试'),
                  ),
                );
              }
              if (!snap.hasData)
                return const Center(child: CircularProgressIndicator());
              final data = snap.data!;
              final state = data.state;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      '通过世界书，你可以影响笔友的故事',
                    ),
                  ),
                  _section('角色当前状态', [
                    ListTile(
                      title: const Text('当前场景'),
                      subtitle: Text(state.scene),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: _busy
                          ? null
                          : () async {
                              final text = await _text('当前场景', state.scene);
                              if (text != null && text.isNotEmpty)
                                await _act(
                                  () => widget.app.rpRuntime.repository
                                      .updateState(_id, scene: text),
                                );
                            },
                    ),
                    ListTile(
                      title: const Text('正在做什么'),
                      subtitle: Text(state.activity),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: _busy
                          ? null
                          : () async {
                              final text = await _text(
                                '角色当前活动',
                                state.activity,
                              );
                              if (text != null && text.isNotEmpty)
                                await _act(
                                  () => widget.app.rpRuntime.repository
                                      .updateState(_id, activity: text),
                                );
                            },
                    ),
                    ListTile(
                      title: const Text('当前目标'),
                      subtitle: Text(state.goal),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: _busy
                          ? null
                          : () async {
                              final text = await _text('角色当前目标', state.goal);
                              if (text != null && text.isNotEmpty)
                                await _act(
                                  () => widget.app.rpRuntime.repository
                                      .updateState(_id, goal: text),
                                );
                            },
                    ),
                    ListTile(
                      title: const Text('叙事精力'),
                      subtitle: Text('${state.energy} / 100（角色演绎状态）'),
                      trailing: PopupMenuButton<int>(
                        tooltip: '调整叙事精力',
                        onSelected: (value) => _act(
                          () => widget.app.rpRuntime.repository.updateState(
                            _id,
                            energy: value,
                          ),
                        ),
                        itemBuilder: (_) => [
                          for (final n in [20, 40, 60, 80, 100])
                            PopupMenuItem(value: n, child: Text('$n / 100')),
                        ],
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('使用 RP 记忆'),
                      subtitle: const Text('关闭时不记录或召回 RP 记忆；单独保存的聊天记录仍由聊天页面管理'),
                      value: state.memoryEnabled,
                      onChanged: _busy
                          ? null
                          : (v) => _act(
                              () => widget.app.rpRuntime.repository.updateState(
                                _id,
                                memoryEnabled: v,
                              ),
                            ),
                    ),
                    SwitchListTile(
                      title: const Text('随机世界事件'),
                      subtitle: const Text('仅前台交互触发，每个本地自然日最多抽取一次'),
                      value: state.eventsEnabled,
                      onChanged: _busy
                          ? null
                          : (v) => _act(
                              () => widget.app.rpRuntime.repository.updateState(
                                _id,
                                eventsEnabled: v,
                              ),
                            ),
                    ),
                  ]),
                  _section(
                    '世界书与随机事件',
                    [
                      for (final item in data.lore)
                        ListTile(
                          title: Text(
                            '${item.kind == 'event' ? '🎲 ' : '📖 '}${item.title}',
                          ),
                          subtitle: Text(
                            '${item.content}\n${item.triggers.isEmpty ? '随机事件' : '触发：${item.triggers.join('、')}'}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: item.enabled,
                                onChanged: _busy
                                    ? null
                                    : (v) => _act(
                                        () => widget.app.rpRuntime.repository
                                            .enableLore(_id, item.id, v),
                                      ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: '删除条目',
                                onPressed: _busy
                                    ? null
                                    : () => _act(
                                        () => widget.app.rpRuntime.repository
                                            .removeLore(_id, item.id),
                                      ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    action: PopupMenuButton<String>(
                      tooltip: '新增世界书或事件',
                      onSelected: _addLore,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'lore', child: Text('新增世界设定')),
                        PopupMenuItem(value: 'event', child: Text('新增随机事件')),
                      ],
                      icon: const Icon(Icons.add),
                    ),
                  ),
                  _section('最近事件', [
                    for (final event in data.events.take(12))
                      ListTile(
                        title: Text(event.title),
                        subtitle: Text(
                          '${event.status} · ${event.description}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: event.status == 'active'
                            ? IconButton(
                                icon: const Icon(Icons.check_circle_outline),
                                tooltip: '结束事件',
                                onPressed: _busy
                                    ? null
                                    : () => _act(
                                        () => widget.app.rpRuntime.repository
                                            .resolveEvent(_id, event.id),
                                      ),
                              )
                            : null,
                      ),
                    if (data.events.isEmpty)
                      const ListTile(subtitle: Text('暂未触发事件')),
                  ]),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'For you，with you.',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _clearAllMemory,
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('清空此角色的 RP 记忆'),
                  ),
                  if (_busy) const LinearProgressIndicator(),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}
