import 'package:flutter/material.dart';

import '../services/launcher_icon_service.dart';

/// Android only. The installed icon is stored by Android PackageManager, not
/// duplicated in SQLite or SharedPreferences.
class LauncherIconPicker extends StatefulWidget {
  const LauncherIconPicker({
    super.key,
    this.service = const LauncherIconService(),
  });

  final LauncherIconService service;

  @override
  State<LauncherIconPicker> createState() => _LauncherIconPickerState();
}

class _LauncherIconPickerState extends State<LauncherIconPicker> {
  late Future<LauncherIconSelection> _selection = widget.service.load();
  String? _changing;

  Future<void> _choose(String id, String label) async {
    if (_changing != null) return;
    setState(() => _changing = id);
    try {
      await widget.service.select(id);
      if (!mounted) return;
      setState(() => _selection = widget.service.load());
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已切换为$label，桌面图标可能需要片刻刷新')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('切换应用图标失败：$error')));
    } finally {
      if (mounted) setState(() => _changing = null);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<LauncherIconSelection>(
    future: _selection,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text('读取应用图标失败'),
          subtitle: Text('${snapshot.error}'),
          trailing: const Icon(Icons.refresh),
          onTap: () => setState(() => _selection = widget.service.load()),
        );
      }
      final data = snapshot.data;
      if (data == null) {
        return const ListTile(
          title: Text('正在读取图标…'),
          trailing: CircularProgressIndicator(),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('更换桌面上的应用启动图标，不影响音乐、缓存和设置。'),
          ),
          for (final option in data.options)
            ListTile(
              enabled: _changing == null,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Image.asset(
                  option.preview,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const SizedBox(
                    width: 52,
                    height: 52,
                    child: Icon(Icons.image_not_supported_outlined),
                  ),
                ),
              ),
              title: Text(option.label),
              subtitle: Text(option.id == data.selected ? '当前使用' : '点击切换'),
              selected: option.id == data.selected,
              trailing: _changing == option.id
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      option.id == data.selected
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: option.id == data.selected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
              onTap: option.id == data.selected
                  ? null
                  : () => _choose(option.id, option.label),
            ),
          if (data.options.length == 1)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Text(
                '尚未导入其他图标，请将 PNG 放入 assets/launcher_icons/ 并运行图标生成脚本后重新安装。',
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text('部分桌面启动器可能延迟刷新；已固定的桌面快捷方式可能需要重新添加。'),
          ),
        ],
      );
    },
  );
}
