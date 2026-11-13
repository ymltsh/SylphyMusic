import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_transfer_diagnostics.dart';
import '../services/device_transfer_transport.dart';

class DeviceTransferTroubleshootingPage extends StatefulWidget {
  const DeviceTransferTroubleshootingPage({
    super.key,
    required this.receiver,
    required this.stage,
  });

  final TransferReceiver? Function() receiver;
  final String Function() stage;

  @override
  State<DeviceTransferTroubleshootingPage> createState() =>
      _DeviceTransferTroubleshootingState();
}

class _DeviceTransferTroubleshootingState
    extends State<DeviceTransferTroubleshootingPage> {
  List<TransferNetworkAddress> _addresses = [];
  String? _networkError;
  bool _refreshing = false;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final addresses = await DeviceTransferDiagnostics.localAddresses();
      if (!mounted) return;
      setState(() {
        _addresses = addresses;
        _networkError = null;
      });
    } catch (_) {
      if (mounted) setState(() => _networkError = '无法读取本机网络接口，请检查网络连接后刷新。');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _act(Future<void> Function() action, String success) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await action();
      if (mounted) _message(success);
    } catch (error) {
      if (mounted) _message('$error');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), duration: const Duration(seconds: 7)),
  );

  String get _stageLabel => switch (widget.stage()) {
    'starting' => '正在启动接收',
    'waiting' => '等待旧设备连接',
    'connecting' => '正在建立安全连接',
    'pairing' => '等待核对配对码',
    'review' => '等待确认导入',
    'working' => '正在迁移',
    'done' => '迁移完成',
    'error' => '接收发生错误',
    _ => '尚未启动',
  };

  Widget _card(IconData icon, String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final receiver = widget.receiver();
    final tcp = receiver?.listeningPort;
    final canRestart = {'waiting', 'error'}.contains(widget.stage());
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('故障排除')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('连接遇到问题？', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text('先查看本机接收状态，再按遇到的情况逐项检查。此页面只读取本机网络信息，不会向其他设备发送探测请求。'),
              const SizedBox(height: 24),
              _card(Icons.network_check_rounded, '本机接收状态', [
                SelectableText(
                  '设备名称：${receiver?.name ?? '尚未生成'}\n'
                  '当前状态：$_stageLabel\n'
                  '设备发现：${receiver?.discoveryListening == true ? 'UDP $transferDiscoveryPort 已监听' : '未监听'}\n'
                  '配置接收：${tcp == null ? '未监听' : 'TCP $tcp 已监听（临时端口）'}\n'
                  '连接占用：${receiver?.occupied == true ? '已接入一台设备' : '无'}',
                ),
                const SizedBox(height: 12),
                if (_refreshing)
                  const LinearProgressIndicator()
                else if (_networkError != null)
                  Text(_networkError!)
                else if (_addresses.isEmpty)
                  const Text('未找到可用于迁移的局域网 IPv4 地址。请连接 Wi-Fi 或有线局域网后刷新。')
                else ...[
                  const Text('局域网 IPv4 地址'),
                  const SizedBox(height: 6),
                  for (final item in _addresses)
                    SelectableText('${item.interfaceName} · ${item.address}'),
                ],
                const SizedBox(height: 12),
                Text(
                  '监听成功仅表示接收服务已启动，不能据此判断防火墙或两台设备之间的网络是否畅通。',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _refreshing ? null : _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('刷新本机信息'),
                  ),
                ),
              ]),
              if (Platform.isWindows)
                _card(Icons.shield_outlined, '其他设备无法发现或连接这台电脑', [
                  const Text(
                    'Windows 防火墙可能阻止了传入连接。发现设备使用 UDP 43872，接收配置使用临时 TCP 端口。请允许当前风灵音乐程序在可信的专用网络中接收连接。',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '自动修复会申请管理员权限，添加或更新两条专属于本应用的规则，只允许专用网络中的本地子网访问。TCP 规则按程序放行，以适配每次接收的临时端口。',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: _acting
                            ? null
                            : () => _act(
                                DeviceTransferDiagnostics.repairWindowsFirewall,
                                '防火墙规则已更新。请返回接收页，让旧设备重新扫描；仍需确认网络互通。',
                              ),
                        icon: const Icon(Icons.build_outlined),
                        label: Text(_acting ? '正在处理…' : '自动修复'),
                      ),
                      OutlinedButton(
                        onPressed: _acting
                            ? null
                            : () => _act(
                                DeviceTransferDiagnostics.openWindowsFirewall,
                                '已请求打开 Windows 防火墙。',
                              ),
                        child: const Text('打开防火墙'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '若当前网络被设为公用网络，请先在 Windows 设置中确认它是你信任的家庭或工作网络，再改为专用网络。规则更新成功不等于连接已恢复。',
                  ),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('手动修复命令'),
                    subtitle: const Text('在管理员命令提示符中执行'),
                    children: [
                      SelectableText(
                        DeviceTransferDiagnostics.windowsFirewallCommands,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _act(
                            () => Clipboard.setData(
                              ClipboardData(
                                text: DeviceTransferDiagnostics
                                    .windowsFirewallCommands,
                              ),
                            ),
                            '已复制防火墙命令。',
                          ),
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('复制命令'),
                        ),
                      ),
                    ],
                  ),
                ]),
              _card(Icons.wifi_find_rounded, '旧设备的扫描列表里找不到本机', [
                const Text(
                  '1. 两台设备连接同一个可互通的 Wi-Fi 或有线局域网，并保持接收页面打开。\n\n'
                  '2. 访客 Wi-Fi、AP 隔离或不同 VLAN 可能阻断广播。可换到同一个普通局域网重试；连接相同名称的 Wi-Fi 也不一定能互相访问。\n\n'
                  '3. 检查 VPN、代理或虚拟网卡是否改变了路由；可暂时断开后重新扫描。\n\n'
                  '4. 让旧设备返回发送入口再重新扫描。本版本使用 IPv4 广播发现，暂不支持输入 IP 手动连接。',
                ),
              ]),
              if (Platform.isAndroid)
                _card(Icons.phonelink_lock_rounded, '本地网络权限未允许', [
                  const Text(
                    '若系统要求本地网络权限，请允许风灵音乐访问。点击下方按钮重新请求；如果系统不再弹出询问，请到系统「设置 → 应用 → 风灵音乐 → 权限」检查，再返回重新开启接收。',
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: _acting
                          ? null
                          : () => _act(
                              requireTransferLanPermission,
                              '本地网络权限可用，请返回并重新开启接收。',
                            ),
                      child: const Text('重新请求本地网络权限'),
                    ),
                  ),
                ]),
              _card(Icons.link_off_rounded, '能发现设备，但连接或配对失败', [
                const Text(
                  '确认两端使用支持设备迁移的版本，并且没有另一台设备占用当前接收会话。核对本机的音符设备名，再逐位核对两端配对码。\n\n'
                  '若配对码不一致，请取消本次配对并重新连接。若等待超时或中途断开，请返回重新开启接收，再让旧设备重新扫描。',
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: canRestart
                        ? () => Navigator.pop(context, true)
                        : null,
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('返回并重新开启接收'),
                  ),
                ),
                if (!canRestart) const Text('正在连接、配对或导入时，请先返回接收页处理当前会话。'),
              ]),
              const Text('排障期间接收服务仍保持运行。返回后可继续配对；离开接收页面才会关闭接收服务。'),
            ],
          ),
        ),
      ),
    );
  }
}
