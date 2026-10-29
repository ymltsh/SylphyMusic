import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> configureSystemBars() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Reapply the native plugin's saved overlay style even when Dart considers
    // the AnnotatedRegion style unchanged after returning from the background.
    await SystemChrome.restoreSystemUIOverlays();
  }
}

/// Gives every route a transparent navigation bar with theme-aware controls.
/// Each page keeps its own safe insets so its background can reach the edge.
class AppSystemBars extends StatefulWidget {
  const AppSystemBars({super.key, required this.child});
  final Widget child;
  @override
  State<AppSystemBars> createState() => _AppSystemBarsState();
}

class _AppSystemBarsState extends State<AppSystemBars>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(configureSystemBars());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced:
            MediaQuery.systemGestureInsetsOf(context).bottom == 0,
      ),
      child: widget.child,
    );
  }
}
