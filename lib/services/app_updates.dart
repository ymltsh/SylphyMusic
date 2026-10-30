import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class AppVersion implements Comparable<AppVersion> {
  AppVersion(this.version, this.build) {
    if (!_pattern.hasMatch(version) || build < 0) {
      throw const FormatException('版本格式无效');
    }
  }
  static final _pattern = RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-(beta|beta2|openlist\.[1-9]\d*))?$',
  );
  final String version;
  final int build;
  bool get prerelease => version.contains('-');
  List<int> get _parts =>
      version.split('-').first.split('.').map(int.parse).toList();
  @override
  int compareTo(AppVersion other) {
    final a = _parts, b = other._parts;
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    int rank(String v) => v.endsWith('-beta2')
        ? 1
        : v.endsWith('-beta')
        ? 0
        : 2;
    final channel = rank(version).compareTo(rank(other.version));
    return channel != 0 ? channel : build.compareTo(other.build);
  }

  static Future<AppVersion> installed() async {
    final info = await PackageInfo.fromPlatform();
    const release = String.fromEnvironment('SYLPHY_RELEASE_VERSION');
    return AppVersion(
      release.isEmpty ? info.version : release,
      int.parse(info.buildNumber),
    );
  }

  @override
  String toString() => '$version+$build';
}

class UpdateRelease {
  UpdateRelease({
    required this.version,
    required this.name,
    required this.notes,
    required this.date,
    required this.urls,
    required this.page,
  });
  final AppVersion version;
  final String name, notes, date;
  final Map<String, Uri> urls;
  final Uri page;

  factory UpdateRelease.fromJson(Map<String, dynamic> json) {
    final version = json['version'], build = json['build'], name = json['name'];
    if (version is! String ||
        build is! int ||
        name is! String ||
        name.isEmpty) {
      throw const FormatException('更新清单缺少有效版本信息');
    }
    String text(String key) {
      final value = json[key];
      if (value != null && value is! String) {
        throw const FormatException('更新清单字段无效');
      }
      return value as String? ?? '';
    }

    Uri link(String value) {
      final uri = Uri.parse(value);
      // A manifest can only open this project's GitHub release pages/assets.
      if (uri.scheme != 'https' ||
          uri.host != 'github.com' ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          !uri.path.startsWith('/${AppUpdates.repository}/releases/')) {
        throw const FormatException('更新链接不是本项目的 HTTPS 发布地址');
      }
      return uri;
    }

    final rawUrls = json['urls'];
    if (rawUrls != null && rawUrls is! Map<String, dynamic>) {
      throw const FormatException('下载链接格式无效');
    }
    final urls = <String, Uri>{};
    if (rawUrls is Map<String, dynamic>) {
      for (final entry in rawUrls.entries) {
        if (entry.value is! String) throw const FormatException('下载链接格式无效');
        urls[entry.key] = link(entry.value as String);
      }
    }
    return UpdateRelease(
      version: AppVersion(version, build),
      name: name,
      notes: text('notes'),
      date: text('date'),
      urls: urls,
      page: json['page'] == null
          ? Uri.parse(AppUpdates.releasePage)
          : link(text('page')),
    );
  }
}

class UpdateCheck {
  UpdateCheck(this.current, this.latest);
  final AppVersion current;
  final UpdateRelease? latest;
  bool get available =>
      latest != null && latest!.version.compareTo(current) > 0;
}

class AppUpdates {
  AppUpdates({
    http.Client Function()? clientFactory,
    Future<AppVersion> Function()? readVersion,
    this.mirror = defaultMirror,
  }) : _clientFactory = clientFactory ?? (() => http.Client()),
       _readVersion = readVersion ?? AppVersion.installed;
  static const repository = 'ymltsh/SylphyMusic';
  static const releasePage =
      'https://github.com/$repository/releases?q=openlist-lite';
  static const rawBase =
      'https://raw.githubusercontent.com/$repository/feature/android-openlist-lite';
  static const defaultMirror = 'https://hub.wgen.top/';
  final String mirror;

  /// The release manifest is validated before its GitHub links are proxied.
  static Uri accelerate(Uri original, String mirror) {
    if (original.scheme != 'https' ||
        original.userInfo.isNotEmpty ||
        original.hasPort ||
        original.host.isEmpty ||
        !(original.host == 'github.com' ||
            original.host == 'raw.githubusercontent.com')) {
      throw const FormatException('只能加速受信任的 GitHub 发布链接');
    }
    final gateway = Uri.tryParse(mirror);
    if (gateway == null ||
        gateway.scheme != 'https' ||
        gateway.host.isEmpty ||
        gateway.userInfo.isNotEmpty ||
        gateway.hasPort ||
        gateway.hasQuery ||
        gateway.hasFragment) {
      throw const FormatException('GitHub 加速地址无效');
    }
    final base = gateway.toString().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base/$original');
  }

  final http.Client Function() _clientFactory;
  final Future<AppVersion> Function() _readVersion;

  Future<UpdateCheck> check({bool beta = false}) async {
    final current = await _readVersion();
    final file = beta ? 'version-beta.json' : 'version.json';
    final client = _clientFactory();
    try {
      // No direct fallback: the configured gateway is used for both checking
      // and downloading releases, including in regions without GitHub access.
      final manifest = await _fetch(
        client,
        accelerate(Uri.parse('$rawBase/$file'), mirror),
      ).timeout(const Duration(seconds: 12));
      if (!manifest.containsKey('latest')) {
        throw const FormatException('更新清单缺少 latest');
      }
      final raw = manifest['latest'];
      if (raw == null) return UpdateCheck(current, null);
      if (raw is! Map<String, dynamic>) throw const FormatException('更新清单格式无效');
      final latest = UpdateRelease.fromJson(raw);
      if (!beta && latest.version.prerelease) {
        throw const FormatException('正式版清单包含测试版');
      }
      return UpdateCheck(current, latest);
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> _fetch(http.Client client, Uri uri) async {
    final request = http.Request('GET', uri)..followRedirects = false;
    request.headers['Accept'] = 'application/json';
    final response = await client.send(request);
    if (response.statusCode != 200) throw const FormatException('无法读取更新清单');
    const limit = 1024 * 1024;
    if ((response.contentLength ?? 0) > limit) {
      throw const FormatException('更新清单过大');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > limit) {
        throw const FormatException('更新清单过大');
      }
      bytes.addAll(chunk);
    }
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map<String, dynamic>) throw const FormatException('更新清单格式无效');
    return data;
  }
}
