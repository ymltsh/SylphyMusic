import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sylphy_music/services/app_updates.dart';
import 'package:sylphy_music/ui/app_update_page.dart';

Map<String, dynamic> release({String version = '0.3.0', int build = 3}) => {
  'version': version,
  'build': build,
  'name': '风灵音乐 $version',
  'notes': '新功能\n修复问题',
  'date': '2026-10-28',
  'urls': {
    'windows':
        'https://github.com/ymltsh/SylphyMusic/releases/download/v$version/setup.exe',
  },
};

http.Response reply(String body, int status) =>
    http.Response.bytes(utf8.encode(body), status);

void main() {
  test('compares numeric versions, channels and builds without downgrades', () {
    expect(
      AppVersion('0.10.0', 2).compareTo(AppVersion('0.9.0', 100)),
      greaterThan(0),
    );
    expect(
      AppVersion('0.3.0', 4).compareTo(AppVersion('0.3.0', 3)),
      greaterThan(0),
    );
    expect(
      AppVersion('0.3.0', 2).compareTo(AppVersion('0.3.0-beta2', 99)),
      greaterThan(0),
    );
    expect(
      AppVersion('0.3.0-beta2', 3).compareTo(AppVersion('0.3.0-beta', 99)),
      greaterThan(0),
    );
    expect(AppVersion('0.3.0', 3).compareTo(AppVersion('0.3.0', 3)), 0);
    expect(() => AppVersion('0.3', 3), throwsFormatException);
    expect(() => AppVersion('00.3.0', 3), throwsFormatException);
  });
  test('checking is explicit and falls back from mirror to origin', () async {
    final calls = <Uri>[];
    final service = AppUpdates(
      readVersion: () async => AppVersion('0.2.0', 2),
      clientFactory: () => MockClient((request) async {
        calls.add(request.url);
        if (request.url.host == 'hub.wgen.top') return reply('offline', 503);
        return reply(jsonEncode({'latest': release()}), 200);
      }),
    );
    expect(calls, isEmpty);
    final result = await service.check();
    expect(result.available, isTrue);
    expect(calls.map((u) => u.host), [
      'hub.wgen.top',
      'raw.githubusercontent.com',
    ]);
    expect(result.latest!.page.toString(), AppUpdates.releasePage);
  });
  test(
    'same or older manifests never offer update; empty release is supported',
    () async {
      for (final value in [
        null,
        release(version: '0.2.0', build: 2),
        release(version: '0.1.0', build: 100),
      ]) {
        final service = AppUpdates(
          readVersion: () async => AppVersion('0.2.0', 2),
          clientFactory: () => MockClient(
            (_) async => reply(jsonEncode({'latest': value}), 200),
          ),
        );
        expect((await service.check()).available, isFalse);
      }
    },
  );
  test(
    'beta uses a separate endpoint; stable rejects beta manifests',
    () async {
      final paths = <String>[];
      final service = AppUpdates(
        readVersion: () async => AppVersion('0.2.0', 2),
        clientFactory: () => MockClient((request) async {
          paths.add(request.url.path);
          return reply(
            jsonEncode({'latest': release(version: '0.3.0-beta')}),
            200,
          );
        }),
      );
      expect((await service.check(beta: true)).available, isTrue);
      expect(paths.single, endsWith('/version-beta.json'));
      await expectLater(service.check(), throwsFormatException);
    },
  );
  test(
    'malformed responses, redirects, oversized bodies and unsafe links fail',
    () async {
      for (final response in [
        reply('<html>not json</html>', 200),
        reply('{}', 200),
        reply('redirect', 302),
        reply('x' * (1024 * 1024 + 1), 200),
        reply(
          jsonEncode({
            'latest': {
              ...release(),
              'urls': {'windows': 'file:///private'},
            },
          }),
          200,
        ),
        reply(
          jsonEncode({
            'latest': {
              ...release(),
              'urls': {
                'windows':
                    'https://github.com/other/repo/releases/download/setup.exe',
              },
            },
          }),
          200,
        ),
        reply(
          jsonEncode({
            'latest': {...release(), 'build': '3'},
          }),
          200,
        ),
      ]) {
        final service = AppUpdates(
          readVersion: () async => AppVersion('0.2.0', 2),
          clientFactory: () => MockClient((_) async => response),
        );
        await expectLater(service.check(), throwsA(anything));
      }
    },
  );
  testWidgets(
    'manual checking, in-flight disabling, retry and platform download',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var calls = 0;
      final request = Completer<UpdateCheck>();
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: AppUpdatePage(
            onCheck: ({bool beta = false}) {
              calls++;
              if (calls == 1) return request.future;
              return Future.value(
                UpdateCheck(
                  AppVersion('0.2.0', 2),
                  UpdateRelease.fromJson(release()),
                ),
              );
            },
            openUrl: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      );
      expect(calls, 0);
      await tester.tap(find.widgetWithText(FilledButton, '检查更新'));
      await tester.pump();
      expect(calls, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      request.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('检查更新失败，请检查网络后重试'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本：风灵音乐 0.3.0'), findsOneWidget);
      await tester.ensureVisible(find.text('Windows 安装程序'));
      await tester.tap(find.text('Windows 安装程序'));
      await tester.pumpAndSettle();
      expect(opened.single.path, endsWith('/setup.exe'));
      await tester.ensureVisible(find.text('查看发布页'));
      await tester.tap(find.text('查看发布页'));
      await tester.pumpAndSettle();
      expect(opened.last.toString(), AppUpdates.releasePage);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
  testWidgets(
    'same version and missing platform links show no download buttons',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppUpdatePage(
            onCheck: ({bool beta = false}) async => UpdateCheck(
              AppVersion('0.3.0', 3),
              UpdateRelease.fromJson(release()),
            ),
          ),
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, '检查更新'));
      await tester.pumpAndSettle();
      expect(find.text('已是最新版本'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
    },
  );
}
