import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../services/api_settings.dart';
import 'music_source_ui.dart';

/// Three explicit steps: welcome, choose a source, configure public APIs.
class QuickStartWizard extends StatefulWidget {
  const QuickStartWizard({
    super.key,
    required this.app,
    required this.onConnect,
    required this.onImportFiles,
    required this.onImportFolder,
    required this.onFinish,
  });

  final SylphyApp app;
  final Future<void> Function(SourceKind) onConnect;
  final Future<void> Function() onImportFiles;
  final Future<void> Function() onImportFolder;
  final Future<void> Function() onFinish;

  @override
  State<QuickStartWizard> createState() => _QuickStartWizardState();
}

class _QuickStartWizardState extends State<QuickStartWizard> {
  int _step = 0;
  bool _sourceWorking = false;
  bool _saving = false;
  late final TextEditingController _quote;
  late final TextEditingController _mirror;
  final _apiForm = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _quote = TextEditingController(text: widget.app.apiSettings.quoteUrl);
    _mirror = TextEditingController(text: widget.app.apiSettings.githubMirror);
  }

  @override
  void dispose() {
    _quote.dispose();
    _mirror.dispose();
    super.dispose();
  }

  void _go(int step) => setState(() => _step = step);

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$error'), duration: const Duration(seconds: 6)),
    );
  }

  Future<void> _runSource(Future<void> Function() action) async {
    if (_sourceWorking || _saving || widget.app.busy) return;
    setState(() => _sourceWorking = true);
    try {
      await action();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _sourceWorking = false);
    }
  }

  Future<void> _localSource() async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.audio_file_outlined),
              title: const Text('导入本地音频文件'),
              onTap: () => Navigator.pop(context, 'files'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('添加本地音乐文件夹'),
              onTap: () => Navigator.pop(context, 'folder'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (selection == 'files') await _runSource(widget.onImportFiles);
    if (selection == 'folder') await _runSource(widget.onImportFolder);
  }

  Future<void> _complete({bool saveApi = false}) async {
    if (_saving) return;
    if (saveApi && !_apiForm.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (saveApi) {
        final settings = widget.app.apiSettings;
        // Validate both before persisting either, avoiding partial config changes.
        final quote = ApiSettings.validateQuoteUrl(_quote.text);
        final mirror = ApiSettings.validateGitHubMirror(_mirror.text);
        if (quote != settings.quoteUrl) await settings.setQuoteUrl(quote);
        if (mirror != settings.githubMirror) {
          await settings.setGitHubMirror(mirror);
        }
      }
      await widget.onFinish();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateQuote(String? value) {
    try {
      ApiSettings.validateQuoteUrl(value ?? '');
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String? _validateMirror(String? value) {
    try {
      ApiSettings.validateGitHubMirror(value ?? '');
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sourceBusy = _sourceWorking || _saving || widget.app.busy;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              children: [
                if (_step != 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '快速上手  ·  ${_step + 1}/3',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(value: (_step + 1) / 3),
                      ],
                    ),
                  ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: switch (_step) {
                      0 => _welcome(theme),
                      1 => _sources(theme, sourceBusy),
                      _ => _api(theme),
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: _buttons(_saving),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The first page intentionally has only the brand icon and slogan.
  Widget _welcome(ThemeData theme) => Center(
    key: const ValueKey('quick-start-welcome'),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.air_rounded, size: 92, color: theme.colorScheme.primary),
        const SizedBox(height: 24),
        Text(
          '让音乐，轻盈相随',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium,
        ),
      ],
    ),
  );

  Widget _sources(ThemeData theme, bool busy) => ListView(
    key: const ValueKey('quick-start-sources'),
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
    children: [
      Text('选择歌曲来源', style: theme.textTheme.headlineSmall),
      const SizedBox(height: 6),
      Text('选择一种来源连接，之后仍可添加多个音乐库。', style: theme.textTheme.bodyMedium),
      if (widget.app.busy)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('音乐库正在后台处理，可继续下一步。'),
        ),
      const SizedBox(height: 24),
      ...musicSourceOptions.map((option) {
        final connected = widget.app.sources.any((s) => s.kind == option.kind);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card.filled(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              leading: MusicSourceIcon(kind: option.kind, size: 52),
              title: Text(
                option.title,
                style: theme.textTheme.titleMedium,
                maxLines: 2,
              ),
              subtitle: Text(option.description),
              trailing: Icon(
                connected ? Icons.check_circle : Icons.chevron_right,
                color: connected ? theme.colorScheme.primary : null,
              ),
              enabled: !busy,
              onTap: busy
                  ? null
                  : () => option.kind == SourceKind.local
                        ? _localSource()
                        : _runSource(() => widget.onConnect(option.kind)),
            ),
          ),
        );
      }),
      if (widget.app.sources.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '已接入 ${widget.app.sources.length} 个音乐来源',
            style: theme.textTheme.bodySmall,
          ),
        ),
    ],
  );

  Widget _api(ThemeData theme) => Form(
    key: _apiForm,
    child: ListView(
      key: const ValueKey('quick-start-api'),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      children: [
        Text('API 配置', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text('可直接使用默认配置，稍后也能在设置中修改。', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 24),
        TextFormField(
          controller: _quote,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: '每日一言 API',
            prefixIcon: const Icon(Icons.format_quote_outlined),
            helperText: '留空恢复默认；需为 HTTPS JSON 接口',
            suffixIcon: IconButton(
              tooltip: '恢复默认每日一言 API',
              icon: const Icon(Icons.restart_alt),
              onPressed: () =>
                  setState(() => _quote.text = ApiSettings.defaultQuoteUrl),
            ),
          ),
          validator: _validateQuote,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _mirror,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'GitHub 加速 API',
            prefixIcon: const Icon(Icons.cloud_download_outlined),
            helperText: '用于更新检查及下载；留空恢复默认',
            suffixIcon: IconButton(
              tooltip: '恢复默认 GitHub 加速 API',
              icon: const Icon(Icons.restart_alt),
              onPressed: () => setState(
                () => _mirror.text = ApiSettings.defaultGitHubMirror,
              ),
            ),
          ),
          validator: _validateMirror,
        ),
        const SizedBox(height: 16),
        Text('API 配置与音乐服务器的登录凭据相互独立。', style: theme.textTheme.bodySmall),
      ],
    ),
  );

  Widget _buttons(bool busy) {
    if (_step == 0) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: busy ? null : () => _go(1),
          child: const Text('开始使用'),
        ),
      );
    }
    if (_step == 1) {
      return Row(
        children: [
          OutlinedButton(
            onPressed: busy ? null : () => _go(0),
            child: const Text('上一步'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: busy ? null : () => _go(2),
              child: const Text('下一步：API 配置'),
            ),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            OutlinedButton(
              onPressed: busy ? null : () => _go(1),
              child: const Text('上一步'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: busy ? null : () => _complete(saveApi: true),
                child: Text(busy ? '正在保存…' : '完成设置'),
              ),
            ),
          ],
        ),
        TextButton(
          onPressed: busy ? null : () => _complete(),
          child: const Text('跳过 API 配置'),
        ),
      ],
    );
  }
}
