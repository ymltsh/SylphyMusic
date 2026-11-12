import 'dart:convert';

import 'package:flutter/services.dart';

import 'api_settings.dart';

/// Bundled, adapted character presets. Loading never contacts a model service.
class PenpalPromptPreset {
  const PenpalPromptPreset({required this.system, required this.user});

  final String system;
  final String user;

  static Future<PenpalPromptPreset> sylphiette() => _load('sylphiette');
  static Future<PenpalPromptPreset> venti() => _load('venti');

  static Future<PenpalPromptPreset> _load(String id) async {
    final data = jsonDecode(
      await rootBundle.loadString('assets/penpal/$id.json'),
    ) as Map<String, dynamic>;
    return PenpalPromptPreset(
      system: ApiSettings.validateLlmSystemPrompt(data['system'] as String),
      user: ApiSettings.validateLlmUserPrompt(data['user'] as String),
    );
  }
}
