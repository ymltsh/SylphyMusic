import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/penpal_chat_models.dart';
import '../services/penpal_chat.dart';
import 'penpal_memory_page.dart';
import 'penpal_avatar.dart';

class PenpalChatPage extends StatefulWidget {
  const PenpalChatPage({
    super.key,
    required this.app,
    required this.letterKey,
    required this.letterTitle,
    required this.letterContext,
  });
  final SylphyApp app;
  final String letterKey, letterTitle, letterContext;

  @override
  State<PenpalChatPage> createState() => _PenpalChatPageState();
}

class _PenpalChatPageState extends State<PenpalChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<PenpalChatMessage> _messages = [];
  PenpalChatRequest? _request;
  late String _persona;
  bool _loading = true, _busy = false, _failed = false, _older = false;
  bool _remember = true, _canRemember = true, _includeLetter = true;
  String? _error;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _persona = widget.app.penpalChat.personaKey;
    widget.app.apiSettings.addListener(_settingsChanged);
    unawaited(_load());
  }

  void _settingsChanged() {
    if (!mounted) return;
    final persona = widget.app.penpalChat.personaKey;
    if (persona != _persona) {
      // The old letter context belongs to another character. Leave the route
      // rather than attaching it to a new card's conversation.
      _request?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.maybePop(context);
      });
      return;
    }
    setState(() {});
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _messages.clear();
      _busy = false;
      _failed = false;
      _error = null;
    });
    try {
      final state = await widget.app.penpalMemory.snapshot();
      final history = await widget.app.penpalChat.history(
        _persona,
        widget.letterKey,
      );
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _canRemember = state.enabled;
        _remember = _remember && state.enabled;
        _messages
          ..clear()
          ..addAll(history);
        _older = history.length == 40;
      });
      _toBottom();
    } catch (_) {
      if (mounted && epoch == _epoch)
        setState(() => _error = '聊天记录读取失败，请返回后重试');
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  Future<void> _loadOlder() async {
    if (_loading || _busy || _messages.isEmpty) return;
    final epoch = _epoch;
    final before = _messages.first.id;
    if (before == null) return;
    setState(() => _loading = true);
    try {
      final rows = await widget.app.penpalChat.history(
        _persona,
        widget.letterKey,
        before: before,
      );
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _messages.insertAll(0, rows);
        _older = rows.length == 40;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '更早的聊天暂时无法读取');
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: Duration(
          milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 220,
        ),
        curve: Curves.easeOut,
      );
    }
  });

  Future<void> _send({bool retry = false}) async {
    if (_busy || _loading || (!retry && _failed)) return;
    final text = retry ? _messages.last.content : _input.text.trim();
    if (text.isEmpty || text.length > 2000) return;
    final epoch = _epoch;
    final request = PenpalChatRequest();
    _request = request;
    setState(() {
      _busy = true;
      _failed = false;
      _error = null;
      if (!retry) {
        _messages.add(
          PenpalChatMessage(
            role: 'user',
            content: text,
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        _input.clear();
      }
    });
    _toBottom();
    try {
      final answer = await widget.app.penpalChat.send(
        persona: _persona,
        letter: widget.letterKey,
        letterContext: _includeLetter ? widget.letterContext : '',
        messages: List.of(_messages),
        remember: _remember,
        request: request,
      );
      if (!mounted || epoch != _epoch) return;
      setState(
        () => _messages.add(
          PenpalChatMessage(
            role: 'assistant',
            content: answer,
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );
      _toBottom();
    } catch (error) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _failed = true;
        _error = error is StateError ? '${error.message}' : '回复未完成，请重试';
      });
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空这段聊天？'),
        content: const Text('删除这封信下当前笔友的聊天，以及从中保存的个性化观点。信件本身会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await widget.app.penpalChat.clear(_persona, widget.letterKey);
      if (!mounted) return;
      setState(() {
        _messages.clear();
        _failed = false;
        _error = null;
        _older = false;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '清空失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    ++_epoch;
    _request?.cancel();
    widget.app.apiSettings.removeListener(_settingsChanged);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = widget.app.apiSettings.llmEnabled;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            PenpalAvatar(store: widget.app.apiSettings.cards, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.app.apiSettings.cards.activeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            enabled: !_busy && !_loading,
            onSelected: (action) async {
              if (action == 'clear') {
                await _clear();
              }
              if (action == 'memory' && mounted) {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => PenpalMemoryPage(app: widget.app),
                  ),
                );
                if (mounted) await _load();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'memory', child: Text('管理笔友记忆')),
              PopupMenuItem(value: 'clear', child: Text('清空这段聊天')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '聊聊你的看法，也可以只是说说话。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      FilterChip(
                        label: Text(
                          '关于《${widget.letterTitle}》',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: _includeLetter,
                        onSelected: _busy
                            ? null
                            : (v) => setState(() => _includeLetter = v),
                      ),
                    ],
                  ),
                ),
                if (_loading) const LinearProgressIndicator(),
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(
                              enabled
                                  ? '这次的选曲，有哪一首让你想说点什么？\n\n也可以从今天的一件小事聊起。'
                                  : '请在推荐设置开启 LLM，并在 API 设置配置连接，再来与笔友聊天。',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length + (_older ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (_older && index == 0)
                              return TextButton(
                                onPressed: _loading ? null : _loadOlder,
                                child: const Text('查看更早的聊天'),
                              );
                            final message = _messages[index - (_older ? 1 : 0)];
                            final user = message.role == 'user';
                            return Align(
                              alignment: user
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(14),
                                constraints: const BoxConstraints(
                                  maxWidth: 620,
                                ),
                                decoration: BoxDecoration(
                                  color: user
                                      ? colors.primaryContainer
                                      : colors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user ? '你' : '笔友',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: user
                                                ? colors.onPrimaryContainer
                                                : colors.primary,
                                          ),
                                    ),
                                    const SizedBox(height: 5),
                                    SelectableText(
                                      message.content,
                                      style: TextStyle(
                                        height: 1.6,
                                        color: user
                                            ? colors.onPrimaryContainer
                                            : colors.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                if (_busy)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('笔友正在回复…'),
                      TextButton(
                        onPressed: () => _request?.cancel(),
                        child: const Text('停止'),
                      ),
                    ],
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        Text(_error!, style: TextStyle(color: colors.error)),
                        if (_failed)
                          Wrap(
                            spacing: 12,
                            children: [
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _send(retry: true),
                                child: const Text('重试这句话'),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                        _input.text = _messages
                                            .removeLast()
                                            .content;
                                        _failed = false;
                                        _error = null;
                                      }),
                                child: const Text('编辑后重发'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Column(
                    children: [
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('记住聊天，帮助后续选曲和写信'),
                        subtitle: Text(
                          _canRemember
                              ? '勾选后保存到本机；聊天内容会发送给已配置模型，可随时删除。'
                              : '笔友记忆已关闭，本次聊天不保存。',
                        ),
                        value: _canRemember && _remember,
                        onChanged: _busy || !_canRemember
                            ? null
                            : (v) => setState(() => _remember = v ?? false),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: CallbackShortcuts(
                              bindings: {
                                const SingleActivator(
                                  LogicalKeyboardKey.enter,
                                  control: true,
                                ): () =>
                                    unawaited(_send()),
                              },
                              child: TextField(
                                controller: _input,
                                enabled: enabled && !_loading,
                                minLines: 1,
                                maxLines: 5,
                                maxLength: 2000,
                                decoration: const InputDecoration(
                                  hintText: '和笔友说点什么…',
                                  border: OutlineInputBorder(),
                                  counterText: '',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed:
                                enabled && !_busy && !_loading && !_failed
                                ? () => _send()
                                : null,
                            tooltip: '发送',
                            icon: const Icon(Icons.arrow_upward_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
