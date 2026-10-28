import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylphy_music/services/launcher_icon_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('music.sylphy/launcher_icons');
  const service = LauncherIconService();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('loads default and alternative Android icons', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getOptions');
      return {
        'selected': 'alt_012345abcdef',
        'options': [
          {'id': 'default', 'label': '默认图标', 'preview': 'assets/icon.png'},
          {
            'id': 'alt_012345abcdef',
            'label': '经典蓝',
            'preview': 'assets/launcher_icons/经典蓝.png',
          },
        ],
      };
    });
    final state = await service.load();
    expect(state.selected, 'alt_012345abcdef');
    expect(state.options.length, 2);
    expect(state.options.last.label, '经典蓝');
  });

  test('sends icon identifier to native Android channel', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'setIcon');
      expect(call.arguments, {'id': 'default'});
      return null;
    });
    await service.select('default');
  });
}
