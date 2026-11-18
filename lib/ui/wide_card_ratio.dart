import 'package:flutter/material.dart';

/// Opt-in and ratio-aware. Does not change any portrait layout.
/// Consumers may add an additional minimum width for split layouts.
bool useWideCardRatio(BuildContext context, bool enabled) {
  if (!enabled) return false;
  final window = MediaQuery.sizeOf(context);
  return window.width >= 700 && window.width > window.height;
}
