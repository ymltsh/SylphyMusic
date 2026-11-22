part of 'settings_page.dart';

extension _ThemeSettings on _SettingsPageState {
  List<Widget> _themeCards() {
    final appearance = app.appearance;
    return [
      _ThemeAppearancePreview(appearance: appearance),
      SettingsGroup(
        title: '外观模式',
        icon: Icons.brightness_6_outlined,
        children: [
          for (final (mode, label) in const [
            (ThemeMode.system, '跟随系统'),
            (ThemeMode.light, '浅色'),
            (ThemeMode.dark, '深色'),
          ])
            _themeChoice(
              key: ValueKey('theme-mode-${mode.name}'),
              leading: _ThemeModeThumbnail(mode: mode),
              title: label,
              selected: appearance.mode == mode,
              onTap: () => _act(() => appearance.update(theme: mode)),
            ),
        ],
      ),
      SettingsGroup(
        title: '配色',
        icon: Icons.palette_outlined,
        children: [
          ListTile(
            leading: CircleAvatar(backgroundColor: appearance.seed, radius: 15),
            title: const Text('主题颜色'),
            subtitle: Text(appearance.seedHex),
            trailing: const SettingsIcon(Icons.chevron_right),
            onTap: _chooseThemeColor,
          ),
        ],
      ),
      if (UiStyleAvailability.miuixAvailable)
        SettingsGroup(
          title: '界面风格',
          icon: Icons.widgets_outlined,
          children: [
            for (final style in UiStyle.values)
              _themeChoice(
                leading: SettingsIcon(
                  style == UiStyle.material3
                      ? Icons.widgets_outlined
                      : Icons.auto_awesome_outlined,
                ),
                title: style == UiStyle.material3 ? 'Material 3' : 'Miuix',
                subtitle: style == UiStyle.material3 ? '经典界面' : 'HyperOS 风格',
                selected: appearance.uiStyle == style,
                checkKey: const ValueKey('ui-style-selected'),
                onTap: () => _act(() => appearance.setUiStyle(style)),
              ),
          ],
        ),
      SettingsGroup(
        title: '页面背景',
        icon: Icons.wallpaper_outlined,
        children: _backgroundControls(),
      ),
      SettingsGroup(
        title: '导航与工具栏',
        icon: Icons.dock_outlined,
        children: [
          if (SylphyMiuixStyle.enabled(context)) ...[
            MiuixWindowDropdownPreference(
              title: '悬浮 Dock 栏宽度',
              summary: '长款与迷你播放器等宽',
              startAction: const SettingsIcon(Icons.width_normal_rounded),
              items: const ['短款', '长款'],
              selectedIndex: appearance.miuixDockWidth.index,
              onSelectedIndexChange: (index) => _act(
                () =>
                    appearance.setMiuixDockWidth(MiuixDockWidth.values[index]),
              ),
            ),
            MiuixSwitchPreference(
              title: '液态玻璃',
              summary: '为竖屏悬浮 Dock 切换液态玻璃材质',
              startAction: const SettingsIcon(Icons.blur_on_rounded),
              value: appearance.miuixLiquidGlass,
              onChanged: (enabled) =>
                  _act(() => appearance.setMiuixLiquidGlass(enabled)),
            ),
          ],
          _toolbarFoldSetting(),
        ],
      ),
    ];
  }

  Widget _themeChoice({
    Key? key,
    required Widget leading,
    required String title,
    String? subtitle,
    required bool selected,
    Key? checkKey,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      key: key,
      leading: leading,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      selected: selected,
      selectedColor: scheme.onSurface,
      selectedTileColor: scheme.primary.withValues(alpha: .08),
      trailing: selected
          ? SettingsIcon(
              Icons.check_rounded,
              key: checkKey,
              color: scheme.primary,
            )
          : const SizedBox(width: 24),
      onTap: onTap,
    );
  }

  Widget _toolbarFoldSetting() {
    const title = '工具栏折叠';
    const summary = '适用于窄屏的音乐库和歌单，自动模式随滚动展开或折叠';
    const icon = Icons.unfold_less_rounded;
    const labels = {
      ToolbarFoldMode.always: '始终折叠（默认）',
      ToolbarFoldMode.automatic: '自动折叠',
      ToolbarFoldMode.never: '从不折叠',
    };
    final value = app.appearance.toolbarFoldMode;
    void change(ToolbarFoldMode mode) =>
        _act(() => app.appearance.setToolbarFoldMode(mode));

    return SylphyMiuixStyle.enabled(context)
        ? MiuixWindowDropdownPreference(
            title: title,
            summary: summary,
            startAction: const SettingsIcon(icon),
            items: ToolbarFoldMode.values.map((mode) => labels[mode]!).toList(),
            selectedIndex: value.index,
            onSelectedIndexChange: (index) =>
                change(ToolbarFoldMode.values[index]),
          )
        : SettingsSelect<ToolbarFoldMode>(
            title: title,
            description: summary,
            icon: icon,
            value: value,
            labels: labels,
            onChanged: change,
          );
  }

  List<Widget> _backgroundControls() => [
    SwitchListTile(
      secondary: const SettingsIcon(Icons.format_color_fill_outlined),
      title: const Text('纯色底色'),
      subtitle: const Text('使用黑白纯色背景'),
      value: app.appearance.solidBackground,
      onChanged: (value) => _act(() => app.appearance.update(solid: value)),
    ),
    ListTile(
      title: const Text('自定义背景图'),
      subtitle: Text(
        app.appearance.backgroundFile == null
            ? '用于首页、音乐库、歌单和「我的」'
            : app.appearance.solidBackground
            ? '关闭纯色背景后显示'
            : '已设置背景图片',
      ),
      leading: const SettingsIcon(Icons.wallpaper_outlined),
      trailing: app.appearance.backgroundFile == null
          ? const SettingsIcon(Icons.chevron_right)
          : IconButton(
              tooltip: '移除背景',
              icon: const SettingsIcon(Icons.delete_outline),
              onPressed: () => _act(app.appearance.clearBackground),
            ),
      onTap: () => _act(app.appearance.pickBackground),
    ),
    if (app.appearance.backgroundFile != null &&
        !app.appearance.solidBackground)
      SettingsSlider(
        title: '背景可见度',
        formatValue: (value) => '${(value * 100).round()}%',
        min: .1,
        max: .4,
        divisions: 30,
        value: app.appearance.backgroundVisibility,
        onChanged: (value) =>
            _act(() => app.appearance.update(visibility: value)),
      ),
  ];
}

class _ThemeModeThumbnail extends StatelessWidget {
  const _ThemeModeThumbnail({required this.mode});

  final ThemeMode mode;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 42,
          height: 32,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (mode != ThemeMode.dark)
                Expanded(child: _window(light: true, accent: accent)),
              if (mode != ThemeMode.light)
                Expanded(child: _window(light: false, accent: accent)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _window({required bool light, required Color accent}) => ColoredBox(
    color: light ? const Color(0xfff5f6fa) : const Color(0xff232932),
    child: Padding(
      padding: const EdgeInsets.all(5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 14,
            height: 3,
            decoration: BoxDecoration(
              color: light ? const Color(0xff9ca5b3) : const Color(0xff777f8a),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: light ? .46 : .70),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ThemeAppearancePreview extends StatelessWidget {
  const _ThemeAppearancePreview({required this.appearance});

  final Appearance appearance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final miuix = SylphyMiuixStyle.enabled(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: SylphyAdaptiveCard(
        cornerRadius: 28,
        materialFilled: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 4,
                  bottom: 10,
                  end: 4,
                ),
                child: Row(
                  children: [
                    SettingsIcon(
                      Icons.preview_outlined,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '主题预览',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: SizedBox(
                      height: 173,
                      child: AppBackground(
                        appearance: appearance,
                        child: ExcludeSemantics(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment.topRight,
                                radius: 1.2,
                                colors: [
                                  scheme.primary.withValues(alpha: .24),
                                  scheme.primary.withValues(alpha: 0),
                                ],
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(11),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        AspectRatio(
                                          aspectRatio: 1,
                                          child: _PreviewRecord(scheme: scheme),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '正在播放',
                                                textScaler:
                                                    TextScaler.noScaling,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style:
                                                    theme.textTheme.titleMedium,
                                              ),
                                              const SizedBox(height: 6),
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: AlignmentDirectional
                                                    .centerStart,
                                                child: SizedBox(
                                                  height: 19,
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .center,
                                                    children: [
                                                      for (final height
                                                          in const [
                                                            6.0,
                                                            12.0,
                                                            17.0,
                                                            8.0,
                                                            15.0,
                                                            11.0,
                                                            5.0,
                                                          ])
                                                        Container(
                                                          width: 3,
                                                          height: height,
                                                          margin:
                                                              const EdgeInsetsDirectional.only(
                                                                end: 3,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  2,
                                                                ),
                                                            color:
                                                                scheme.primary,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _miniPlayer(scheme),
                                  const SizedBox(height: 6),
                                  _navigation(scheme, miuix),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniPlayer(ColorScheme scheme) => DecoratedBox(
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHigh.withValues(alpha: .96),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.music_note_rounded, size: 14, color: scheme.primary),
          const SizedBox(width: 7),
          Expanded(
            child: LinearProgressIndicator(
              value: .58,
              minHeight: 3,
              borderRadius: BorderRadius.circular(4),
              backgroundColor: scheme.outlineVariant,
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.play_circle_fill_rounded, size: 21, color: scheme.primary),
          const SizedBox(width: 6),
          Icon(Icons.skip_next_rounded, size: 15, color: scheme.onSurface),
        ],
      ),
    ),
  );

  Widget _navigation(ColorScheme scheme, bool miuix) => FractionallySizedBox(
    widthFactor: miuix && appearance.miuixDockWidth == MiuixDockWidth.short
        ? .72
        : 1,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(
          alpha: miuix && appearance.miuixLiquidGlass ? .68 : .96,
        ),
        borderRadius: BorderRadius.circular(miuix ? 16 : 9),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final (index, icon) in const [
              Icons.home_rounded,
              Icons.library_music_rounded,
              Icons.queue_music_rounded,
              Icons.person_rounded,
            ].indexed)
              Icon(
                icon,
                size: 16,
                color: index == 0 ? scheme.primary : scheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    ),
  );
}

class _PreviewRecord extends StatelessWidget {
  const _PreviewRecord({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [scheme.primaryContainer, scheme.primary],
      ),
    ),
    child: Center(
      child: FractionallySizedBox(
        widthFactor: .76,
        heightFactor: .76,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xff20242d),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (final fraction in const [.84, .68, .52])
                Center(
                  child: FractionallySizedBox(
                    widthFactor: fraction,
                    heightFactor: fraction,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: .75),
                      ),
                    ),
                  ),
                ),
              Center(
                child: SizedBox.square(
                  dimension: 19,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary,
                    ),
                    child: Icon(
                      Icons.music_note_rounded,
                      size: 12,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
