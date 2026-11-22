part of 'settings_page.dart';

enum _Destination {
  sources('音乐源管理'),
  library('音乐库与同步'),
  transfer('设备间快速迁移'),
  cache('下载与缓存'),
  cacheStorage('管理音乐缓存'),
  downloads('下载任务'),
  playback('播放与音效'),
  player('播放界面'),
  playerEditor('编辑播放页面'),
  lyrics('歌词设置'),
  theme('主题与背景'),
  desktop('横屏与 PC'),
  recommendation('推荐与音乐笔友'),
  letters('每日推荐文案'),
  icon('应用图标'),
  onlineServices('在线服务'),
  onlineLyrics('在线歌词服务'),
  llmConnection('模型连接'),
  diagnostics('诊断与反馈'),
  about('关于风灵音乐');

  const _Destination(this.title);

  final String title;
}

enum _Availability { all, android, windows, androidOrWindows }

class _SettingEntry {
  const _SettingEntry(
    this.destination,
    this.icon,
    this.summary,
    this.keywords, {
    this.label,
    this.availability = _Availability.all,
    this.children = const [],
  });

  final _Destination destination;
  final IconData icon;
  final String summary;
  final String keywords;
  final String? label;
  final _Availability availability;
  final List<_SettingEntry> children;
  String get title => label ?? destination.title;

  bool get available {
    if (availability == _Availability.all) return true;
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => availability != _Availability.windows,
      TargetPlatform.windows => availability != _Availability.android,
      _ => false,
    };
  }

  int match(List<String> terms) {
    final name = title.toLowerCase();
    final query = terms.join(' ');
    if (name == query) return 4;
    if (keywords.toLowerCase().split(' ').contains(query)) return 3;
    if (terms.every(name.contains)) return 2;
    final indexed = '$name ${keywords.toLowerCase()}';
    return terms.every(indexed.contains) ? 1 : 0;
  }
}

const _settingsGroups = [
  (
    title: '音乐与存储',
    entries: [
      _SettingEntry(
        _Destination.sources,
        Icons.dns_outlined,
        '添加、编辑和管理音乐源',
        '音源 服务器 连接 本地文件夹 emby navidrome opensubsonic webdav',
      ),
      _SettingEntry(
        _Destination.library,
        Icons.library_music_outlined,
        '曲库分类、自动同步与收藏偏好',
        '音乐库分类 曲库 显示 隐藏 歌曲 专辑 艺术家 文件夹 自动同步间隔 收藏 默认收藏位置',
        children: [
          _SettingEntry(
            _Destination.library,
            Icons.notifications_outlined,
            '',
            '通知 权限 自动同步',
            label: '同步完成通知',
            availability: _Availability.androidOrWindows,
          ),
        ],
      ),
      _SettingEntry(
        _Destination.transfer,
        Icons.swap_horiz_rounded,
        '在设备之间安全迁移音乐源、API 和自定义界面',
        '迁移 换手机 换设备 导入配置 导出配置 局域网 配对',
      ),
      _SettingEntry(
        _Destination.cache,
        Icons.storage_outlined,
        '管理下载、缓存和空间限制',
        '离线 缓存 下载 清理 空间限制 缓存上限 最大缓存空间',
        children: [
          _SettingEntry(
            _Destination.downloads,
            Icons.download_outlined,
            '',
            '离线任务',
          ),
          _SettingEntry(
            _Destination.cacheStorage,
            Icons.storage_outlined,
            '',
            '占用空间 缓存文件',
          ),
        ],
      ),
    ],
  ),
  (
    title: '播放与歌词',
    entries: [
      _SettingEntry(
        _Destination.playback,
        Icons.tune_rounded,
        '音量、播放速度与响度均衡',
        '播放器设置 音量 增益 replaygain 速度 倍速 音效',
        children: [
          _SettingEntry(
            _Destination.playback,
            Icons.graphic_eq_rounded,
            '',
            'de-click declick 淡入 淡出',
            label: '平滑跳转',
            availability: _Availability.android,
          ),
        ],
      ),
      _SettingEntry(
        _Destination.player,
        Icons.album_outlined,
        '编辑播放页，调整迷你播放器和封面背景',
        '播放器外观 迷你播放器 横条样式 悬浮按钮 磨砂 封面模糊背景',
        children: [
          _SettingEntry(
            _Destination.playerEditor,
            Icons.dashboard_customize_outlined,
            '',
            '播放页编辑器 黑胶 沉浸 封面 圆角 羽化 渐隐 唱片 组件',
          ),
        ],
      ),
      _SettingEntry(
        _Destination.lyrics,
        Icons.lyrics_outlined,
        '调整歌词字号、颜色和补充方式',
        '歌词 歌词字号 字体大小 高亮歌词 歌词取色 迷你歌词 完整歌词',
        children: [
          _SettingEntry(
            _Destination.lyrics,
            Icons.picture_in_picture_alt_outlined,
            '',
            '歌词浮窗 悬浮窗',
            label: '桌面歌词',
            availability: _Availability.androidOrWindows,
          ),
        ],
      ),
    ],
  ),
  (
    title: '外观与个性化',
    entries: [
      _SettingEntry(
        _Destination.theme,
        Icons.palette_outlined,
        '设置外观模式、主题颜色和背景图片',
        '主题预览 跟随系统 主题颜色 主色 深色 浅色 夜间 外观模式 自定义背景图 壁纸 纯色 透明度 背景可见度 默认折叠 默认折叠工具栏 折叠按钮 工具栏 工具栏折叠 始终折叠 自动折叠 从不折叠 默认折叠并锁定工具栏 锁定工具栏 悬浮 Dock Dock栏 底部浮栏 短款 长款',
      ),
      _SettingEntry(
        _Destination.desktop,
        Icons.desktop_windows_outlined,
        '调整横屏布局、宽屏控件和快捷键',
        '横屏 宽屏 卡片比例 快捷键 键盘 宽屏控件 收藏快捷按钮',
        children: [
          _SettingEntry(
            _Destination.desktop,
            Icons.font_download_outlined,
            '',
            '字体 本地字体 ttf otf',
            label: 'Windows 字体',
            availability: _Availability.windows,
          ),
        ],
      ),
      _SettingEntry(
        _Destination.recommendation,
        Icons.auto_awesome_outlined,
        '设置推荐偏好、模型增强和音乐笔友',
        '推荐 推荐设置 笔友 个性化 公开热度 每日精选 换新 刷新 立即更新 增强 参与方式 超时 角色卡 记忆 相处 清除推荐统计',
        children: [
          _SettingEntry(
            _Destination.letters,
            Icons.markunread_mailbox_outlined,
            '',
            '存档 推荐信件 来信 逐曲理由',
          ),
        ],
      ),
      _SettingEntry(
        _Destination.icon,
        Icons.apps_outlined,
        '切换 Android 应用图标',
        '启动图标 桌面图标 launcher icon',
        availability: _Availability.android,
      ),
    ],
  ),
  (
    title: '网络与服务',
    entries: [
      _SettingEntry(
        _Destination.onlineServices,
        Icons.api_outlined,
        '管理每日一言、GitHub 加速、在线歌词与模型连接',
        'api 设置 接口 密钥 模型 llm 每日一言 hitokoto github 镜像 加速',
        children: [
          _SettingEntry(
            _Destination.onlineLyrics,
            Icons.lyrics_outlined,
            '',
            'lrcapi 自动补充 歌词服务地址 歌词服务密钥 缺失歌词',
          ),
          _SettingEntry(
            _Destination.llmConnection,
            Icons.hub_outlined,
            '',
            'llm接口 llm模型 接口地址 模型名称 api key 连接测试',
          ),
        ],
      ),
    ],
  ),
  (
    title: '应用与帮助',
    entries: [
      _SettingEntry(
        _Destination.diagnostics,
        Icons.bug_report_outlined,
        '记录、导出、分享和清理诊断日志',
        '日志 故障 排查 播放问题 导出诊断 分享诊断 清除诊断',
      ),
      _SettingEntry(
        _Destination.about,
        Icons.info_outline_rounded,
        '查看应用信息、检查更新与开源许可证',
        '版本号 关于 版权 开源许可 检查更新 更新 升级 版本更新',
      ),
    ],
  ),
];
