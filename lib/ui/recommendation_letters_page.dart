import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import 'letter_image.dart';
import '../core/recommendation_models.dart';
import '../core/models.dart';
import 'recommendation_showcase.dart';
import 'penpal_memory_page.dart';
import 'penpal_chat_page.dart';

/// Private letters from each daily recommendation generation, kept separately
/// from diagnostic logs and independent of old recommendation snapshots.
class RecommendationLettersPage extends StatefulWidget {
  const RecommendationLettersPage({super.key, required this.app});

  final SylphyApp app;

  @override
  State<RecommendationLettersPage> createState() =>
      _RecommendationLettersPageState();
}

class _RecommendationLettersPageState extends State<RecommendationLettersPage> {
  static const _pageSize = 30;
  final List<RecommendationLetter> _letters = [];
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final batch = await widget.app.recommendationRepository.letters(
        offset: _letters.length,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _letters.addAll(batch);
        _hasMore = batch.length == _pageSize;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '读取文案存档失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clearLetters() async {
    if (_loading) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空每日推荐文案？'),
        content: const Text(
          '删除私人信件存档，也会清除来源于这些信件的笔友记忆、回复和聊天记录；不会删除播放历史、曲库或推荐统计。此操作不能撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await widget.app.recommendationRepository.clearLetters();
      await widget.app.penpalMemory.clearLetterDerived();
      if (mounted) {
        setState(() {
          _letters.clear();
          _hasMore = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法清空信件，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Track>> _coversForLetter(RecommendationLetter letter) async {
    final covers = <Track>[];
    for (final ref in letter.coverRefs) {
      final track = await widget.app.db.track(ref);
      if (track != null && !track.missing) covers.add(track);
    }
    return covers;
  }

  Future<void> _replyToLetter(RecommendationLetter letter) =>
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => PenpalChatPage(
            app: widget.app,
            letterKey: '${letter.day}:${letter.generation}',
            letterTitle: letter.title,
            letterContext:
                '${letter.title}\n${letter.content}\n${letter.detailsText}',
          ),
        ),
      );

  Widget _letterMore(RecommendationLetter letter) => PopupMenuButton<String>(
    tooltip: '更多',
    onSelected: (_) => _replyToLetter(letter),
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'chat', child: Text('与笔友聊天')),
    ],
  );

  void _openLetter(RecommendationLetter letter) {
    unawaited(
      widget.app.penpalMemory
          .recordOpenedLetter(letter)
          .catchError((Object _) {}),
    );
    final coversFuture = _coversForLetter(letter);
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text('${letter.day} · 第 ${letter.generation + 1} 封信'),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Card.filled(
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.mark_email_read_outlined,
                              color: Theme.of(context).colorScheme.primary,
                              size: 32,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              letter.title,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${letter.day} · ${letter.trackCount > 0 ? '${letter.trackCount} 首 · ' : ''}${letter.origin == 'llm' ? '音乐笔友' : '本地精选'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (letter.coverRefs.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              FutureBuilder<List<Track>>(
                                future: coversFuture,
                                builder: (context, snapshot) {
                                  final tracks =
                                      snapshot.data ?? const <Track>[];
                                  if (tracks.isEmpty)
                                    return const SizedBox.shrink();
                                  final mix = DailyMix(
                                    letter.day,
                                    letter.generation,
                                    [
                                      for (final t in tracks)
                                        RecommendedTrack(t, '', 0),
                                    ],
                                  );
                                  return Center(
                                    child: RecommendationCoverDeck(
                                      app: widget.app,
                                      mix: mix,
                                      size: 210,
                                    ),
                                  );
                                },
                              ),
                            ],
                            const SizedBox(height: 24),
                            SelectableText(
                              letter.content,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(height: 1.85),
                            ),
                            if (letter.detailsText.trim().isNotEmpty) ...[
                              const SizedBox(height: 28),
                              Text(
                                '这轮推荐的歌曲与理由',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              SelectableText(
                                letter.detailsText,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(height: 1.8),
                              ),
                            ],
                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 12),
                            FutureBuilder<List<Track>>(
                              future: coversFuture,
                              builder: (context, snapshot) => Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: LetterImageActions(
                                      app: widget.app,
                                      day: letter.day,
                                      title: letter.title,
                                      content: letter.content,
                                      tracks: snapshot.data ?? const <Track>[],
                                      trackCount: letter.trackCount,
                                      detailsText: letter.detailsText
                                          .split('\n')
                                          .take(3)
                                          .join('\n'),
                                    ),
                                  ),
                                  _letterMore(letter),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('每日推荐文案'),
        actions: [
          IconButton(
            tooltip: '关于我的音乐笔友',
            icon: const Icon(Icons.auto_stories_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PenpalMemoryPage(app: widget.app),
              ),
            ),
          ),
          IconButton(
            tooltip: '清空文案存档',
            icon: const Icon(Icons.delete_outline),
            onPressed: _letters.isEmpty || _loading ? null : _clearLetters,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: _letters.isEmpty && !_loading
              ? Center(
                  child: _error == null
                      ? const Text('还没有收到音乐来信。生成一轮每日精选后，这里会留下记录。')
                      : TextButton(
                          onPressed: _loadMore,
                          child: Text('$_error，点击重试'),
                        ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _letters.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _letters.length) {
                      if (_loading) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (!_hasMore && _error == null) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.all(8),
                        child: Center(
                          child: TextButton.icon(
                            onPressed: _loadMore,
                            icon: const Icon(Icons.expand_more),
                            label: Text(_error ?? '继续翻阅往日来信'),
                          ),
                        ),
                      );
                    }
                    final letter = _letters[index];
                    final firstLine = letter.content
                        .replaceAll(RegExp(r'\s+'), ' ')
                        .trim();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 8,
                          ),
                          leading: const Icon(Icons.mail_outline_rounded),
                          title: Text(letter.title),
                          subtitle: Text(
                            firstLine,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: _letterMore(letter),
                          onTap: () => _openLetter(letter),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
