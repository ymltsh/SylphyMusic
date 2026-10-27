import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'core/app_controller.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '风灵音乐 · Sylphy Music',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff528a81)),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff528a81),
            brightness: Brightness.dark,
          ),
        ),
        home: snapshot.hasData
            ? SylphyShell(app: snapshot.data!)
            : Scaffold(
                body: Center(
                  child: snapshot.hasError
                      ? SelectableText('启动失败：${snapshot.error}')
                      : const CircularProgressIndicator(),
                ),
              ),
      );
    },
  );
}
