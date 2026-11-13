/// Temporary, on-demand LAN discovery and authenticated encrypted migration.
/// No discovery socket or listener survives the transfer screen's lifetime.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as digest;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

const transferDiscoveryPort = 43872;
const _protocol = 1;
const _discover = 'SYLPHY_MIGRATE_DISCOVER_1';
const _reply = 'SYLPHY_MIGRATE_REPLY_1:';
const _maxFrameBytes = 64 * 1024 * 1024;

Future<void> requireTransferLanPermission() async {
  if (!Platform.isAndroid) return;
  final granted = await const MethodChannel('music.sylphy/local_network')
      .invokeMethod<bool>('request');
  if (granted != true) {
    throw StateError('请允许风灵音乐访问本地网络后再试');
  }
}

String transferDeviceName() {
  const notes = ['♩', '♪', '♫', '♬'];
  final random = Random.secure();
  final note = notes[random.nextInt(notes.length)];
  final number = random.nextInt(1000000).toString().padLeft(6, '0');
  return '$note 设备 $number';
}

bool isLanAddress(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4) return false;
  final b = address.rawAddress;
  return b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168) ||
      (b[0] == 169 && b[1] == 254) ||
      b[0] == 127;
}

class TransferDevice {
  const TransferDevice({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
  });
  final String id;
  final String name;
  final InternetAddress address;
  final int port;
  String get label => '$name · ${address.address}';
}

/// UDP broadcast is used only for ephemeral discovery. TCP carries ALL data.
class TransferScanner {
  RawDatagramSocket? _udp;
  Timer? _timer;
  final Map<String, TransferDevice> _found = {};
  final _changes = StreamController<List<TransferDevice>>.broadcast();
  Stream<List<TransferDevice>> get changes => _changes.stream;

  Future<void> start() async {
    if (_udp != null) return;
    final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _udp = udp..broadcastEnabled = true;
    udp.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? packet;
      while ((packet = udp.receive()) != null) {
        final item = packet!;
        if (!isLanAddress(item.address)) continue;
        final text = utf8.decode(item.data, allowMalformed: true);
        if (!text.startsWith(_reply)) continue;
        try {
          final json = jsonDecode(text.substring(_reply.length)) as Map;
          if (json['v'] != _protocol) continue;
          final id = json['id'];
          final name = json['name'];
          final port = json['port'];
          if (id is! String ||
              id.length != 32 ||
              name is! String ||
              name.isEmpty ||
              name.length > 48 ||
              port is! int ||
              port < 1 ||
              port > 65535)
            continue;
          _found[id] = TransferDevice(
            id: id,
            name: name,
            address: item.address,
            port: port,
          );
          if (!_changes.isClosed) _changes.add(_found.values.toList());
        } on FormatException {
          // Ignore unrelated LAN broadcasts.
        } on TypeError {
          // Ignore malformed replies.
        }
      }
    });
    _broadcast();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _broadcast());
  }

  void _broadcast() {
    final udp = _udp;
    if (udp == null) return;
    try {
      udp.send(
        utf8.encode(_discover),
        InternetAddress('255.255.255.255'),
        transferDiscoveryPort,
      );
    } on SocketException {
      // A transient Wi-Fi/interface change should not crash the scan timer.
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _udp?.close();
    _udp = null;
    _found.clear();
    await _changes.close();
  }
}

/// One receiver per screen. Reject concurrent connections, non-LAN peers,
/// and connections outside the explicitly opened receive window.
class TransferReceiver {
  TransferReceiver({required this.onSocket});
  final void Function(Socket socket) onSocket;
  ServerSocket? _tcp;
  RawDatagramSocket? _udp;
  final String id = _randomHex(16);
  final String name = transferDeviceName();
  bool _occupied = false;
  Socket? _acceptedSocket;
  bool get discoveryListening => _udp != null;
  int? get listeningPort => _tcp?.port;
  bool get occupied => _occupied;

  Future<void> start() async {
    if (_tcp != null) return;
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _tcp = server;
    try {
      final udp = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        transferDiscoveryPort,
      );
      _udp = udp;
      udp.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? packet;
        while ((packet = udp.receive()) != null) {
          final request = packet!;
          if (_occupied ||
              !isLanAddress(request.address) ||
              utf8.decode(request.data, allowMalformed: true) != _discover) {
            continue;
          }
          try {
            udp.send(
              utf8.encode(
                '$_reply${jsonEncode({'v': _protocol, 'id': id, 'name': name, 'port': server.port})}',
              ),
              request.address,
              request.port,
            );
          } on SocketException {
            // The peer may have switched networks during discovery.
          }
        }
      });
      server.listen((socket) {
        if (_occupied || !isLanAddress(socket.remoteAddress)) {
          socket.destroy();
          return;
        }
        _occupied = true;
        _acceptedSocket = socket;
        onSocket(socket);
      });
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  Future<void> stop() async {
    _acceptedSocket?.destroy();
    _acceptedSocket = null;
    _udp?.close();
    _udp = null;
    await _tcp?.close();
    _tcp = null;
  }
}

String _randomHex(int length) {
  final random = Random.secure();
  return List.generate(
    length,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// A length-prefixed socket reader; never decodes untrusted messages unboundedly.
class _Frames {
  _Frames(this.socket) : _iterator = StreamIterator<Uint8List>(socket);
  final Socket socket;
  final StreamIterator<Uint8List> _iterator;
  Uint8List _pending = Uint8List(0);
  int _offset = 0;

  Future<Uint8List> _readExact(int amount) async {
    final result = Uint8List(amount);
    var copied = 0;
    while (copied < amount) {
      if (_offset == _pending.length) {
        if (!await _iterator.moveNext()) {
          throw const SocketException('对方已断开连接');
        }
        _pending = _iterator.current;
        _offset = 0;
        continue;
      }
      final count = min(amount - copied, _pending.length - _offset);
      result.setRange(copied, copied + count, _pending, _offset);
      copied += count;
      _offset += count;
    }
    return result;
  }

  Future<Uint8List> read({int maxBytes = _maxFrameBytes}) async {
    final header = await _readExact(4);
    final size = ByteData.sublistView(header).getUint32(0, Endian.big);
    if (size == 0 || size > maxBytes || size > _maxFrameBytes) {
      throw const FormatException('迁移数据大小超出安全限制');
    }
    return _readExact(size);
  }

  Future<void> write(List<int> bytes) async {
    if (bytes.isEmpty || bytes.length > _maxFrameBytes) {
      throw const FormatException('迁移数据大小超出安全限制');
    }
    final head = ByteData(4)..setUint32(0, bytes.length, Endian.big);
    socket.add(head.buffer.asUint8List());
    socket.add(bytes);
    await socket.flush();
  }

  Future<Map<String, dynamic>> readJson() async {
    final decoded = jsonDecode(utf8.decode(await read(maxBytes: 4096)));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('迁移消息格式错误');
    }
    return decoded;
  }

  Future<void> writeJson(Map<String, dynamic> data) =>
      write(utf8.encode(jsonEncode(data)));

  Future<void> close() async {
    socket.destroy();
    await _iterator.cancel();
  }
}

/// Each side approves a short authentication string computed from the *ordered*
/// ephemeral handshake transcript. Approval is transmitted with AES-GCM and
/// never sent until the human confirms both screens display the same code.
class TransferSession {
  TransferSession._(this._frames, this._key, this.code);
  final _Frames _frames;
  final SecretKey _key;
  final String code;
  final Cipher _cipher = AesGcm.with256bits();
  int _sendSequence = 0;
  int _readSequence = 0;

  static Future<TransferSession> connect(Socket socket) =>
      _handshake(socket, client: true);

  static Future<TransferSession> accept(Socket socket) =>
      _handshake(socket, client: false);

  static Future<TransferSession> _handshake(
    Socket socket, {
    required bool client,
  }) async {
    final frames = _Frames(socket);
    try {
      final exchange = X25519();
      final localKeys = await exchange.newKeyPair();
      final public = await localKeys.extractPublicKey();
      final random = Random.secure();
      final nonce = List<int>.generate(32, (_) => random.nextInt(256));
      final hello = <String, dynamic>{
        'v': _protocol,
        'public': base64Encode(public.bytes),
        'nonce': base64Encode(nonce),
      };
      Map<String, dynamic> other;
      if (client) {
        await frames.writeJson(hello);
        other = await frames.readJson().timeout(const Duration(seconds: 15));
      } else {
        other = await frames.readJson().timeout(const Duration(seconds: 15));
        await frames.writeJson(hello);
      }
      if (other['v'] != _protocol) {
        throw const FormatException('两台设备的迁移协议不兼容');
      }
      final remotePublic = base64Decode(other['public'] as String);
      final remoteNonce = base64Decode(other['nonce'] as String);
      if (remotePublic.length != 32 || remoteNonce.length != 32) {
        throw const FormatException('无效的设备握手信息');
      }
      final transcript = <int>[
        ...(client ? public.bytes : remotePublic),
        ...(client ? remotePublic : public.bytes),
        ...(client ? nonce : remoteNonce),
        ...(client ? remoteNonce : nonce),
      ];
      final checksum = digest.sha256.convert(transcript).bytes;
      final digits =
          ByteData.sublistView(Uint8List.fromList(checksum))
              .getUint32(0, Endian.big) %
          1000000;
      final shared = await exchange.sharedSecretKey(
        keyPair: localKeys,
        remotePublicKey: SimplePublicKey(
          remotePublic,
          type: KeyPairType.x25519,
        ),
      );
      final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: shared,
        nonce: checksum,
        info: utf8.encode('SylphyMusic-device-migration-v1'),
      );
      return TransferSession._(frames, key, digits.toString().padLeft(6, '0'));
    } catch (_) {
      await frames.close();
      rethrow;
    }
  }

  Future<void> send(Map<String, dynamic> value) async {
    final json = utf8.encode(
      jsonEncode({'seq': _sendSequence++, 'data': value}),
    );
    final box = await _cipher.encrypt(json, secretKey: _key);
    await _frames.write([...box.nonce, ...box.mac.bytes, ...box.cipherText]);
  }

  Future<Map<String, dynamic>> receive({int maxBytes = _maxFrameBytes}) async {
    final raw = await _frames
        .read(maxBytes: maxBytes)
        .timeout(const Duration(minutes: 2));
    if (raw.length < 29) throw const FormatException('加密迁移消息不完整');
    final clear = await _cipher.decrypt(
      SecretBox(
        raw.sublist(28),
        nonce: raw.sublist(0, 12),
        mac: Mac(raw.sublist(12, 28)),
      ),
      secretKey: _key,
    );
    final value = jsonDecode(utf8.decode(clear));
    if (value is! Map<String, dynamic> ||
        value['seq'] != _readSequence++ ||
        value['data'] is! Map<String, dynamic>) {
      throw const FormatException('迁移消息无效或已重放');
    }
    return value['data'] as Map<String, dynamic>;
  }

  Future<void> approve() async {
    await send({'type': 'approve'});
    final response = await receive(maxBytes: 4096);
    if (response['type'] != 'approve') {
      throw StateError('对方未确认配对');
    }
  }

  Future<void> close() => _frames.close();
}
