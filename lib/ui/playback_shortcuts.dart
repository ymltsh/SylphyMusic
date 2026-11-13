import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';

/// Foreground, app-local shortcuts. Never register system-wide hotkeys.
class PlaybackShortcuts extends StatefulWidget {
  const PlaybackShortcuts({
    super.key,
    required this.app,
    required this.child,
    required this.onQueue,
  });
  final SylphyApp app;
  final Widget child;
  final VoidCallback onQueue;
  @override
  State<PlaybackShortcuts> createState() => _PlaybackShortcutsState();
}

class _PlaybackShortcutsState extends State<PlaybackShortcuts> {
  bool _transportBusy = false;
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handle);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handle);
    super.dispose();
  }

  bool _editingOrPopup() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    if (ModalRoute.of(context) is PopupRoute) return true;
    var editing = context.widget is EditableText || context.widget is Slider;
    context.visitAncestorElements((element) {
      if (element.widget is EditableText || element.widget is Slider) {
        editing = true;
        return false;
      }
      return true;
    });
    return editing;
  }

  bool _focusedButton() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    var button = false;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is ButtonStyleButton ||
          widget is IconButton ||
          widget is Checkbox ||
          widget is Switch) {
        button = true;
        return false;
      }
      return true;
    });
    return button;
  }

  Future<void> _perform(
    Future<void> Function() command, {
    bool transport = false,
  }) async {
    if (transport && _transportBusy) return;
    if (transport) _transportBusy = true;
    try {
      await command();
    } catch (_) {
      // PlaybackNotice displays playback errors; a key press must not escape
      // into the framework's keyboard dispatcher.
    } finally {
      if (transport) _transportBusy = false;
    }
  }

  bool _handle(KeyEvent event) {
    if (!mounted ||
        event is KeyUpEvent ||
        event.synthesized ||
        !widget.app.desktopPreferences.shortcutsEnabled ||
        _editingOrPopup())
      return false;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed)
      return false;
    final size = MediaQuery.sizeOf(context);
    if (!Platform.isWindows && !(size.width >= 600 && size.width > size.height))
      return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed)
      return false;
    final player = widget.app.playback;
    final key = event.logicalKey;
    final control = keyboard.isControlPressed;
    Future<void> Function()? command;
    var transport = false;
    if (control && key == LogicalKeyboardKey.keyL) {
      if (event is KeyDownEvent) widget.onQueue();
      return true;
    }
    if (control &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      command = () => player.setVolume(
        (player.volume + (key == LogicalKeyboardKey.arrowUp ? 5 : -5)).clamp(
          0,
          100,
        ),
      );
    } else if (!control && key == LogicalKeyboardKey.keyM) {
      if (event is KeyRepeatEvent) return true;
      command = player.toggleMute;
    } else if (player.snapshot.tracks.isNotEmpty) {
      if (!control && key == LogicalKeyboardKey.space) {
        if (_focusedButton()) return false;
        if (event is KeyRepeatEvent) return true;
        command = player.toggle;
        transport = true;
      } else if (control &&
          (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowRight)) {
        if (event is KeyRepeatEvent) return true;
        command = key == LogicalKeyboardKey.arrowLeft
            ? player.previous
            : player.next;
        transport = true;
      } else if (!control &&
          (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowRight) &&
          player.duration > Duration.zero) {
        final target =
            (player.position.inMilliseconds +
                    (key == LogicalKeyboardKey.arrowLeft ? -5000 : 5000))
                .clamp(0, player.duration.inMilliseconds);
        command = () => player.seek(Duration(milliseconds: target));
        transport = true;
      }
    }
    if (command == null) return false;
    unawaited(_perform(command, transport: transport));
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
