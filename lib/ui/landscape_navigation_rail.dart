import 'package:flutter/material.dart';

/// Compact rail for Android landscape: main tabs scroll when height is short,
/// while global actions remain reachable at the bottom without an AppBar.
class LandscapeNavigationRail extends StatelessWidget {
  const LandscapeNavigationRail({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onSearch,
    required this.onSettings,
    this.backgroundColor,
  });

  final List<NavigationRailDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onSearch;
  final VoidCallback onSettings;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final color =
        backgroundColor ??
        NavigationRailTheme.of(context).backgroundColor ??
        Theme.of(context).colorScheme.surface;
    return ColoredBox(
      color: color,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Expanded(
              child: NavigationRail(
                minWidth: 72,
                backgroundColor: Colors.transparent,
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
                destinations: destinations,
                // Side icons only: no page titles in landscape.
                labelType: NavigationRailLabelType.none,
                // Short car-head-unit screens must not overflow the rail.
                scrollable: true,
              ),
            ),
            const Divider(height: 1),
            SizedBox.square(
              dimension: 48,
              child: IconButton(
                key: const ValueKey('landscape-search'),
                tooltip: '搜索',
                onPressed: onSearch,
                icon: const Icon(Icons.search),
              ),
            ),
            SizedBox.square(
              dimension: 48,
              child: IconButton(
                key: const ValueKey('landscape-settings'),
                tooltip: '设置',
                onPressed: onSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
