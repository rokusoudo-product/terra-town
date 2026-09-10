import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'design/app_theme.dart';
import 'features/map/map_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.mapPathResolver});

  /// テスト用の差し替えフック（既定 null では [MapScreen] が実アセットから
  /// 地域パックを解決する）。
  ///
  /// `packages/location` の `MapView` は MapLibre の実プラットフォームビューに
  /// 依存しており widget テスト環境では動作しない（`app/test/widget_test.dart`
  /// 冒頭コメント参照）。ナビ/テーマのみを検証するテストは、ここにパック未取得を
  /// 返すフェイクを注入することで、地図の実描画に一切触れずに済ませる。
  final Future<String> Function()? mapPathResolver;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'terra-town',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // UI は日本語で作られているため、Material/Widgets/Cupertino の組み込み文言
      // （テキスト選択メニュー・日付/時刻ピッカー・ダイアログの既定ボタン、
      // TalkBack 等スクリーンリーダー向けセマンティクスを含む）も日本語で出す（Issue #51）。
      // MVP は日本語直書き UI のみのため、端末ロケールに関わらず ja に固定する
      // （サブエージェントの判断による暫定対応。将来の多言語対応時は要見直し）。
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ja')],
      locale: const Locale('ja'),
      home: RootScaffold(mapPathResolver: mapPathResolver),
    );
  }
}

/// 下部ナビ4タブ（地図 / 建設 / 図鑑 / 設定）の骨組み（DESIGN.md「余白・レイアウト」）。
///
/// 地図タブ（T057・Issue #99）以外の中身（4状態の実装）は Issue #25 のスコープ外。
/// tasks.md の各画面タスク（T075・T076・T089・T093・T103）に委ねる。
class RootScaffold extends StatefulWidget {
  const RootScaffold({super.key, this.mapPathResolver});

  /// [MyApp.mapPathResolver] をそのまま [MapScreen] まで橋渡しするテスト用フック。
  final Future<String> Function()? mapPathResolver;

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
    final Widget body = _selectedIndex == 0
        ? MapScreen(resolveMbtilesPath: widget.mapPathResolver)
        : _PlaceholderScreen(label: _tabs[_selectedIndex].label);

    return Scaffold(
      body: body,
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
