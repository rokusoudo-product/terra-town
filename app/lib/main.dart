import 'package:flutter/material.dart';

import 'design/app_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'terra-town',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const RootScaffold(),
    );
  }
}

/// 下部ナビ4タブ（地図 / 建設 / 図鑑 / 設定）の骨組み（DESIGN.md「余白・レイアウト」）。
///
/// 各タブの中身（4状態の実装）は Issue #25 のスコープ外。
/// tasks.md の各画面タスク（T057・T075・T076・T089・T093・T103）に委ねる。
class RootScaffold extends StatefulWidget {
  const RootScaffold({super.key});

  @override
  State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> {
  int _selectedIndex = 0;

  static const List<_TabSpec> _tabs = [
    _TabSpec(label: '地図', icon: Icons.map_outlined, selectedIcon: Icons.map),
    _TabSpec(
      label: '建設',
      icon: Icons.construction_outlined,
      selectedIcon: Icons.construction,
    ),
    _TabSpec(
      label: '図鑑',
      icon: Icons.collections_bookmark_outlined,
      selectedIcon: Icons.collections_bookmark,
    ),
    _TabSpec(
      label: '設定',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _PlaceholderScreen(label: _tabs[_selectedIndex].label),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// 画面本体のプレースホルダ。テーマ（トークン）が適用されていることだけを示し、
/// 実際の4状態（通常/ローディング/空/エラー）は各画面タスクで実装する。
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(label, style: Theme.of(context).textTheme.headlineSmall),
    );
  }
}
