import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../data/library_catalog.dart';
import 'capsule_toggle.dart';
import 'library_browser.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.app,
    required this.onAction,
    this.initialSource,
  });
  final SylphyApp app;
  final Future<void> Function(String, Track) onAction;
  final String? initialSource;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final input = TextEditingController();
  Timer? debounce;
  String query = '';
  String? source;
  int view = 0;
  @override
  void initState() {
    super.initState();
    source = widget.initialSource;
  }

  @override
  void dispose() {
    debounce?.cancel();
    input.dispose();
    super.dispose();
  }

  void _search(String value) {
    debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => query = '');
      return;
    }
    debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: TextField(
        controller: input,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '搜索歌曲、专辑、艺术家',
          border: InputBorder.none,
          suffixIcon: IconButton(
            tooltip: '清空搜索',
            icon: const Icon(Icons.close),
            onPressed: () {
              input.clear();
              _search('');
            },
          ),
        ),
        onChanged: _search,
        onSubmitted: (v) {
          debounce?.cancel();
          setState(() => query = v.trim());
        },
      ),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: CapsuleToggle<int>(
                  keyPrefix: 'search-filter',
                  selected: view,
                  onChanged: (value) => setState(() => view = value),
                  options: const [
                    CapsuleOption(
                      value: 0,
                      label: '歌曲',
                      icon: Icons.music_note_outlined,
                    ),
                    CapsuleOption(
                      value: 1,
                      label: '专辑',
                      icon: Icons.album_outlined,
                    ),
                    CapsuleOption(
                      value: 2,
                      label: '艺术家',
                      icon: Icons.person_outline,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '搜索来源',
                icon: const Icon(Icons.filter_list),
                onSelected: (v) =>
                    setState(() => source = v == 'all' ? null : v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'all', child: Text('全部来源')),
                  ...widget.app.sources.map(
                    (s) => PopupMenuItem(value: s.id, child: Text(s.name)),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: query.isEmpty
              ? const Center(child: Text('输入关键词，搜索你的音乐库'))
              : LibraryBrowser(
                  app: widget.app,
                  query: CatalogQuery(
                    view: view,
                    search: query,
                    sourceId: source,
                  ),
                  onAction: widget.onAction,
                ),
        ),
      ],
    ),
  );
}
