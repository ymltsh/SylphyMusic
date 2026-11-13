import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../services/api_settings.dart';
import '../services/device_transfer_config.dart';
import 'device_transfer_page.dart';
import 'music_source_ui.dart';

/// Welcome, device transfer, source selection, then optional public APIs.
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

  Future<void> _receiveFromDevice() => _runSource(() async {
    final scope = await Navigator.of(context).push<TransferScope>(
      MaterialPageRoute(
        builder: (_) => DeviceTransferReceivePage(app: widget.app),
      ),
    );
    if (!mounted || scope == null) return;
    if (scope == TransferScope.all) {
      await _complete();
    } else {
      _go(3); // Only sources transferred; keep the API setup step.
    }
  });

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
      backgroundColor: _step <= 1 && theme.brightness == Brightness.light
          ? const Color(0xFFF7F9FE)
          : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              children: [
                if (_step > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '快速上手  ·  ${_step + 1}/4',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(value: (_step + 1) / 4),
                      ],
                    ),
                  ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: switch (_step) {
                      0 => _welcome(theme),
                      1 => _transferWelcome(theme, sourceBusy),
                      2 => _sources(theme, sourceBusy),
                      _ => _api(theme),
                    },
                  ),
                ),
                if (_step > 1)
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

  /// A spacious welcome composition inspired by the introductory mockup.
  /// All spacing is flexible so the same page fits small phones and desktops.
  Widget _welcome(ThemeData theme) => LayoutBuilder(
    key: const ValueKey('quick-start-welcome'),
    builder: (context, constraints) {
      final compact = constraints.maxHeight < 700;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const Spacer(flex: 8),
            Icon(
              Icons.air_rounded,
              size: compact ? 76 : 92,
              color: theme.colorScheme.primary,
            ),
            SizedBox(height: compact ? 16 : 20),
            Text(
              '让音乐，轻盈相随',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: compact ? 24 : 28,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: theme.colorScheme.onSurface,
              ),
            ),
            SizedBox(height: compact ? 18 : 24),
            Text(
              '欢迎使用风灵音乐！\n'
              '连接你的私人音乐库，享受纯净听歌\n'
              '体验，离线也能自在聆听。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: compact ? 13 : 14,
                height: 1.5,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const Spacer(flex: 7),
            IconButton.filled(
              key: const ValueKey('quick-start-next'),
              tooltip: '开始使用',
              onPressed: _saving ? null : () => _go(1),
              style: IconButton.styleFrom(
                fixedSize: Size.square(compact ? 70 : 76),
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 38),
            ),
            const Spacer(flex: 5),
          ],
        ),
      );
    },
  );

  Widget _transferWelcome(ThemeData theme, bool busy) => LayoutBuilder(
    key: const ValueKey('quick-start-transfer'),
    builder: (context, constraints) {
      final colors = theme.colorScheme;
      final compact = constraints.maxHeight < 700;
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '返回欢迎页',
                      onPressed: busy ? null : () => _go(0),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const Spacer(),
                    Text(
                      '02 / 04',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      _transferIllustration(theme, compact ? 168 : 208),
                      const SizedBox(height: 24),
                      Text(
                        '熟悉的一切，\n随音乐一起抵达',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontSize: compact ? 26 : 30,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '从旧设备接过你的音乐源、API 与自定义外观。\n'
                        '少一些重新设置，多一些即刻熟悉。',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.7,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 16,
                        runSpacing: 10,
                        children: [
                          _transferHint(theme, Icons.wifi_rounded, '同一局域网'),
                          _transferHint(
                            theme,
                            Icons.lock_outline_rounded,
                            '配对加密',
                          ),
                          _transferHint(theme, Icons.tune_rounded, '仅迁移配置'),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('quick-start-receive'),
                      onPressed: busy ? null : _receiveFromDevice,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('从旧设备迁移'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: busy ? null : () => _go(2),
                      child: const Text('首次使用，手动设置'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '在旧设备打开「设置 → 设备间快速迁移 → 发送」',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _transferHint(ThemeData theme, IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: theme.colorScheme.primary),
      const SizedBox(width: 5),
      Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );

  Widget _transferIllustration(ThemeData theme, double size) {
    final colors = theme.colorScheme;
    Widget device(IconData icon) => Container(
      width: size * .34,
      height: size * .44,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.primary.withValues(alpha: .18)),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: .08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, size: size * .21, color: colors.primary),
    );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  colors.primary.withValues(alpha: .12),
                  colors.primary.withValues(alpha: .02),
                ],
              ),
              border: Border.all(color: colors.primary.withValues(alpha: .08)),
            ),
          ),
          Container(
            width: size * .72,
            height: size * .72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.primary.withValues(alpha: .12)),
            ),
          ),
          Positioned(
            left: size * .04,
            top: size * .2,
            child: Transform.rotate(
              angle: -.12,
              child: device(Icons.phonelink_rounded),
            ),
          ),
          Positioned(
            right: size * .04,
            bottom: size * .14,
            child: Transform.rotate(
              angle: .1,
              child: device(Icons.phone_android_rounded),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.arrow_forward_rounded,
              color: colors.onPrimary,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

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
    if (_step == 2) {
      return Row(
        children: [
          OutlinedButton(
            onPressed: busy ? null : () => _go(1),
            child: const Text('上一步'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: busy ? null : () => _go(3),
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
              onPressed: busy ? null : () => _go(2),
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
