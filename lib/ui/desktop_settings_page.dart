import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_controller.dart';
import '../services/desktop_fonts.dart';

class DesktopSettingsPage extends StatefulWidget {
  const DesktopSettingsPage({super.key, required this.app});
  final SylphyApp app;
  @override
  State<DesktopSettingsPage> createState() => _DesktopSettingsPageState();
}

class _DesktopSettingsPageState extends State<DesktopSettingsPage> {
  bool _busy = false;
  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('设置未完成：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _group(String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final prefs = widget.app.desktopPreferences;
    return Scaffold(
      appBar: AppBar(title: const Text('横屏与 PC')),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListenableBuilder(
              listenable: prefs,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [
                  _group('横屏迷你播放器', [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '宽屏集中显示歌曲、播放控制和进度；空间不足时切换为单行极简底栏，其他操作可在更多菜单中使用。',
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('显示应用内音量'),
                      subtitle: const Text('直接调整播放器音量，不改变系统音量'),
                      value: prefs.showVolume,
                      onChanged: _busy
                          ? null
                          : (v) => _act(() => prefs.update(volume: v)),
                    ),
                    SwitchListTile(
                      title: const Text('显示收藏快捷按钮'),
                      subtitle: const Text('在宽屏歌曲信息旁显示；更多菜单中始终可用'),
                      value: prefs.showExtraControls,
                      onChanged: _busy
                          ? null
                          : (v) => _act(() => prefs.update(extraControls: v)),
                    ),
                  ]),
                  _group('键盘快捷键', [
                    SwitchListTile(
                      title: const Text('启用应用内快捷键'),
                      subtitle: const Text('Windows 或横屏连接键盘时可用；输入文字和操作弹窗时不触发'),
                      value: prefs.shortcutsEnabled,
                      onChanged: _busy
                          ? null
                          : (v) => _act(() => prefs.update(shortcuts: v)),
                    ),
                    for (final row in const [
                      ('空格', '播放 / 暂停'),
                      ('Ctrl + ← / →', '上一首 / 下一首'),
                      ('← / →', '后退 / 前进 5 秒'),
                      ('Ctrl + ↑ / ↓', '音量增加 / 减少 5%'),
                      ('M', '静音 / 恢复音量'),
                      ('Ctrl + L', '打开播放队列'),
                    ])
                      ListTile(
                        dense: true,
                        title: Text(row.$2),
                        trailing: Text(row.$1),
                      ),
                  ]),
                  _group('Windows 字体', [
                    if (Platform.isWindows) ...[
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          '可选官方字体：点击后从厂商官网下载并使用，首次下载需要联网。'
                          '字体适用各自的独立许可，不属于本项目的 MIT 授权；选择下载即表示你已阅读并接受对应许可。',
                        ),
                      ),
                      for (final font in DesktopFont.values)
                        ListTile(
                          leading: Icon(
                            prefs.fontLabel == font.label
                                ? Icons.check_circle
                                : Icons.cloud_download_outlined,
                          ),
                          title: Text(font.label),
                          subtitle: Text(
                            '${font.description} · ${font.size}\n'
                            '${prefs.fontLabel == font.label ? "正在使用" : "下载并使用"} · 厂商独立许可',
                          ),
                          isThreeLine: true,
                          onTap: _busy || prefs.fontLabel == font.label
                              ? null
                              : () => _act(() => prefs.downloadFont(font)),
                          trailing: IconButton(
                            tooltip: '${font.label} 官网与许可',
                            icon: const Icon(Icons.open_in_new),
                            onPressed: () => _act(() async {
                              if (!await launchUrl(
                                Uri.parse(font.licenseUrl),
                                mode: LaunchMode.externalApplication,
                              )) {
                                throw StateError('无法打开官方许可页面');
                              }
                            }),
                          ),
                        ),
                      if (prefs.downloadingFont != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              LinearProgressIndicator(
                                value: prefs.downloadProgress,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${prefs.downloadStatus}'
                                      '${prefs.downloadProgress == null ? "" : " · ${(prefs.downloadProgress! * 100).floor()}%"}',
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: prefs.cancelFontDownload,
                                    child: const Text('取消'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.font_download_outlined),
                        title: const Text('导入本地字体'),
                        subtitle: Text(prefs.fontLabel),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _busy ? null : () => _act(prefs.pickFont),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '选择本机 TTF 或 OTF 字体，应用内立即生效并记住选择；建议选择包含中文的字体。',
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '风灵音乐 · 让音乐随心而行\nSylphy Music 0123456789',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton(
                            onPressed: _busy || prefs.fontFamily == null
                                ? null
                                : () => _act(prefs.resetFont),
                            child: const Text('恢复系统默认字体'),
                          ),
                        ),
                      ),
                    ] else
                      const ListTile(
                        title: Text('仅 Windows 支持自定义字体'),
                        subtitle: Text('移动端继续使用系统字体'),
                      ),
                  ]),
                  if (_busy && prefs.downloadingFont == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
