import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_updates.dart';
import 'settings_controls.dart';

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    super.key,
    required this.onCheck,
    this.mirror = AppUpdates.defaultMirror,
    this.openUrl = _launch,
  });

  final Future<UpdateCheck> Function({bool beta}) onCheck;
  final String mirror;
  final Future<bool> Function(Uri) openUrl;

  static Future<bool> _launch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _beta = false;
  late Future<UpdateCheck> _request = _checkChannel();
  String? _openError;

  Future<UpdateCheck> _checkChannel() =>
      Future.sync(() => widget.onCheck(beta: _beta));

  void _checkAgain({bool? beta}) {
    setState(() {
      _beta = beta ?? _beta;
      _openError = null;
      _request = _checkChannel();
    });
  }

  Future<void> _open(Uri uri) async {
    var opened = false;
    try {
      opened = await widget.openUrl(AppUpdates.accelerate(uri, widget.mirror));
    } catch (_) {
      // Present launcher and mirror errors in the same dialog.
    }
    if (!mounted) return;
    setState(() {
      _openError = opened ? null : '无法打开浏览器，请稍后重试';
    });
  }

  @override
  Widget build(BuildContext context) {
    final downloads = switch (defaultTargetPlatform) {
      TargetPlatform.android => const {
        'android': 'Android APK',
        'android_arm64': 'Android arm64',
        'android_armv7': 'Android 32 位',
        'android_x64': 'Android x86_64',
      },
      TargetPlatform.windows => const {
        'windows': 'Windows 安装程序',
        'windows_portable': 'Windows 便携版',
      },
      _ => const <String, String>{},
    };
    return FutureBuilder<UpdateCheck>(
      future: _request,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final failed = !loading && snapshot.hasError;
        final result = loading ? null : snapshot.data;
        final latest = result?.available == true ? result!.latest : null;
        final colors = Theme.of(context).colorScheme;

        return AlertDialog(
          title: Text(latest == null ? '检查更新' : '发现新版本：${latest.name}'),
          scrollable: true,
          content: SizedBox(
            width: 440,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('测试版更新'),
                  subtitle: const Text('测试版可能包含尚未稳定的功能'),
                  value: _beta,
                  onChanged: loading ? null : (beta) => _checkAgain(beta: beta),
                ),
                const SizedBox(height: 12),
                if (loading) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  const Text('正在检查…'),
                ] else if (failed)
                  const Text('检查更新失败，请检查网络后重试'),
                if (result != null) ...[
                  Text('当前版本 ${result.current}'),
                  const SizedBox(height: 8),
                  if (latest == null)
                    Text(result.latest == null ? '尚未发布可用版本' : '已是最新版本')
                  else ...[
                    Text(
                      latest.date.isEmpty
                          ? '新版本 ${latest.version}'
                          : '新版本 ${latest.version} · ${latest.date}',
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      latest.notes.isEmpty ? '此版本暂无更新说明' : latest.notes,
                    ),
                    const SizedBox(height: 16),
                    for (final entry in downloads.entries)
                      if (latest.urls[entry.key] case final uri?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton.icon(
                            onPressed: () => _open(uri),
                            icon: const SettingsIcon(Icons.download_outlined),
                            label: Text(entry.value),
                          ),
                        ),
                  ],
                ],
                if (_openError case final error?)
                  Text(error, style: TextStyle(color: colors.error)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(latest == null ? '关闭' : '稍后'),
            ),
            if (failed)
              FilledButton(onPressed: _checkAgain, child: const Text('重试')),
            if (latest != null)
              TextButton(
                onPressed: () => _open(latest.page),
                child: const Text('查看发布页'),
              ),
          ],
        );
      },
    );
  }
}
