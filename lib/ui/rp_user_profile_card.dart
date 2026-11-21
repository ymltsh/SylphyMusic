import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../data/rp_user_profile_repository.dart';

class RpUserProfileCard extends StatefulWidget {
  const RpUserProfileCard({super.key, required this.app});

  final SylphyApp app;

  @override
  State<RpUserProfileCard> createState() => _RpUserProfileCardState();
}

class _RpUserProfileCardState extends State<RpUserProfileCard> {
  late Future<RpUserProfile> _profile = widget.app.userProfile.read();
  bool _editing = false;

  Future<void> _edit(RpUserProfile profile) async {
    if (_editing) return;
    _editing = true;
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => _RpUserProfileDialog(
          repository: widget.app.userProfile,
          profile: profile,
        ),
      );
      if (saved == true && mounted) _reload();
    } finally {
      _editing = false;
    }
  }

  void _reload() => setState(() => _profile = widget.app.userProfile.read());

  @override
  Widget build(BuildContext context) => FutureBuilder<RpUserProfile>(
    future: _profile,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Card(
          child: ListTile(
            title: const Text('你的资料'),
            subtitle: const Text('读取失败，点击重试'),
            onTap: _reload,
          ),
        );
      }
      final profile = snapshot.data;
      final edit =
          profile == null || snapshot.connectionState != ConnectionState.done
          ? null
          : () => _edit(profile);
      return Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('你的资料'),
              subtitle: const Text('所有音乐笔友共用，由你编辑'),
              trailing: IconButton(
                tooltip: '编辑个人资料',
                onPressed: edit,
                icon: const Icon(Icons.edit_outlined),
              ),
              onTap: edit,
            ),
            if (profile == null)
              const LinearProgressIndicator()
            else ...[
              ListTile(
                title: const Text('希望笔友怎么称呼你？'),
                subtitle: Text(
                  profile.preferredName.isEmpty
                      ? '尚未填写'
                      : profile.preferredName,
                ),
                onTap: edit,
              ),
              ListTile(
                title: const Text('个人简介'),
                subtitle: Text(
                  profile.biography.isEmpty ? '尚未填写' : profile.biography,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: edit,
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _RpUserProfileDialog extends StatefulWidget {
  const _RpUserProfileDialog({required this.repository, required this.profile});

  final RpUserProfileRepository repository;
  final RpUserProfile profile;

  @override
  State<_RpUserProfileDialog> createState() => _RpUserProfileDialogState();
}

class _RpUserProfileDialogState extends State<_RpUserProfileDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.preferredName);
  late final _biography = TextEditingController(text: widget.profile.biography);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _biography.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.save(
        preferredName: _name.text,
        biography: _biography.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '资料保存失败，请稍后重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('你的资料'),
      scrollable: true,
      content: SizedBox(
        width: 430,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '开启模型增强后，聊天和新推荐会将已填写的资料发送给所配置的模型。'
                '关闭记忆召回后依然如此。清空字段并保存后，后续请求会省略该字段。',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                readOnly: _saving,
                maxLength: RpUserProfileRepository.nameLimit,
                validator: RpUserProfileRepository.validateName,
                decoration: const InputDecoration(
                  labelText: '希望笔友怎么称呼你？',
                  helperText: '可以留空',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _biography,
                readOnly: _saving,
                minLines: 3,
                maxLines: 6,
                maxLength: RpUserProfileRepository.biographyLimit,
                validator: RpUserProfileRepository.validateBiography,
                decoration: const InputDecoration(
                  labelText: '个人简介',
                  hintText: '简单介绍自己、兴趣或交流偏好',
                  alignLabelWithHint: true,
                ),
              ),
              if (_error case final message?)
                Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '正在保存…' : '保存'),
        ),
      ],
    ),
  );
}
