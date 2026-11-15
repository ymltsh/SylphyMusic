import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/services/device_transfer_config.dart';
import 'package:sylphy_music/services/device_transfer_transport.dart';

void main() {
  test('bundle scope forbids hidden API keys in sources-only transfer', () {
    final valid = TransferBundle.parse({
      'version': 1,
      'scope': 'sources',
      'sources': <Object>[],
      'settings': <String, String>{},
      'keys': <String, String>{},
      'images': <String, String>{},
      'cards': <Object>[],
      'activeCard': null,
    });
    expect(valid.scope, TransferScope.sources);
    expect(
      () => TransferBundle.parse({
        ...valid.toJson(),
        'keys': {'llm': 'must not transfer'},
      }),
      throwsFormatException,
    );
  });

  test('remote source identity ignores trailing slash but not account', () {
    const a = SourceProfile(
      id: 'one',
      kind: SourceKind.emby,
      name: 'Home',
      url: 'https://music.example/',
      username: 'Alice',
    );
    const b = SourceProfile(
      id: 'two',
      kind: SourceKind.emby,
      name: 'Elsewhere',
      url: 'https://music.example',
      username: 'alice',
    );
    const c = SourceProfile(
      id: 'three',
      kind: SourceKind.emby,
      name: 'Another user',
      url: 'https://music.example',
      username: 'Bob',
    );
    expect(DeviceTransferConfig.sameRemoteSource(a, b), isTrue);
    expect(DeviceTransferConfig.sameRemoteSource(a, c), isFalse);
  });

  test('UDP discovery is limited to LAN addresses', () {
    expect(isLanAddress(InternetAddress('192.168.1.5')), isTrue);
    expect(isLanAddress(InternetAddress('10.0.0.2')), isTrue);
    expect(isLanAddress(InternetAddress('8.8.8.8')), isFalse);
  });

  test('handshake yields matching codes and encrypted frames', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final incoming = server.first.then(TransferSession.accept);
    final clientSocket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      server.port,
    );
    final sender = await TransferSession.connect(clientSocket);
    final receiver = await incoming;
    try {
      expect(sender.code, matches(RegExp(r'^\d{6}$')));
      expect(sender.code, receiver.code);
      await Future.wait([sender.approve(), receiver.approve()])
          .timeout(const Duration(seconds: 10));
      await sender.send({'type': 'bundle', 'secret': 'not plaintext'});
      expect(await receiver.receive(), {
        'type': 'bundle',
        'secret': 'not plaintext',
      });
      await receiver.send({'type': 'result', 'success': true});
      expect((await sender.receive())['success'], isTrue);
    } finally {
      await sender.close();
      await receiver.close();
      await server.close();
    }
  });
}
