import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _systemBarsChannel = MethodChannel('music.sylphy/system_bars');
Future<void> _pendingSystemBars = Future<void>.value();
Object? _immersiveOwner;
bool _nativeImmersive = false;

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

Future<void> configureSystemBars() {
  if (!_isAndroid) return Future<void>.value();
  // Queue window changes and consult the current route when each change runs.
  return _pendingSystemBars = _pendingSystemBars.then((_) async {
    final immersive = _immersiveOwner != null;
    try {
      if (!immersive) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        // Reapply the saved overlay style after returning from the background.
        await SystemChrome.restoreSystemUIOverlays();
      }
      if (immersive || _nativeImmersive) {
        await _systemBarsChannel.invokeMethod<void>('setImmersive', immersive);
        _nativeImmersive = immersive;
      }
    } on MissingPluginException {
      // The cached Flutter engine can outlive its Android Activity.
    } on PlatformException catch (error) {
      debugPrint('System bars update failed: ${error.code}');
    }
  });
}

void _setImmersiveOwner(Object owner, {required bool enabled}) {
  if (!_isAndroid) return;
  if (enabled) {
    if (identical(_immersiveOwner, owner)) return;
    _immersiveOwner = owner;
  } else {
    if (!identical(_immersiveOwner, owner)) return;
    _immersiveOwner = null;
  }
  unawaited(configureSystemBars());
}

/// Gives every route a transparent navigation bar with theme-aware controls.
/// Each page keeps its own safe insets so its background can reach the edge.
class AppSystemBars extends StatefulWidget {
  const AppSystemBars({super.key, required this.child, this.immersive = false});
  final Widget child;
  final bool immersive;
  @override
  State<AppSystemBars> createState() => _AppSystemBarsState();
}

class _AppSystemBarsState extends State<AppSystemBars>
    with WidgetsBindingObserver {
  bool _routeIsCurrent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeIsCurrent = ModalRoute.isCurrentOf(context) ?? false;
    _syncImmersive();
  }

  @override
  void didUpdateWidget(AppSystemBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.immersive != widget.immersive) _syncImmersive();
  }

  void _syncImmersive() =>
      _setImmersiveOwner(this, enabled: widget.immersive && _routeIsCurrent);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(configureSystemBars());
    }
  }

  @override
  void dispose() {
    _setImmersiveOwner(this, enabled: false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemStatusBarContrastEnforced: false,
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
