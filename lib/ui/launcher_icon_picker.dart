import 'package:flutter/material.dart';

import '../services/launcher_icon_service.dart';

/// Uses installed Android aliases as the source of truth; preview is local.
class LauncherIconPicker extends StatefulWidget {
  const LauncherIconPicker({
    super.key,
    this.service = const LauncherIconService(),
  });

  final LauncherIconService service;

  @override
  State<LauncherIconPicker> createState() => _LauncherIconPickerState();
}

class _IconCopy {
  const _IconCopy(this.tag, this.story, [this.inspiration]);

  final String tag;
  final String story;
  final String? inspiration;
}

class _LauncherIconPickerState extends State<LauncherIconPicker> {
  static const _copy = <String, _IconCopy>{
    '微风与低音': _IconCopy('默认 · 自由之风', '风起之时，故事与旋律一起出发。', '《原神》· 微风与少年'),
    '高气压': _IconCopy('轻盈 · 音浪', '气压正在升高，下一阵音浪即将抵达。'),
    '春风拂面': _IconCopy('自然 · 春日', '春风有信，音符有期。'),
    '杨柳依依': _IconCopy('柔和 · 春意', '杨柳依依，旋律随风轻轻摇曳。'),
    '吹响！上低音号': _IconCopy('青春 · 合奏', '四季流转，我们的合奏仍在继续。', '《吹响！上低音号》· 季节与音符'),
    '点阵白': _IconCopy('星舰 · 晨光', '三十三束火光，等待黎明点火。', 'Starship · 33 台猛禽发动机'),
    '点阵黑': _IconCopy('星舰 · 夜航', '三十三台引擎，向星海齐声轰鸣。', 'Starship · 33 台猛禽发动机'),
    '风精灵': _IconCopy('幻想 · 温柔', '有一位风精灵，悄悄住进了旋律里。', '《无职转生》· Sylphy'),
  };

  late Future<LauncherIconSelection> _selection = widget.service.load();
  String? _previewId;
  String? _changingId;
  bool _showInspiration = false;

  String _name(String label) => label
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('（默认）', '')
      .replaceAll('(默认)', '');

  _IconCopy _description(String label) =>
      _copy[_name(label)] ?? const _IconCopy('个性 · 自由', '为喜欢的音乐，选择喜欢的样子。');

  void _preview(String id) {
    if (_changingId != null) return;
    setState(() {
      _previewId = id;
      _showInspiration = false;
    });
  }

  Future<void> _apply(LauncherIconOption option) async {
    if (_changingId != null) return;
    setState(() => _changingId = option.id);
    try {
      await widget.service.select(option.id);
      final selection = await widget.service.load();
      if (selection.selected != option.id) throw StateError('系统未完成图标切换，请重试');
      if (!mounted) return;
      setState(() {
        _selection = Future.value(selection);
        _previewId = option.id;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已切换为 ${_name(option.label)}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('切换应用图标失败：$error')));
    } finally {
      if (mounted) setState(() => _changingId = null);
    }
  }

  Widget _iconImage(LauncherIconOption option, double size) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .22),
    child: Image.asset(
      option.preview,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(
        1,
        512,
      ),
      errorBuilder: (context, error, stackTrace) => SizedBox(
        width: size,
        height: size,
        child: const Icon(Icons.image_not_supported_outlined),
      ),
    ),
  );

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
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (data.options.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Text('当前安装版本没有可用图标。'),
        );
      }

      final active = data.options.firstWhere(
        (option) => option.id == data.selected,
        orElse: () => data.options.first,
      );
      final preview = data.options.firstWhere(
        (option) => option.id == _previewId,
        orElse: () => active,
      );
      final copy = _description(preview.label);
      final isActive = preview.id == active.id;
      final colors = Theme.of(context).colorScheme;
      final textTheme = Theme.of(context).textTheme;

      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 600
              ? 4
              : constraints.maxWidth >= 450
              ? 3
              : 2;
          final content = Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'MAKE IT YOURS',
                  style: textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.bold,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '风的形状',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '为音乐挑选一张面孔。\n每一阵风，都藏着一段小小的故事。',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: LinearGradient(
                      colors: [
                        colors.primary.withValues(alpha: .19),
                        colors.primary.withValues(alpha: .045),
                      ],
                    ),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: .28),
                    ),
                  ),
                  child: Row(
                    children: [
                      _iconImage(active, 76),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '桌面当前使用',
                              style: textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _name(active.label),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: colors.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '正在使用',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: colors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '选择一阵风',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${data.options.length} 款图标 · 点击预览',
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: data.options.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: 165,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (context, index) {
                    final option = data.options[index];
                    final selected = preview.id == option.id;
                    final current = active.id == option.id;
                    final info = _description(option.label);
                    return AnimatedContainer(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: selected
                            ? colors.primary.withValues(alpha: .12)
                            : colors.surfaceContainerLow,
                        border: Border.all(
                          width: selected ? 1.7 : 1,
                          color: selected
                              ? colors.primary
                              : colors.outlineVariant,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _changingId == null
                              ? () => _preview(option.id)
                              : null,
                          borderRadius: BorderRadius.circular(18),
                          child: Stack(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 16, 8, 9),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Center(child: _iconImage(option, 72)),
                                    const SizedBox(height: 10),
                                    Text(
                                      _name(option.label),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.labelLarge?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      info.tag,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.labelSmall?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (selected)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Icon(
                                    Icons.check_circle_rounded,
                                    size: 20,
                                    color: colors.primary,
                                  ),
                                ),
                              if (current)
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  child: Text(
                                    '使用中',
                                    style: textTheme.labelSmall?.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    border: Border.all(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A LITTLE STORY',
                        style: textTheme.labelSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _name(preview.label),
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        copy.story,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                      if (copy.inspiration != null) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => setState(
                            () => _showInspiration = !_showInspiration,
                          ),
                          icon: Icon(
                            _showInspiration
                                ? Icons.expand_less
                                : Icons.auto_awesome,
                            size: 16,
                          ),
                          label: Text(_showInspiration ? '收起彩蛋' : '发现灵感彩蛋'),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        if (_showInspiration)
                          Text(
                            copy.inspiration!,
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: SingleChildScrollView(child: content)),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(top: BorderSide(color: colors.outlineVariant)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: isActive || _changingId != null
                            ? null
                            : () => _apply(preview),
                        icon: _changingId != null
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                isActive
                                    ? Icons.check
                                    : Icons.app_shortcut_rounded,
                              ),
                        label: Text(
                          _changingId != null
                              ? '正在切换…'
                              : isActive
                              ? '当前已应用'
                              : '应用「${_name(preview.label)}」',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '仅更换桌面图标，不影响音乐与设置；桌面可能稍后刷新。',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
