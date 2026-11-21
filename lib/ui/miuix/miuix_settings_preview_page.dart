import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// Stage-1 real widget preview. Regular settings retain their M3 layout until
/// shared settings actions are separated in the next migration phase.
class MiuixSettingsPreviewPage extends StatefulWidget {
  const MiuixSettingsPreviewPage({super.key});

  @override
  State<MiuixSettingsPreviewPage> createState() =>
      _MiuixSettingsPreviewPageState();
}

class _MiuixSettingsPreviewPageState extends State<MiuixSettingsPreviewPage> {
  bool enabled = true;

  @override
  Widget build(BuildContext context) => MiuixScaffold(
    topBar: MiuixTopAppBar(
      title: 'Miuix 组件预览',
      navigationIcon: IconButton(
        tooltip: '返回',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ),
    content: (padding) => ListView(
      padding: padding.add(const EdgeInsets.fromLTRB(16, 12, 16, 20)),
      children: [
        const MiuixCard(
          insideMargin: EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MiuixText('风灵音乐 · HyperOS 风格'),
              SizedBox(height: 8),
              MiuixText('实验性预览，不改变播放、歌单或布局配置。'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        MiuixCard(
          child: Column(
            children: [
              MiuixSwitchPreference(
                title: '示例开关',
                summary: '仅改变此页的临时状态',
                value: enabled,
                onChanged: (value) => setState(() => enabled = value),
              ),
              MiuixArrowPreference(
                title: '返回主题与背景',
                summary: '保留已选择的界面风格',
                onClick: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
