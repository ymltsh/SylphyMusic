import 'package:flutter/material.dart';

import '../services/sources.dart' show WebDavDirectory;

/// Browse directories with one WebDAV Depth:1 request per opened folder.
class WebDavFolderPicker extends StatefulWidget {
  const WebDavFolderPicker({
    super.key,
    required this.initialPath,
    required this.load,
  });

  final String initialPath;
  final Future<List<WebDavDirectory>> Function(String path) load;

  @override
  State<WebDavFolderPicker> createState() => _WebDavFolderPickerState();
}

class _WebDavFolderPickerState extends State<WebDavFolderPicker> {
  late String _path;
  late Future<List<WebDavDirectory>> _listing;

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
    _listing = widget.load(_path);
  }

  void _open(String path) {
    setState(() {
      _path = path;
      _listing = widget.load(path);
    });
  }

  String get _parentPath {
    final segments = Uri.parse(_path).pathSegments
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.isEmpty) return '';
    segments.removeLast();
    return Uri(pathSegments: segments).toString();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('选择 WebDAV 基础目录'),
    content: SizedBox(
      width: 520,
      height: 370,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '上一级',
                onPressed: _path.isEmpty ? null : () => _open(_parentPath),
                icon: const Icon(Icons.arrow_upward),
              ),
              Expanded(
                child: Text(
                  _path.isEmpty
                      ? '/'
                      : '/${Uri.parse(_path).pathSegments.join('/')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: FutureBuilder<List<WebDavDirectory>>(
              future: _listing,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('无法读取此目录，请检查连接和权限'),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => _open(_path),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  );
                }
                final directories = snapshot.data ?? const <WebDavDirectory>[];
                if (directories.isEmpty) {
                  return const Center(child: Text('没有子目录，可选择当前目录'));
                }
                return ListView.builder(
                  itemCount: directories.length,
                  itemBuilder: (context, index) {
                    final folder = directories[index];
                    return ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(folder.name),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(folder.path),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _path),
        child: const Text('选择当前目录'),
      ),
    ],
  );
}
