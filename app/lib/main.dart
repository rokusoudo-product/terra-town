import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:terra_town_location/terra_town_location.dart';

import 'design/app_theme.dart';
import 'features/inventory/inventory_screen.dart';
import 'features/map/map_screen.dart';
import 'features/settings/settings_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.mapPathResolver, this.gameDatabaseBuilder});

  /// テスト用の差し替えフック（既定 null では [MapScreen] が実アセットから
  /// 地域パックを解決する）。
  ///
  /// `packages/location` の `MapView` は MapLibre の実プラットフォームビューに
  /// 依存しており widget テスト環境では動作しない（`app/test/widget_test.dart`
  /// 冒頭コメント参照）。ナビ/テーマのみを検証するテストは、ここにパック未取得を
  /// 返すフェイクを注入することで、地図の実描画に一切触れずに済ませる。
  final Future<String> Function()? mapPathResolver;

  /// テスト用の差し替えフック（既定 null では [GameDatabase.defaultConnection]
  /// を使う。Issue #135）。[GameDatabase] は `LazyDatabase` 経由でファイルI/Oを
  /// 遅延させているため、この関数自体を呼ぶだけでは実際のディスクアクセスは
  /// 起きない（設定タブを開き最初のクエリが発行されたときに初めて開く）。
  /// widget テストでは [GameDatabase.forTesting]（インメモリ）を渡すことで、
  /// `path_provider` の実プラットフォーム実装なしに設定画面を検証できる。
  final GameDatabase Function()? gameDatabaseBuilder;

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
      home: RootScaffold(
        mapPathResolver: mapPathResolver,
        gameDatabaseBuilder: gameDatabaseBuilder,
      ),
    );
  }
}

/// 下部ナビ4タブ（地図 / 建設 / 図鑑 / 設定）の骨組み（DESIGN.md「余白・レイアウト」）。
///
/// 地図タブ（T057・Issue #99）・建設タブの資材インベントリ表示（T076・Issue #150）
/// 以外の中身（4状態の実装）は Issue #25 のスコープ外。tasks.md の各画面タスク
/// （T075・T089・T093・T103）に委ねる。
///
/// ## 建設タブ（2026-09-13・Issue #150）
/// 建設UI本体（建物を建てる操作・T089）はまだ無いため、現時点では
/// [InventoryScreen]（所持資材の一覧）のみを表示する。T089 実装時に
/// 本タブの中身を差し替える。
class RootScaffold extends StatefulWidget {
  const RootScaffold({super.key, this.mapPathResolver, this.gameDatabaseBuilder});

  /// [MyApp.mapPathResolver] をそのまま [MapScreen] まで橋渡しするテスト用フック。
  final Future<String> Function()? mapPathResolver;

  /// [MyApp.gameDatabaseBuilder] をそのまま [SettingsScreen] まで橋渡しする
  /// テスト用フック（Issue #135）。
  final GameDatabase Function()? gameDatabaseBuilder;

  @override
  State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> {
  int _selectedIndex = 0;

  /// ゲーム状態DB（Issue #135 で `app` から初めて開く）。設定タブ（[SettingsScreen]）
  /// が [RewardSettingsRepository] 経由で読み書きするほか、地図タブ（[MapScreen]）が
  /// 開示済みヘクスの永続化（`disclosed_hex`・T060・Issue #137）に、建設タブ
  /// （[InventoryScreen]）が [InventoryRepository] 経由で所持資材の読み取りに使う、
  /// 単一の共有インスタンス。`LazyDatabase` のためこのフィールド初期化自体は
  /// ディスクI/Oを起こさない（[MyApp.gameDatabaseBuilder] のドキュメント参照）。
  late final GameDatabase _gameDatabase =
      (widget.gameDatabaseBuilder ?? GameDatabase.defaultConnection)();
  late final RewardSettingsRepository _rewardSettingsRepository =
      RewardSettingsRepository(_gameDatabase);

  /// 建設タブ（[InventoryScreen]）が所持資材を読み出すためのリポジトリ。
  /// `InventoryRepository` は Issue #143 で追加済みの既存クラスをそのまま使う
  /// （新しい Repository は作らない・Issue #150 提案内容3）。
  late final InventoryRepository _inventoryRepository =
      InventoryRepository(_gameDatabase);

  @override
  void dispose() {
    unawaited(_gameDatabase.close());
    super.dispose();
  }

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
    final Widget body = switch (_selectedIndex) {
      0 => MapScreen(
          resolveMbtilesPath: widget.mapPathResolver,
          gameDatabase: _gameDatabase,
        ),
      1 => InventoryScreen(inventoryRepository: _inventoryRepository),
      3 => SettingsScreen(store: _rewardSettingsRepository),
      _ => _PlaceholderScreen(label: _tabs[_selectedIndex].label),
    };

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
