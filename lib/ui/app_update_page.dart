import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_updates.dart';

class AppUpdatePage extends StatefulWidget {
  const AppUpdatePage({
    super.key,
    required this.onCheck,
    this.openUrl = _launch,
  });
  final Future<UpdateCheck> Function({bool beta}) onCheck;
  final Future<bool> Function(Uri) openUrl;
  static Future<bool> _launch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
  @override
  State<AppUpdatePage> createState() => _AppUpdatePageState();
}

class _AppUpdatePageState extends State<AppUpdatePage> {
  bool beta = false, loading = false;
  UpdateCheck? result;
  String? error;
  Future<void> _check() async {
    setState(() {
      loading = true;
      error = null;
      result = null;
    });
    try {
      final value = await widget.onCheck(beta: beta);
      if (mounted) setState(() => result = value);
    } catch (_) {
      if (mounted) setState(() => error = '检查更新失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _open(Uri uri) async {
    try {
      if (!await widget.openUrl(uri)) throw StateError('无法打开链接');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开浏览器，请稍后重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final latest = result?.latest;
    final available = result?.available ?? false;
    final platform = defaultTargetPlatform;
    final keys = platform == TargetPlatform.android
        ? const {
            'android': 'Android APK',
            'android_arm64': 'Android arm64',
            'android_armv7': 'Android 32 位',
            'android_x64': 'Android x86_64',
          }
        : platform == TargetPlatform.windows
        ? const {'windows': 'Windows 安装程序', 'windows_portable': 'Windows 便携版'}
        : const <String, String>{};
    return Scaffold(
      appBar: AppBar(title: const Text('检查更新')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Icon(Icons.system_update_alt, size: 48),
                const SizedBox(height: 16),
                Text(
                  '风灵音乐 · Sylphy Music',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text('仅在点击时检查更新，下载后由你手动安装。'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('测试版更新'),
                  subtitle: const Text('测试版可能包含尚未稳定的功能'),
                  value: beta,
                  onChanged: loading
                      ? null
                      : (value) => setState(() {
                          beta = value;
                          result = null;
                          error = null;
                        }),
                ),
                FilledButton.icon(
                  onPressed: loading ? null : _check,
                  icon: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(
                    loading
                        ? '正在检查…'
                        : error != null
                        ? '重试'
                        : '检查更新',
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Text(error!),
                  ),
                if (result != null) ...[
                  const SizedBox(height: 20),
                  Text('当前版本 ${result!.current}'),
                  const SizedBox(height: 12),
                  Text(
                    available
                        ? '发现新版本：${latest!.name}'
                        : latest == null
                        ? '尚未发布可用版本'
                        : '已是最新版本',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (available) ...[
                    Text('${latest!.version} · ${latest.date}'),
                    const SizedBox(height: 12),
                    SelectableText(
                      latest.notes.isEmpty ? '此版本暂无更新说明' : latest.notes,
                    ),
                    const SizedBox(height: 16),
                    for (final entry in keys.entries)
                      if (latest.urls.containsKey(entry.key))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton.icon(
                            onPressed: () => _open(latest.urls[entry.key]!),
                            icon: const Icon(Icons.download_outlined),
                            label: Text(entry.value),
                          ),
                        ),
                    TextButton(
                      onPressed: () => _open(latest.page),
                      child: const Text('查看发布页'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
