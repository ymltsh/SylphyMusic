import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/openlist_lite.dart';

class OpenListLiteSettingsPage extends StatefulWidget {
  const OpenListLiteSettingsPage({super.key, required this.setEnabled});

  final Future<void> Function(bool) setEnabled;

  @override
  State<OpenListLiteSettingsPage> createState() =>
      _OpenListLiteSettingsPageState();
}

class _OpenListLiteSettingsPageState extends State<OpenListLiteSettingsPage> {
  String _mode = 'smart';
  bool _enabled = true;
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
        _enabled = status['enabled'] != false;
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
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
              SwitchListTile(
                title: const Text('启用 OpenList 服务'),
                subtitle: const Text('关闭后立即停止服务，扫描、播放和后台任务均不会自动启动'),
                value: _enabled,
                onChanged: _busy
                    ? null
                    : (value) => _run(() => widget.setEnabled(value)),
              ),
              const Divider(height: 1),
              RadioGroup<String>(
                groupValue: _mode,
                onChanged: (value) {
                  if (!_busy && _enabled && value != null) {
                    _run(() => OpenListLite.setMode(value));
                  }
                },
                child: Column(
                  children: [
                    RadioListTile<String>(
                      title: const Text('智能运行（推荐）'),
                      subtitle: const Text('需要时启动，空闲约 3 分钟后自动停止'),
                      value: 'smart',
                      enabled: !_busy && _enabled,
                    ),
                    RadioListTile<String>(
                      title: const Text('持续运行'),
                      subtitle: const Text('用户主动保持本地服务；受 Android 后台限制，不保证永久存活'),
                      value: 'continuous',
                      enabled: !_busy && _enabled,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy || !_enabled
              ? null
              : () => _run(OpenListLite.openUi),
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
          subtitle: const Text('使用 admin 管理网盘；若已修改密码，请使用修改后的密码'),
          trailing: const Icon(Icons.lock_outline),
          onTap: _busy
              ? null
              : () => _run(() async {
                  final password = await OpenListLite.adminPassword();
                  if (!context.mounted) return;
                  await showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('本地 OpenList 管理员凭据'),
                      content: SelectableText('用户名：admin\n密码：$password'),
                      actions: [
                        TextButton(
                          onPressed: () => Clipboard.setData(
                            const ClipboardData(text: 'admin'),
                          ),
                          child: const Text('复制账号'),
                        ),
                        TextButton(
                          onPressed: () =>
                              Clipboard.setData(ClipboardData(text: password)),
                          child: const Text('复制密码'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  );
                }),
        ),
        ListTile(
          title: const Text('预置 WebDAV 账号'),
          subtitle: const SelectableText(
            '账号：sylphy\n初始密码：sylphy\n权限：WebDAV 读取、管理',
          ),
          trailing: Wrap(
            children: [
              IconButton(
                tooltip: '复制账号',
                icon: const Icon(Icons.person_outline),
                onPressed: () => Clipboard.setData(
                  const ClipboardData(text: OpenListLite.webDavUsername),
                ),
              ),
              IconButton(
                tooltip: '复制初始密码',
                icon: const Icon(Icons.copy),
                onPressed: () => Clipboard.setData(
                  const ClipboardData(text: OpenListLite.webDavPassword),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            '使用 admin 在 Web UI 中添加网盘后，返回“音乐源管理”，选择 OpenList 并选择音乐目录即可。预置账号只在缺失时创建，已修改的密码或权限不会重置。'
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
