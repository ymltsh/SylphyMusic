import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/penpal_mailbox_models.dart';

/// A physical-letter-like outbox: no immediate model call on submission.
class PenpalMailboxPage extends StatefulWidget {
  const PenpalMailboxPage({
    super.key,
    required this.app,
    this.relatedLetterKey = '',
  });

  final SylphyApp app;
  final String relatedLetterKey;

  @override
  State<PenpalMailboxPage> createState() => _PenpalMailboxPageState();
}

class _PenpalMailboxPageState extends State<PenpalMailboxPage> {
  final _editor = TextEditingController();
  late String _cardId = widget.app.apiSettings.activeCardId;
  bool _loading = true;
  bool _busy = false;
  int _epoch = 0;
  PenpalMailboxNote? _pending;
  List<PenpalMailboxNote> _history = const [];

  @override
  void initState() {
    super.initState();
    widget.app.apiSettings.addListener(_cardChanged);
    _load(resetDraft: true);
  }

  void _cardChanged() {
    if (!mounted || _cardId == widget.app.apiSettings.activeCardId) return;
    _cardId = widget.app.apiSettings.activeCardId;
    _editor.clear();
    setState(() {
      _history = const [];
      _pending = null;
      _loading = true;
    });
    _load(resetDraft: true);
  }

  Future<void> _load({bool resetDraft = false}) async {
    final epoch = ++_epoch;
    final cardId = _cardId;
    if (mounted) setState(() => _loading = true);
    try {
      final notes = await widget.app.penpalMailbox.history(cardId);
      if (!mounted || epoch != _epoch || cardId != _cardId) return;
      PenpalMailboxNote? pending;
      for (final note in notes) {
        if (note.isPending) {
          pending = note;
          break;
        }
      }
      setState(() {
        _history = notes;
        _pending = pending;
        if (resetDraft) _editor.text = pending?.content ?? '';
        _loading = false;
      });
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('暂时无法读取留言，请稍后再试')));
    }
  }

  Future<void> _save() async {
    if (_busy || _loading || _cardId != widget.app.apiSettings.activeCardId) {
      return;
    }
    final text = _editor.text.trim();
    if (text.isEmpty || text.length > 500) return;
    setState(() => _busy = true);
    try {
      await widget.app.penpalMailbox.saveOrReplace(
        _cardId,
        text,
        relatedLetterKey: widget.relatedLetterKey,
      );
      await _load(resetDraft: true);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('便笺已收好，下次生成新来信时会尝试回复')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('留言保存失败，请检查内容并重试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw() async {
    final note = _pending;
    if (note == null || _busy || _loading) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤回这张便笺？'),
        content: const Text('撤回后笔友不会在下次来信里回复它。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤回'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.app.penpalMailbox.withdraw(_cardId, note.id);
      await _load(resetDraft: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('撤回失败，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteWithdrawn(PenpalMailboxNote note) async {
    if (_busy ||
        _loading ||
        note.status != 'withdrawn' ||
        note.cardId != _cardId ||
        _cardId != widget.app.apiSettings.activeCardId)
      return;
    setState(() => _busy = true);
    try {
      await widget.app.penpalMailbox.deleteWithdrawn(note.cardId, note.id);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    ++_epoch;
    widget.app.apiSettings.removeListener(_cardChanged);
    _editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.app.apiSettings.cards.activeName;
    final pending = _pending;
    return Scaffold(
      appBar: AppBar(title: Text('给$name留言')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        pending == null ? '写一张便笺' : '等待回信的便笺',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text('笔友会在下次的音乐来信里回应你'),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _editor,
                        enabled: !_busy && !_loading,
                        maxLength: 500,
                        minLines: 4,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '这次有什么想告诉笔友的？',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _busy || _loading ? null : _save,
                              icon: const Icon(
                                Icons.mark_email_unread_outlined,
                              ),
                              label: Text(pending == null ? '留下便笺' : '保存修改'),
                            ),
                          ),
                          if (pending != null) ...[
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: _busy || _loading ? null : _withdraw,
                              child: const Text('撤回'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_busy || _loading) const LinearProgressIndicator(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '往日便笺',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_history.isEmpty && !_loading)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('还没有留下便笺。'),
                ),
              for (final note in _history)
                Card(
                  child: ListTile(
                    title: Text(note.content),
                    subtitle: Text(_status(note)),
                    trailing: note.status == 'withdrawn'
                        ? IconButton(
                            tooltip: '删除已撤回留言',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _busy || _loading
                                ? null
                                : () => _deleteWithdrawn(note),
                          )
                        : null,
                    onTap: note.replyContent.isEmpty
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(
                                note.replyTitle.isEmpty
                                    ? '笔友的回信'
                                    : note.replyTitle,
                              ),
                              content: SizedBox(
                                width: 520,
                                child: SingleChildScrollView(
                                  child: SelectableText(note.replyContent),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('关闭'),
                                ),
                              ],
                            ),
                          ),
                    leading: Icon(
                      note.isPending
                          ? Icons.markunread_mailbox_outlined
                          : note.status == 'answered'
                          ? Icons.mark_email_read_outlined
                          : Icons.undo_outlined,
                    ),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '每位角色的留言互不共享。模型失败或本地推荐不会消耗便笺；'
                  '只有成功写出的回信存档后才会标记已回复。留言默认不成为长期记忆。',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _status(PenpalMailboxNote note) {
    final date = DateTime.fromMillisecondsSinceEpoch(note.createdAtMs);
    final day =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    if (note.isPending) return '$day · 等待下一封新来信';
    if (note.status == 'withdrawn') return '$day · 已撤回';
    if (note.replyTitle.isNotEmpty) {
      return '$day · 已在《${note.replyTitle}》中回复';
    }
    return '$day · 已回复（回信可能已从存档中清理）';
  }
}
