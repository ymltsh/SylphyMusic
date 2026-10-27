import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'core/app_controller.dart';
import 'ui/app_shell.dart';
import 'ui/system_bars.dart';
import 'ui/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureSystemBars();
  MediaKit.ensureInitialized();
  runApp(const _Bootstrap());
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final Future<SylphyApp> ready = SylphyApp.bootstrap();
  @override
  Widget build(BuildContext context) => FutureBuilder<SylphyApp>(
    future: ready,
    builder: (context, snapshot) {
      final app = snapshot.data;
      return AnimatedBuilder(
        animation: app?.appearance ?? const AlwaysStoppedAnimation(0),
        builder: (context, _) => MaterialApp(
          themeMode: app?.appearance.mode ?? ThemeMode.system,
          builder: (context, child) =>
              AppSystemBars(child: child ?? const SizedBox.shrink()),
          debugShowCheckedModeBanner: false,
          title: '风灵音乐 · Sylphy Music',
          theme: sylphyTheme(app?.appearance, Brightness.light),
          darkTheme: sylphyTheme(app?.appearance, Brightness.dark),
          home: snapshot.hasData
              ? SylphyShell(app: snapshot.data!)
              : Scaffold(
                  body: Center(
                    child: snapshot.hasError
                        ? SelectableText('启动失败：${snapshot.error}')
                        : const CircularProgressIndicator(),
                  ),
                ),
        ),
      );
    },
  );
}
