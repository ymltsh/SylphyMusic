import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/core/models.dart';
import 'package:sylphy_music/services/sources.dart';
import 'package:sylphy_music/services/webdav_tags.dart';

import 'live_emby_test.dart' show MemoryVault;
import 'media_proxy_test.dart' show NetworkTestBinding;

void main() {
  NetworkTestBinding();
  final path = Platform.environment['SYLPHY_WEBDAV_CREDENTIAL_FILE'];
  test(
    'live WebDAV login, recursive listing, sidecars and original audio Range (read only)',
    () async {
      final v = (await File(
        path!,
      ).readAsLines()).where((s) => s.trim().isNotEmpty).toList();
      final vault = MemoryVault();
      final adapter = WebDavAdapter(
        SourceProfile(
          id: 'live-dav',
          name: 'Private test',
          kind: SourceKind.webdav,
          url: v[0].trim(),
          username: v[1].trim(),
        ),
        vault,
      );
      final tags = WebDavTags(AdapterFactory(vault));
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
        final embedded = await tags.load(adapter.profile, first);
        // Sanitized assertions: never include private lyrics or binary tags in
        // failure output. This test source's first track has both embedded.
        expect(embedded.cover?.isNotEmpty == true, isTrue);
        expect(embedded.lyrics?.trim().isNotEmpty == true, isTrue);
        final codec = await ui.instantiateImageCodec(embedded.cover!);
        final frame = await codec.getNextFrame();
        expect(frame.image.width > 0 && frame.image.height > 0, isTrue);
        frame.image.dispose();
        codec.dispose();
        if (first.remote['lyricsId'] != null) {
          expect(await adapter.lyrics(first), isNotEmpty);
        }
      } catch (e) {
        fail('真实 WebDAV 只读联调失败（${e.runtimeType}）；私密环境中检查连接与权限');
      } finally {
        await tags.shutdown();
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
