import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/services/sources.dart';

import 'live_emby_test.dart' show MemoryVault;

void main() {
  final path = Platform.environment['SYLPHY_WEBDAV_CREDENTIAL_FILE'];
  test(
    'live WebDAV login, recursive listing, sidecars and original audio Range (read only)',
    () async {
      final v = (await File(
        path!,
      ).readAsLines()).where((s) => s.trim().isNotEmpty).toList();
      final adapter = WebDavAdapter(
        SourceProfile(
          id: 'live-dav',
          name: 'Private test',
          kind: SourceKind.webdav,
          url: v[0].trim(),
          username: v[1].trim(),
        ),
        MemoryVault(),
      );
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 20);
      try {
        await adapter.login(v[2]);
        await adapter.validateConnection();
        Track? first;
        await for (final page in adapter.libraryPages()) {
          expect(page.length, lessThanOrEqualTo(250));
          if (page.isNotEmpty) {
            first = page.first;
            break;
          }
        }
        expect(first, isNotNull);
        final request = await client.getUrl(await adapter.mediaUrl(first!));
        request.followRedirects = false;
        (await adapter.mediaHeaders()).forEach(
          (k, v) => request.headers.set(k, v),
        );
        request.headers.set('Range', 'bytes=0-1023');
        final response = await request.close();
        expect(response.statusCode, 206);
        expect(await response.fold<int>(0, (n, b) => n + b.length), 1024);
        if (first.remote['lyricsId'] != null) {
          expect(await adapter.lyrics(first), isNotEmpty);
        }
      } catch (e) {
        fail('真实 WebDAV 只读联调失败（${e.runtimeType}）；私密环境中检查连接与权限');
      } finally {
        adapter.close();
        client.close(force: true);
      }
    },
    skip: path == null
        ? 'Set SYLPHY_WEBDAV_CREDENTIAL_FILE for private test'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
