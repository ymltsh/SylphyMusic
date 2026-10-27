import 'package:flutter/material.dart';

import '../core/appearance.dart';

class ThemeColorDialog extends StatefulWidget {
  const ThemeColorDialog({super.key, required this.initial});
  final Color initial;
  @override
  State<ThemeColorDialog> createState() => _ThemeColorDialogState();
}

class _ThemeColorDialogState extends State<ThemeColorDialog> {
  static String hex(Color color) =>
      '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  late final input = TextEditingController(text: hex(widget.initial));
  String? error;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('选择主题颜色'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in const [
                Appearance.defaultSeed,
                Color(0xff528a81),
                Color(0xff4e7ac7),
                Color(0xff8865b2),
                Color(0xffbd657a),
                Color(0xffb77a42),
                Color(0xff6b797d),
              ])
                IconButton.filled(
                  tooltip: hex(color),
                  style: IconButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => setState(() {
                    input.text = hex(color);
                    error = null;
                  }),
                  icon: Icon(
                    input.text.toUpperCase() == hex(color)
                        ? Icons.check
                        : Icons.circle_outlined,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: input,
            maxLength: 7,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: '自定义颜色',
              hintText: '#5094B2',
              errorText: error,
            ),
            onChanged: (_) => setState(() => error = null),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, Appearance.defaultSeed),
        child: const Text('恢复默认'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          final value = input.text.trim();
          if (!RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(value)) {
            setState(() => error = '请输入 6 位十六进制颜色');
            return;
          }
          Navigator.pop(
            context,
            Color(
              0xff000000 | int.parse(value.replaceFirst('#', ''), radix: 16),
            ),
          );
        },
        child: const Text('应用'),
      ),
    ],
  );
}
