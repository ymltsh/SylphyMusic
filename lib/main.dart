import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'core/app_controller.dart';
import 'services/native_lifecycle.dart';
import 'services/native_licenses.dart';
import 'ui/app_identity.dart';
import 'ui/app_shell.dart';
import 'ui/system_bars.dart';
import 'ui/app_theme.dart';
import 'ui/playback_shortcuts.dart';
import 'ui/player_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await recordDartStartup();
  await configureSystemBars();
  if (Platform.isAndroid) {
    registerAndroidNativeLicenses();
  } else {
    MediaKit.ensureInitialized();
  }
  runApp(const _Bootstrap());
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  final _navigator = GlobalKey<NavigatorState>();
  late final Future<SylphyApp> ready = SylphyApp.bootstrap();
  @override
  Widget build(BuildContext context) => FutureBuilder<SylphyApp>(
    future: ready,
    builder: (context, snapshot) {
      final app = snapshot.data;
      return AnimatedBuilder(
        animation: app == null
            ? const AlwaysStoppedAnimation(0)
            : Listenable.merge([app.appearance, app.desktopPreferences]),
        builder: (context, _) => MaterialApp(
          navigatorKey: _navigator,
          themeMode: app?.appearance.mode ?? ThemeMode.system,
          builder: (context, child) {
            final content = AppSystemBars(
              child: child ?? const SizedBox.shrink(),
            );
            if (app == null) return content;
            return PlaybackShortcuts(
              app: app,
              child: content,
              onQueue: () {
                final target = _navigator.currentState?.overlay?.context;
                if (target != null) PlayerBar(app: app).showQueue(target);
              },
            );
          },
          debugShowCheckedModeBanner: false,
          onGenerateTitle: (_) => appDisplayName(),
          theme: sylphyTheme(
            app?.appearance,
            Brightness.light,
            fontFamily: app?.desktopPreferences.fontFamily,
          ),
          darkTheme: sylphyTheme(
            app?.appearance,
            Brightness.dark,
            fontFamily: app?.desktopPreferences.fontFamily,
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
        ),
      );
    },
  );
}
