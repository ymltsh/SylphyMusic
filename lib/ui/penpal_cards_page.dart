import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/penpal_card.dart';
import '../services/api_settings.dart';
import 'penpal_avatar.dart';

class PenpalCardsPage extends StatefulWidget {
  const PenpalCardsPage({super.key, required this.app});
  final SylphyApp app;
  @override
  State<PenpalCardsPage> createState() => _PenpalCardsPageState();
}

class _PenpalCardsPageState extends State<PenpalCardsPage> {
  late Future<List<PenpalCard>> _cards = widget.app.apiSettings.cards.list();
  bool _busy = false;

  void _reload() =>
      setState(() => _cards = widget.app.apiSettings.cards.list());

  Future<void> _act(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
      if (mounted) _reload();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('角色卡操作未完成：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([PenpalCard? card]) async {
    final result =
        await showDialog<({String name, String system, String user})>(
          context: context,
          builder: (_) => _CardEditor(card: card),
        );
    if (result == null || !mounted) return;
    await _act(() async {
      final store = widget.app.apiSettings.cards;
      if (card == null) {
        final created = await store.create(
          name: result.name,
          system: result.system,
          user: result.user,
        );
        await store.activate(created.id);
      } else {
        await store.updateCard(
          card.id,
          name: result.name,
          system: result.system,
          user: result.user,
        );
      }
    });
  }

  Future<void> _import() async {
    var raw = '';
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入角色卡 JSON'),
        content: SizedBox(
          width: 580,
          child: TextField(
            onChanged: (value) => raw = value,
            maxLength: 150000,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '粘贴包含 name、system、user 的角色卡',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, raw),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    await _act(() async {
      final card = await widget.app.apiSettings.cards.importJson(text);
      await widget.app.apiSettings.cards.activate(card.id);
    });
  }

  Future<void> _chooseAvatar(PenpalCard card) async {
    await _act(() async {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      );
      if (file == null || !mounted) return;
      final length = await file.length();
      if (length != null && length > 8 * 1024 * 1024) {
        throw const FormatException('请选择小于 8 MiB 的头像');
      }
      await widget.app.apiSettings.cards.setAvatar(
        card.id,
        await file.readAsBytes(),
      );
    });
  }

  Future<void> _delete(PenpalCard card) async {
    final current = card.id == widget.app.apiSettings.activeCardId;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除「${card.name}」？'),
        content: Text(
          '将删除该角色卡及其聊天与记忆，历史来信保留。'
          '${current ? '删除后将切换到另一位笔友；若没有其他角色，将新建默认笔友。' : ''}'
          '此操作无法撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除角色'),
          ),
        ],
      ),
    );
    if (yes == true && mounted)
      await _act(() => widget.app.apiSettings.cards.delete(card.id));
  }

  Future<void> _menu(PenpalCard card, String action) async {
    final cards = widget.app.apiSettings.cards;
    switch (action) {
      case 'select':
        await _act(() => cards.activate(card.id));
      case 'copy':
        await _act(() async {
          final copy = await cards.duplicate(card);
          await cards.activate(copy.id);
        });
      case 'export':
        await Clipboard.setData(ClipboardData(text: cards.exportJson(card)));
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('角色卡 JSON 已复制到剪贴板')));
      case 'delete':
        await _delete(card);
      case 'avatar':
        await _chooseAvatar(card);
      case 'clear-avatar':
        await _act(() => cards.clearAvatar(card.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('我的音乐笔友')),
    body: SafeArea(
      top: false,
      child: FutureBuilder<List<PenpalCard>>(
        future: _cards,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(
              child: TextButton(
                onPressed: _reload,
                child: const Text('读取角色卡失败，点击重试'),
              ),
            );
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('每位笔友有独立的头像、设定、聊天和记忆。点击头像可更换，角色名称与提示词均可编辑。'),
                  const SizedBox(height: 12),
                  for (final card in snapshot.data!) _card(card),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _edit(),
                        icon: const Icon(Icons.add),
                        label: const Text('新建角色'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _import,
                        icon: const Icon(Icons.file_download_outlined),
                        label: const Text('导入角色卡 JSON'),
                      ),
                    ],
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _card(PenpalCard card) {
    final active = card.id == widget.app.apiSettings.activeCardId;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: IconButton(
              tooltip: '更换头像',
              padding: EdgeInsets.zero,
              onPressed: _busy ? null : () => _chooseAvatar(card),
              icon: PenpalAvatar(
                store: widget.app.apiSettings.cards,
                card: card,
              ),
            ),
            title: Text(card.name),
            subtitle: Text(
              '${active ? '正在通信' : '未使用'} · ${card.builtin ? '彩蛋角色' : '自定义角色'}',
            ),
            onTap: _busy || active
                ? null
                : () => _act(
                    () => widget.app.apiSettings.cards.activate(card.id),
                  ),
            trailing: PopupMenuButton<String>(
              tooltip: '角色操作',
              enabled: !_busy,
              onSelected: (value) => unawaited(_menu(card, value)),
              itemBuilder: (_) => [
                if (!active)
                  const PopupMenuItem(value: 'select', child: Text('使用这位笔友')),
                const PopupMenuItem(value: 'avatar', child: Text('更换头像')),
                if (card.avatarPath.isNotEmpty)
                  const PopupMenuItem(
                    value: 'clear-avatar',
                    child: Text('恢复默认头像'),
                  ),
                const PopupMenuItem(value: 'copy', child: Text('复制为新角色')),
                const PopupMenuItem(value: 'export', child: Text('复制导出 JSON')),
                const PopupMenuItem(value: 'delete', child: Text('删除角色')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : () => _edit(card),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('编辑提示词与角色'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardEditor extends StatefulWidget {
  const _CardEditor({this.card});
  final PenpalCard? card;
  @override
  State<_CardEditor> createState() => _CardEditorState();
}

class _CardEditorState extends State<_CardEditor> {
  late final _name = TextEditingController(text: widget.card?.name ?? '新的音乐笔友');
  late final _system = TextEditingController(
    text: widget.card?.system ?? ApiSettings.defaultLlmSystemPrompt,
  );
  late final _user = TextEditingController(
    text: widget.card?.user ?? ApiSettings.defaultLlmUserPrompt,
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _system.dispose();
    _user.dispose();
    super.dispose();
  }

  void _save() {
    try {
      if (_name.text.trim().isEmpty || _name.text.trim().length > 80)
        throw const FormatException('角色名称需要 1–80 字');
      Navigator.pop(context, (
        name: _name.text.trim(),
        system: ApiSettings.validateLlmSystemPrompt(_system.text),
        user: ApiSettings.validateLlmUserPrompt(_user.text),
      ));
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.card == null ? '新建音乐笔友' : '编辑角色与提示词'),
    content: SizedBox(
      width: 640,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('保存后保留原有聊天和记忆；修改当前笔友会同步更新推荐使用的设定。'),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: '角色名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _system,
              minLines: 5,
              maxLines: 10,
              maxLength: ApiSettings.maxLlmSystemPromptLength,
              decoration: const InputDecoration(
                labelText: '角色设定 · System',
                helperText: '身份、性格与表达方式；留空恢复默认',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              minLines: 3,
              maxLines: 6,
              maxLength: ApiSettings.maxLlmUserPromptLength,
              decoration: const InputDecoration(
                labelText: '个人偏好 · User',
                helperText: '选曲侧重与来信偏好；留空恢复默认',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存')),
    ],
  );
}
