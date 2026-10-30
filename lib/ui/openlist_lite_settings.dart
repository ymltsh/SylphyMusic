import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/openlist_lite.dart';

class OpenListLiteSettingsPage extends StatefulWidget {
  const OpenListLiteSettingsPage({super.key});

  @override
  State<OpenListLiteSettingsPage> createState() =>
      _OpenListLiteSettingsPageState();
}

class _OpenListLiteSettingsPageState extends State<OpenListLiteSettingsPage> {
  String _mode = 'smart';
  bool _running = false;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final status = await OpenListLite.status();
      if (!mounted) return;
      setState(() {
        _mode = status['mode'] == 'continuous' ? 'continuous' : 'smart';
        _running = status['running'] == true;
        _busy = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = '$e';
        });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      _error = '$e';
    }
    await _refresh();
    if (mounted && _error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_error!)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('OpenList Lite · 网盘管理')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.hub_outlined),
                title: const Text('内置 OpenList'),
                subtitle: Text(
                  _busy ? '检测中…' : (_running ? '正在运行 · 仅本机访问' : '已停止'),
                ),
                trailing: IconButton(
                  onPressed: _busy ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新状态',
                ),
              ),
              const Divider(height: 1),
              RadioListTile<String>(
                title: const Text('智能运行（推荐）'),
                subtitle: const Text('需要时启动，空闲约 3 分钟后自动停止'),
                value: 'smart',
                groupValue: _mode,
                onChanged: _busy
                    ? null
                    : (_) => _run(() => OpenListLite.setMode('smart')),
              ),
              RadioListTile<String>(
                title: const Text('持续运行'),
                subtitle: const Text('用户主动保持本地服务；受 Android 后台限制，不保证永久存活'),
                value: 'continuous',
                groupValue: _mode,
                onChanged: _busy
                    ? null
                    : (_) => _run(() => OpenListLite.setMode('continuous')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : () => _run(OpenListLite.openUi),
          icon: const Icon(Icons.open_in_browser),
          label: const Text('打开 OpenList 原生 Web UI'),
        ),
        const SizedBox(height: 12),
        ListTile(
          title: const Text('内置 WebDAV 地址'),
          subtitle: const Text(OpenListLite.webDavUrl),
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制地址',
            onPressed: () => Clipboard.setData(
              const ClipboardData(text: OpenListLite.webDavUrl),
            ),
          ),
        ),
        ListTile(
          title: const Text('查看初始管理员密码'),
          subtitle: const Text('首次管理网盘时使用；建议在 Web UI 中设置只读音乐账号'),
          trailing: const Icon(Icons.lock_outline),
          onTap: _busy
              ? null
              : () => _run(() async {
                  final password = await OpenListLite.adminPassword();
                  if (!mounted) return;
                  await showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('本地 OpenList 管理员凭据'),
                      content: SelectableText('用户名：admin\n密码：$password'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  );
                }),
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            '在 Web UI 中添加网盘后，返回“音乐源管理”，添加 WebDAV 来源，填写上面的地址及具有读取权限的 OpenList 账号。'
            '完整 Web UI 和驱动由内置 OpenList 提供。此模式只监听 127.0.0.1，不开放局域网访问。',
          ),
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
}
