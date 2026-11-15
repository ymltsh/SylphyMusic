import 'dart:convert';
import 'dart:io';

import 'device_transfer_transport.dart';

/// Local interface information only; does not probe other devices or servers.
class TransferNetworkAddress {
  const TransferNetworkAddress(this.interfaceName, this.address);
  final String interfaceName;
  final String address;
}

class DeviceTransferDiagnostics {
  static Future<List<TransferNetworkAddress>> localAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return [
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (isLanAddress(address))
            TransferNetworkAddress(interface.name, address.address),
    ];
  }

  // TCP uses an ephemeral port, so scope its rule to the current executable.
  // Both rules are limited to private networks and local-subnet peers.
  static String get windowsFirewallCommands {
    final program = Platform.resolvedExecutable;
    return 'netsh advfirewall firewall add rule '
        'name="SylphyMusic Transfer Discovery" dir=in action=allow '
        'program="$program" profile=private remoteip=localsubnet '
        'protocol=UDP localport=$transferDiscoveryPort\n\n'
        'netsh advfirewall firewall add rule '
        'name="SylphyMusic Transfer Receive" dir=in action=allow '
        'program="$program" profile=private remoteip=localsubnet '
        'protocol=TCP';
  }

  static String _powerShellLiteral(String value) =>
      "'${value.replaceAll("'", "''")}'";

  static String _encodedCommand(String script) {
    final bytes = <int>[];
    for (final unit in script.codeUnits) {
      bytes.addAll([unit & 255, unit >> 8]);
    }
    return base64Encode(bytes);
  }

  /// Invoked only by the user's repair button. Windows owns the UAC prompt.
  static Future<void> repairWindowsFirewall() async {
    if (!Platform.isWindows) return;
    final program = _powerShellLiteral(Platform.resolvedExecutable);
    final repair =
        '''
\$ErrorActionPreference = 'Stop'
try {
  \$program = $program
  foreach (\$rule in @(
    @{Name='SylphyMusic.Transfer.Discovery'; Protocol='UDP'; Port='$transferDiscoveryPort'},
    @{Name='SylphyMusic.Transfer.Receive'; Protocol='TCP'; Port='Any'}
  )) {
    \$options = @{
      Direction='Inbound'; Action='Allow'; Enabled='True'; Profile='Private';
      Program=\$program; RemoteAddress='LocalSubnet';
      Protocol=\$rule.Protocol; LocalPort=\$rule.Port
    }
    \$existing = Get-NetFirewallRule -Name \$rule.Name -ErrorAction SilentlyContinue
    if (\$existing) {
      Set-NetFirewallRule -Name \$rule.Name @options | Out-Null
    } else {
      New-NetFirewallRule -Name \$rule.Name -DisplayName \$rule.Name @options | Out-Null
    }
  }
  exit 0
} catch { exit 1 }
''';
    final encodedRepair = _encodedCommand(repair);
    final launcher =
        '''
try {
  \$process = Start-Process -FilePath "\$PSHOME\\powershell.exe" -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', '$encodedRepair')
  exit \$process.ExitCode
} catch { exit 2 }
''';
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      _encodedCommand(launcher),
    ]);
    if (result.exitCode == 2) {
      throw StateError('未获得管理员权限，未完成自动修复。可再次尝试或使用手动命令。');
    }
    if (result.exitCode != 0) {
      throw StateError('防火墙规则未能更新。请打开防火墙检查系统或组织策略。');
    }
  }

  static Future<void> openWindowsFirewall() async {
    if (!Platform.isWindows) return;
    final result = await Process.run('control.exe', ['firewall.cpl']);
    if (result.exitCode != 0) {
      throw StateError('无法打开防火墙，请从 Windows 设置中打开 Windows Defender 防火墙。');
    }
  }
}
