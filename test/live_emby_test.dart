import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/services/sources.dart';

class MemoryVault extends AuthVault {
  final Map<String, String> values = {};
  @override
  Future<void> write(String id, String name, String value) async {
    values['$id.$name'] = value;
  }

  @override
  Future<String?> read(String id, String name) async => values['$id.$name'];
  @override
  Future<void> delete(String id) async {
    values.removeWhere((k, _) => k.startsWith('$id.'));
  }
}

void main() {
  final path = Platform.environment['SYLPHY_EMBY_CREDENTIAL_FILE'];
  test(
    'live Emby primary artwork URLs and image decoding (read only)',
    () async {
      final values = (await File(
        path!,
      ).readAsLines()).where((s) => s.trim().isNotEmpty).toList();
      final adapter = EmbyAdapter(
        SourceProfile(
          id: 'cover-live-test',
          name: 'Private test',
          kind: SourceKind.emby,
          url: values[0].trim(),
          username: values[1].trim(),
        ),
        MemoryVault(),
      );
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      try {
        await adapter.login(values[2]);
        var verified = 0;
        await for (final page in adapter.libraryPages()) {
          for (final track in page) {
            final tag = (track.remote['ImageTags'] as Map?)?['Primary'];
            if (tag == null) continue;
            final url = (await adapter.coverUrl(track))!;
            if (url.queryParameters['tag'] != tag ||
                !url.pathSegments.contains(track.ref.id)) {
              throw StateError('Invalid image identity');
            }
            final request = await client.getUrl(url);
            request.followRedirects = false;
            (await adapter.mediaHeaders()).forEach(
              (k, v) => request.headers.set(k, v),
            );
            final response = await request.close().timeout(
              const Duration(seconds: 20),
            );
            if (response.statusCode != 200) {
              throw StateError('Image read failed');
            }
            final bytes = await response.fold<List<int>>(
              [],
              (out, b) => out..addAll(b),
            );
            final buffer = await ui.ImmutableBuffer.fromUint8List(
              Uint8List.fromList(bytes),
            );
            final descriptor = await ui.ImageDescriptor.encoded(buffer);
            if (descriptor.width < 1 || descriptor.height < 1) {
              throw StateError('Invalid image');
            }
            descriptor.dispose();
            buffer.dispose();
            if (++verified == 8) break;
          }
          if (verified == 8) break;
        }
        expect(verified, 8);
      } catch (error) {
        fail('真实 Emby 封面验证失败（${error.runtimeType}）；地址、图片身份与内容不输出');
      } finally {
        adapter.close();
        client.close(force: true);
      }
    },
    skip: path == null
        ? 'Set SYLPHY_EMBY_CREDENTIAL_FILE for private cover test'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'live Emby login, index, playlists and original audio Range (read only)',
    () async {
      final lines = await File(path!).readAsLines();
      final values = lines.where((s) => s.trim().isNotEmpty).toList();
      if (values.length != 3) fail('测试凭据文件应为 URL、用户名、密码三行');
      final adapter = EmbyAdapter(
        SourceProfile(
          id: 'live-test',
          name: 'Test',
          kind: SourceKind.emby,
          url: values[0].trim(),
          username: values[1].trim(),
        ),
        MemoryVault(),
      );
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      try {
        await adapter.login(values[2]);
        await adapter.validateConnection();
        Track? first;
        await for (final page in adapter.libraryPages()) {
          expect(page.length, lessThanOrEqualTo(250));
          if (page.isNotEmpty) first ??= page.first;
        }
        expect(first, isNotNull);
        var lyricFound = false;
        await for (final page in adapter.libraryPages()) {
          for (final track in page) {
            final sources =
                (track.remote['MediaSources'] as List?)?.whereType<Map>() ??
                const <Map>[];
            final streams = [
              ...?track.remote['MediaStreams'] as List?,
              for (final source in sources) ...?source['MediaStreams'] as List?,
            ];
            if (!streams.whereType<Map>().any(
              (s) =>
                  s['Type'] == 'Subtitle' &&
                  ['text', 'txt', 'lrc'].contains(s['Codec']),
            )) {
              continue;
            }
            final text = await adapter.lyrics(track);
            // No private lyrics, song names or IDs in test output.
            expect(text?.trim().isNotEmpty, true, reason: '服务器声明的歌词流应可读取');
            lyricFound = true;
            break;
          }
          if (lyricFound) break;
        }
        expect(lyricFound, true, reason: '测试曲库应包含歌词流');
        final playlists = await adapter.fetchPlaylists();
        if (playlists.isNotEmpty) {
          await adapter.fetchPlaylist(playlists.first.id);
        }
        final request = await client.getUrl(await adapter.mediaUrl(first!));
        request.followRedirects = false;
        (await adapter.mediaHeaders()).forEach(
          (k, v) => request.headers.set(k, v),
        );
        request.headers.set('Range', 'bytes=0-1023');
        final response = await request.close();
        expect(response.statusCode, 206);
        expect(
          response.headers.value('content-range'),
          startsWith('bytes 0-1023/'),
        );
        expect(
          await response.fold<int>(0, (size, chunk) => size + chunk.length),
          1024,
        );
      } catch (error) {
        // Never expose server address, credentials or private library metadata.
        fail('真实 Emby 只读联调失败（${error.runtimeType}）；请在私密环境检查连接与服务端权限');
      } finally {
        client.close(force: true);
        adapter.close();
      }
    },
    skip: path == null
        ? 'Set SYLPHY_EMBY_CREDENTIAL_FILE to run private integration'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
