import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../services/device_transfer_config.dart';
import '../services/device_transfer_transport.dart';
import 'device_transfer_troubleshooting_page.dart';

/// Entry from Settings. The receiver is also offered on the *second* welcome
/// page, so users do not need to configure a music source before transferring.
class DeviceTransferPage extends StatelessWidget {
  const DeviceTransferPage({super.key, required this.app});
  final SylphyApp app;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设备间快速迁移')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(
              Icons.devices_rounded,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              '让熟悉的音乐体验，轻松抵达新设备',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              '两台设备连接同一个可互通的局域网，不经过云端。'
              '仅迁移你手动填写的配置，不传歌曲、缓存或播放记录。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Card.filled(
              child: ListTile(
                leading: const Icon(Icons.radar_rounded),
                title: const Text('发送本机配置'),
                subtitle: const Text('扫描正在等待接收的另一台设备'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DeviceTransferSendPage(app: app),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card.filled(
              child: ListTile(
                leading: const Icon(Icons.download_for_offline_outlined),
                title: const Text('接收其他设备的配置'),
                subtitle: const Text('开启临时接收服务，让旧设备发现本机'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<TransferScope>(
                    builder: (_) => DeviceTransferReceivePage(app: app),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '配对时，请确认两台设备显示的 6 位数字完全一致。'
              '迁移成功后，可能需要重新授权部分服务器账号或重启应用。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class DeviceTransferSendPage extends StatefulWidget {
  const DeviceTransferSendPage({super.key, required this.app});
  final SylphyApp app;

  @override
  State<DeviceTransferSendPage> createState() => _SendState();
}

class _SendState extends State<DeviceTransferSendPage> {
  TransferScanner? _scanner;
  StreamSubscription<List<TransferDevice>>? _subscription;
  TransferSession? _session;
  Socket? _connectingSocket;
  List<TransferDevice> _found = [];
  TransferScope _scope = TransferScope.all;
  String _stage = 'scanning';
  String _message = '';
  String? _code;

  @override
  void initState() {
    super.initState();
    unawaited(_startScan());
  }

  Future<void> _startScan() async {
    try {
      await requireTransferLanPermission();
      if (!mounted) return;
      final scanner = TransferScanner();
      _scanner = scanner;
      _subscription = scanner.changes.listen((list) {
        if (mounted) setState(() => _found = list);
      });
      await scanner.start();
      if (!mounted) {
        await scanner.stop();
        return;
      }
      if (mounted) setState(() => _stage = 'scanning');
    } catch (e) {
      if (mounted)
        setState(() {
          _stage = 'error';
          _message = '扫描失败：$e';
        });
    }
  }

  Future<void> _select(TransferDevice device) async {
    if (_stage != 'scanning') return;
    setState(() => _stage = 'connecting');
    await _subscription?.cancel();
    await _scanner?.stop();
    try {
      final socket = await Socket.connect(
        device.address,
        device.port,
        timeout: const Duration(seconds: 10),
      );
      _connectingSocket = socket;
      if (!mounted) {
        socket.destroy();
        return;
      }
      final session = await TransferSession.connect(socket);
      _session = session;
      if (!mounted) {
        await session.close();
        return;
      }
      setState(() {
        _stage = 'pairing';
        _code = session.code;
        _message = device.label;
      });
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _approve() async {
    final session = _session;
    if (session == null || _stage != 'pairing') return;
    setState(() => _stage = 'working');
    try {
      await session.approve().timeout(const Duration(minutes: 2));
      if (!mounted) return;
      setState(() => _message = '正在整理并加密手动配置…');
      final bundle = await DeviceTransferConfig(widget.app).export(_scope);
      await session.send({'type': 'bundle', 'value': bundle.toJson()});
      if (!mounted) return;
      setState(() => _message = '等待新设备确认导入…');
      final result = await session
          .receive(maxBytes: 8192)
          .timeout(const Duration(minutes: 3));
      if (result['type'] != 'result' || result['success'] != true) {
        throw StateError(result['message'] ?? '新设备未能完成导入');
      }
      if (!mounted) return;
      setState(() {
        _stage = 'done';
        _message = '新设备已导入 ${result['created']} 个新音乐源。';
      });
    } catch (e) {
      _fail(e);
    } finally {
      await session.close();
    }
  }

  void _fail(Object error) {
    if (!mounted) return;
    setState(() {
      _stage = 'error';
      _message = '$error';
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_scanner?.stop());
    _connectingSocket?.destroy();
    unawaited(_session?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('发送配置')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_stage == 'scanning') ...[
              Text('搜索接收设备', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                '请在新设备上选择「接收其他设备的配置」。'
                '扫描只在本页面开启期间进行。',
              ),
              const SizedBox(height: 12),
              SegmentedButton<TransferScope>(
                segments: const [
                  ButtonSegment(
                    value: TransferScope.all,
                    label: Text('全部手动配置'),
                  ),
                  ButtonSegment(
                    value: TransferScope.sources,
                    label: Text('仅音乐源'),
                  ),
                ],
                selected: {_scope},
                onSelectionChanged: (value) =>
                    setState(() => _scope = value.first),
              ),
              RadarDisplay(devices: _found, onChoose: _select),
              if (_found.isEmpty)
                const Text(
                  '正在搜索… 请确保两台设备连接同一 Wi-Fi 或局域网，'
                  '并允许系统防火墙中的本地设备通信。',
                  textAlign: TextAlign.center,
                )
              else
                ..._found.map(
                  (device) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.devices_other_outlined),
                      title: Text(device.name),
                      subtitle: Text(device.address.address),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _select(device),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => setState(() => _found = []),
                icon: const Icon(Icons.refresh),
                label: const Text('继续搜索'),
              ),
            ] else if (_stage == 'pairing') ...[
              _pairCode(context, _code!, _message),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _approve,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('数字一致，允许发送'),
              ),
            ] else ...[
              const SizedBox(height: 48),
              Icon(
                _stage == 'done'
                    ? Icons.check_circle_outline
                    : _stage == 'error'
                    ? Icons.error_outline
                    : Icons.sync,
                size: 70,
                color: Theme.of(context).colorScheme.primary,
              ),
              if (_stage == 'connecting' || _stage == 'working')
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: LinearProgressIndicator(),
                ),
              const SizedBox(height: 20),
              Text(
                _message.isEmpty ? '正在建立安全连接…' : _message,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (_stage == 'done' || _stage == 'error')
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

class DeviceTransferReceivePage extends StatefulWidget {
  const DeviceTransferReceivePage({super.key, required this.app});
  final SylphyApp app;

  @override
  State<DeviceTransferReceivePage> createState() => _ReceiveState();
}

class _ReceiveState extends State<DeviceTransferReceivePage> {
  TransferReceiver? _receiver;
  TransferSession? _session;
  Completer<bool>? _pairApproval;
  Completer<bool>? _importApproval;
  String _stage = 'waiting';
  String _message = '准备接收设备…';
  String? _code;
  TransferBundle? _bundle;
  TransferPreview? _preview;
  bool _starting = true;

  @override
  void initState() {
    super.initState();
    unawaited(_listen());
  }

  Future<void> _listen() async {
    try {
      await requireTransferLanPermission();
      if (!mounted) return;
      final receiver = TransferReceiver(
        onSocket: (socket) {
          unawaited(_handle(socket));
        },
      );
      _receiver = receiver;
      await receiver.start();
      if (!mounted) {
        await receiver.stop();
        return;
      }
      if (mounted) setState(() => _message = '等待旧设备发现 ${receiver.name}…');
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _troubleshoot() async {
    final restart = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DeviceTransferTroubleshootingPage(
          receiver: () => _receiver,
          stage: () => _starting ? 'starting' : _stage,
        ),
      ),
    );
    if (!mounted || restart != true || _starting) return;
    if (!{'waiting', 'error'}.contains(_stage)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已有设备连接，请先处理当前会话。')));
      return;
    }
    setState(() {
      _starting = true;
      _stage = 'waiting';
      _message = '正在重新开启接收…';
    });
    try {
      await _session?.close();
      _session = null;
      await _receiver?.stop();
      _receiver = null;
      if (mounted) await _listen();
    } catch (error) {
      _fail(error);
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _handle(Socket socket) async {
    TransferSession? session;
    try {
      if (!mounted) {
        socket.destroy();
        return;
      }
      setState(() {
        _stage = 'connecting';
        _message = '正在建立安全会话…';
      });
      final connected = await TransferSession.accept(socket);
      session = connected;
      _session = connected;
      final approval = Completer<bool>();
      _pairApproval = approval;
      if (!mounted) return;
      setState(() {
        _stage = 'pairing';
        _code = connected.code;
      });
      final allowed = await approval.future.timeout(const Duration(minutes: 2));
      if (!allowed) throw StateError('已取消配对');
      if (!mounted) return;
      setState(() {
        _stage = 'working';
        _message = '正在等待加密配置…';
      });
      await connected.approve().timeout(const Duration(minutes: 2));
      final payload = await connected.receive().timeout(
        const Duration(minutes: 3),
      );
      if (payload['type'] != 'bundle' ||
          payload['value'] is! Map<String, dynamic>) {
        throw const FormatException('对方发送了无效迁移包');
      }
      final bundle = TransferBundle.parse(
        payload['value'] as Map<String, dynamic>,
      );
      final preview = await DeviceTransferConfig(widget.app).preview(bundle);
      final importApproval = Completer<bool>();
      _importApproval = importApproval;
      _bundle = bundle;
      _preview = preview;
      if (!mounted) return;
      setState(() => _stage = 'review');
      final accepted = await importApproval.future.timeout(
        const Duration(minutes: 3),
      );
      if (!accepted) throw StateError('用户取消了导入');
      if (!mounted) return;
      setState(() {
        _stage = 'working';
        _message = '正在保存配置及安全凭据…';
      });
      final count = await DeviceTransferConfig(widget.app).apply(bundle);
      try {
        await connected.send({
          'type': 'result',
          'success': true,
          'created': count,
        });
      } catch (_) {
        // Local import is already committed; a lost acknowledgement cannot
        // turn a successful import into a failed one.
      }
      if (!mounted) return;
      setState(() {
        _stage = 'done';
        _message = '成功导入 $count 个新音乐源。已有相同来源不会被覆盖。';
      });
    } catch (e) {
      if (session != null) {
        try {
          await session.send({
            'type': 'result',
            'success': false,
            'message': '接收设备导入失败',
          });
        } catch (_) {}
      }
      _fail(e);
    } finally {
      await session?.close();
    }
  }

  void _fail(Object error) {
    if (!mounted) return;
    setState(() {
      _stage = 'error';
      _message = '$error';
    });
  }

  @override
  void dispose() {
    if (_pairApproval?.isCompleted == false) _pairApproval?.complete(false);
    if (_importApproval?.isCompleted == false) _importApproval?.complete(false);
    unawaited(_session?.close());
    unawaited(_receiver?.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('接收配置'),
      actions: [
        IconButton(
          tooltip: '故障排除',
          onPressed: _troubleshoot,
          icon: const Icon(Icons.help_outline_rounded),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_stage == 'waiting') ...[
              Text('等待旧设备连接', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                '请在旧设备的「设置 → 设备间快速迁移」选择发送，'
                '再从扫描结果中找到本机。',
              ),
              const RadarDisplay(),
              Text(_message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: _troubleshoot,
                icon: const Icon(Icons.build_outlined),
                label: const Text('找不到本机？故障排除'),
              ),
            ] else if (_stage == 'pairing') ...[
              _pairCode(context, _code!, '请检查旧设备上的配对数字'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  if (_pairApproval?.isCompleted == false) {
                    _pairApproval?.complete(true);
                  }
                },
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('数字一致，允许接收'),
              ),
            ] else if (_stage == 'review') ...[
              Text(
                '确认即将导入的配置',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Card.filled(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.library_music_outlined),
                      title: Text('新增音乐源：${_preview!.newSources} 个'),
                      subtitle: Text(
                        '跳过已存在的相同来源：${_preview!.skippedSources} 个',
                      ),
                    ),
                    if (_bundle!.scope == TransferScope.all) ...[
                      ListTile(
                        leading: const Icon(Icons.tune),
                        title: Text('自定义设置与密钥：${_preview!.settingsCount} 项'),
                        subtitle: const Text('API 地址、外观和播放器布局等'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text('音乐笔友角色卡：${_preview!.cardCount} 张'),
                      ),
                    ],
                  ],
                ),
              ),
              const Text(
                '已有音乐源不会被覆盖；本地音乐、播放历史、缓存及开关不迁移。'
                '导入的新服务器连接可能需要在新设备重新验证。',
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  if (_importApproval?.isCompleted == false) {
                    _importApproval?.complete(true);
                  }
                },
                icon: const Icon(Icons.download_done),
                label: const Text('确认导入'),
              ),
            ] else ...[
              const SizedBox(height: 44),
              Icon(
                _stage == 'done'
                    ? Icons.check_circle_outline
                    : _stage == 'error'
                    ? Icons.error_outline
                    : Icons.sync,
                size: 76,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(_message, textAlign: TextAlign.center),
              if (_stage == 'working' || _stage == 'connecting')
                const Padding(
                  padding: EdgeInsets.all(28),
                  child: LinearProgressIndicator(),
                ),
              const SizedBox(height: 20),
              if (_stage == 'done')
                FilledButton(
                  onPressed: () => Navigator.pop(context, _bundle!.scope),
                  child: const Text('完成并继续'),
                ),
              if (_stage == 'error') ...[
                FilledButton.tonalIcon(
                  onPressed: _troubleshoot,
                  icon: const Icon(Icons.build_outlined),
                  label: const Text('故障排除'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('返回'),
                ),
              ],
            ],
          ],
        ),
      ),
    ),
  );
}

Widget _pairCode(BuildContext context, String code, String hint) => Column(
  children: [
    const SizedBox(height: 44),
    Icon(
      Icons.shield_outlined,
      size: 60,
      color: Theme.of(context).colorScheme.primary,
    ),
    const SizedBox(height: 16),
    Text(
      '确认两台设备上的数字完全一致',
      style: Theme.of(context).textTheme.titleMedium,
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 20),
    SelectableText(
      '${code.substring(0, 3)} ${code.substring(3)}',
      style: Theme.of(context).textTheme.displayMedium
          ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 4),
    ),
    const SizedBox(height: 12),
    Text(hint, textAlign: TextAlign.center),
    const SizedBox(height: 12),
    const Text('只有两端都确认后才会传输配置和密钥。', textAlign: TextAlign.center),
  ],
);

/// Radar uses stable visual positions, NOT physical proximity or direction.
class RadarDisplay extends StatefulWidget {
  const RadarDisplay({super.key, this.devices = const [], this.onChoose});
  final List<TransferDevice> devices;
  final ValueChanged<TransferDevice>? onChoose;

  @override
  State<RadarDisplay> createState() => _RadarState();
}

class _RadarState extends State<RadarDisplay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Center(
      child: SizedBox(
        height: 296,
        width: 296,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _RadarPaint(color, _controller.value),
                ),
              ),
              const Center(child: Icon(Icons.devices_rounded, size: 32)),
              for (var i = 0; i < math.min(widget.devices.length, 8); i++)
                Positioned(
                  left: 148 + 102 * math.cos(-math.pi / 2 + i * 2.4) - 24,
                  top: 148 + 102 * math.sin(-math.pi / 2 + i * 2.4) - 24,
                  child: Tooltip(
                    message: widget.devices[i].label,
                    child: Material(
                      color: color.withValues(alpha: 0.15),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: widget.devices[i].label,
                        icon: Icon(
                          widget.devices[i].name.toLowerCase().contains('win')
                              ? Icons.computer
                              : Icons.smartphone,
                        ),
                        onPressed: widget.onChoose == null
                            ? null
                            : () => widget.onChoose!(widget.devices[i]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadarPaint extends CustomPainter {
  const _RadarPaint(this.color, this.phase);
  final Color color;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .46;
    for (final scale in [.35, .65, 1.0]) {
      canvas.drawCircle(
        center,
        radius * scale,
        Paint()
          ..color = color.withValues(alpha: .26)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(phase * math.pi * 2);
    final sweep = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi / 2,
        colors: [color.withValues(alpha: .0), color.withValues(alpha: .22)],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: radius),
      -math.pi / 2,
      math.pi / 2,
      true,
      sweep,
    );
    canvas.restore();
    canvas.drawCircle(
      center,
      31,
      Paint()..color = color.withValues(alpha: .18),
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPaint old) =>
      old.phase != phase || old.color != color;
}
