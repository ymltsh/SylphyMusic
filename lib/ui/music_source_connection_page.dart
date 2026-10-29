import 'package:flutter/material.dart';

import '../core/models.dart';
import 'music_source_ui.dart';

/// The form collects data; the shell remains responsible for authentication.
class MusicSourceConnectionDraft {
  const MusicSourceConnectionDraft({
    required this.kind,
    required this.name,
    required this.url,
    required this.username,
    required this.password,
  });

  final SourceKind kind;
  final String name;
  final String url;
  final String username;
  final String password;
}

class MusicSourceConnectionPage extends StatefulWidget {
  const MusicSourceConnectionPage({
    super.key,
    this.initialKind = SourceKind.emby,
    this.source,
  });

  final SourceKind initialKind;
  final SourceProfile? source;

  @override
  State<MusicSourceConnectionPage> createState() =>
      _MusicSourceConnectionPageState();
}

class _MusicSourceConnectionPageState extends State<MusicSourceConnectionPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _user;
  late final TextEditingController _password;
  late SourceKind _kind;
  bool _obscurePassword = true;

  bool get _editing => widget.source != null;

  @override
  void initState() {
    super.initState();
    final source = widget.source;
    _kind = source?.kind ?? widget.initialKind;
    _name = TextEditingController(text: source?.name ?? '');
    _host = TextEditingController(text: source?.url ?? '');
    _port = TextEditingController();
    _user = TextEditingController(text: source?.username ?? '');
    _password = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '请填写此项' : null;

  String? _validHost(String? value) {
    final text = value?.trim() ?? '';
    final uri = Uri.tryParse(text);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return '请输入 http:// 或 https:// 开头的服务器地址';
    }
    return null;
  }

  String? _validPort(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final port = int.tryParse(value.trim());
    return port != null && port >= 1 && port <= 65535 ? null : '端口必须为 1–65535';
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final uri = Uri.parse(_host.text.trim());
    final overridePort = int.tryParse(_port.text.trim());
    final url = overridePort == null
        ? _host.text.trim()
        : uri.replace(port: overridePort).toString();
    if (_kind == SourceKind.fnMusic &&
        !Uri.parse(url).path
            .replaceAll(RegExp(r'/+$'), '')
            .endsWith('/music')) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('飞牛音乐地址需要以 /music 结尾')));
      return;
    }
    Navigator.of(context).pop(
      MusicSourceConnectionDraft(
        kind: _kind,
        name: _name.text.trim(),
        url: url,
        username: _user.text.trim(),
        password: _password.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? '编辑音乐源' : '添加音乐源')),
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Text('连接类型', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  if (_editing)
                    Card.filled(
                      child: ListTile(
                        leading: MusicSourceIcon(kind: _kind),
                        title: Text(sourceOptionFor(_kind).title),
                        subtitle: const Text('现有连接的类型不可修改'),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: musicSourceOptions
                          .where((option) => option.kind != SourceKind.local)
                          .map(
                            (option) => ChoiceChip(
                              selected: _kind == option.kind,
                              avatar: Icon(option.icon, size: 18),
                              label: Text(option.title),
                              onSelected: (_) =>
                                  setState(() => _kind = option.kind),
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 22),
                  Text('服务器信息', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('source-name'),
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '名称',
                      prefixIcon: Icon(Icons.drive_file_rename_outline),
                      hintText: '例如：我的音乐库',
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('source-host'),
                    controller: _host,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: '服务器地址',
                      prefixIcon: const Icon(Icons.dns_outlined),
                      hintText: _kind == SourceKind.fnMusic
                          ? 'https://nas.example.com:5001/music'
                          : 'https://music.example.com/path',
                      helperText: _kind == SourceKind.fnMusic
                          ? '填写飞牛音乐入口，地址以 /music 结尾'
                          : '可包含反向代理路径；请尽量使用 HTTPS',
                    ),
                    validator: _validHost,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('source-port'),
                    controller: _port,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '端口（可选）',
                      prefixIcon: Icon(Icons.numbers),
                      hintText: '不填写则使用地址中的端口',
                    ),
                    validator: _validPort,
                  ),
                  const SizedBox(height: 22),
                  Text('账户验证', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('source-user'),
                    controller: _user,
                    readOnly: _editing,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: '用户名',
                      prefixIcon: const Icon(Icons.person_outline),
                      helperText: _editing ? '为保护原有曲库身份，账号不可修改' : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('source-password'),
                    controller: _password,
                    obscureText: _obscurePassword,
                    onFieldSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      labelText: _editing ? '密码（重新验证）' : '密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_kind == SourceKind.fnMusic)
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.info_outline),
                      title: Text('飞牛音乐账号'),
                      subtitle: Text(
                        '使用飞牛「音乐」里创建的独立账号；首期支持曲库、播放、封面和歌词，暂不支持云歌单写入与 FN Connect 自动寻址。',
                      ),
                    ),
                  if (_kind == SourceKind.webdav)
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.info_outline),
                      title: Text('WebDAV 说明'),
                      subtitle: Text('递归读取音乐目录，支持同名歌词文件与文件夹封面；云端歌单为只读。'),
                    ),
                  if (_editing &&
                      _kind != SourceKind.emby &&
                      _kind != SourceKind.fnMusic)
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.shield_outlined),
                      subtitle: Text('该协议无法验证服务器稳定身份。需要更换服务器地址时，请新增来源。'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: Icon(_editing ? Icons.check : Icons.add_link),
                  label: Text(_editing ? '验证并保存' : '连接并同步'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
