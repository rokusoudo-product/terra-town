import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import 'design/app_theme.dart';
import 'design/color_tokens.dart';
import 'features/build/build_screen.dart';
import 'features/build/build_selection_controller.dart';
import 'features/collection/collection_screen.dart';
import 'features/collection/region_pack_loader.dart';
import 'features/map/map_screen.dart';
import 'features/settings/save_data_transfer_adapters.dart';
import 'features/settings/settings_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.mapPathResolver,
    this.gameDatabaseBuilder,
    this.loadRegionPack,
  });

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

  /// テスト用の差し替えフック（既定 null では [defaultLoadRegionPack] を使う）。
  ///
  /// [CollectionScreen]（図鑑タブ・T075・Issue #161）がカテゴリ集計の総数（分母）を
  /// 得るために地域パックを読み込む関数。`region_pack_loader.dart` クラスdoc参照。
  final LoadRegionPack? loadRegionPack;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  /// [RootScaffold] に付与する Key（Issue #180・T105 決定事項4「読み込み後は
  /// アプリの状態を全体的に作り直す」）。
  ///
  /// セーブデータの読み込み成功後にこの値を変えることで、`RootScaffold`
  /// （`_gameDatabase`・地図タブのパイプライン・各種 Repository を保持する）を
  /// **丸ごと作り直す**。`_RootScaffoldState._gameDatabase` は `late final` のため
  /// 差し替えられず、DB だけを新しくしても `MapScreen` のパイプライン・
  /// coordinator がメモリ上に保持している古いウォーターマーク等が次の計上で
  /// 書き戻される危険がある（Issue #180 本文「DB だけを差し替えても、次の計上で
  /// 古い値を書き戻す危険がある」）。Key を変えて `State` ごと破棄・再生成する
  /// ことで、この危険を構造的に断つ。
  Key _rootKey = UniqueKey();

  void _handleDataRestored() {
    setState(() => _rootKey = UniqueKey());
  }

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
        key: _rootKey,
        mapPathResolver: widget.mapPathResolver,
        gameDatabaseBuilder: widget.gameDatabaseBuilder,
        loadRegionPack: widget.loadRegionPack,
        onDataRestored: _handleDataRestored,
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
/// ## 建設タブ（2026-09-13・Issue #150／2026-09-16・Issue #192）
/// [BuildScreen]（建物カード＋所持資材の一覧）を表示する。建物を選ぶと
/// [_buildSelectionController] に選択を記録した上で地図タブへ切り替え、
/// 実際に建てる場所を選ぶ操作は地図タブ（`MapScreen`）に委ねる
/// （`build_selection_controller.dart` クラスdoc参照）。
///
/// ## 図鑑タブ（2026-09-14・Issue #161・T075）
/// [CollectionScreen]（名所図鑑）を表示する。建設タブと同じく、既存の
/// Repository（[CollectionRepository]）をそのまま使う方針。
class RootScaffold extends StatefulWidget {
  const RootScaffold({
    super.key,
    this.mapPathResolver,
    this.gameDatabaseBuilder,
    this.loadRegionPack,
    this.onDataRestored,
  });

  /// [MyApp.mapPathResolver] をそのまま [MapScreen] まで橋渡しするテスト用フック。
  final Future<String> Function()? mapPathResolver;

  /// [MyApp.gameDatabaseBuilder] をそのまま [SettingsScreen] まで橋渡しする
  /// テスト用フック（Issue #135）。
  final GameDatabase Function()? gameDatabaseBuilder;

  /// [MyApp.loadRegionPack] をそのまま [CollectionScreen] まで橋渡しする
  /// テスト用フック（T075・Issue #161）。
  final LoadRegionPack? loadRegionPack;

  /// セーブデータの読み込み成功後に呼ばれるコールバック（Issue #180・T105）。
  /// [SettingsScreen.onDataRestored] へそのまま橋渡しする。`_MyAppState` が
  /// これを受けて本ウィジェットの `Key` を変え、アプリの状態を作り直す。
  final VoidCallback? onDataRestored;

  @override
  State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> {
  int _selectedIndex = 0;

  /// ゲーム状態DB（Issue #135 で `app` から初めて開く）。設定タブ（[SettingsScreen]）
  /// が [RewardSettingsRepository] 経由で読み書きするほか、地図タブ（[MapScreen]）が
  /// 開示済みヘクスの永続化（`disclosed_hex`・T060・Issue #137）と建設
  /// （`building`・Issue #192）に、建設タブ（`BuildScreen`）が
  /// [InventoryRepository] 経由で所持資材の読み取りに使う、単一の共有インスタンス。
  /// `LazyDatabase` のためこのフィールド初期化自体はディスクI/Oを起こさない
  /// （[MyApp.gameDatabaseBuilder] のドキュメント参照）。
  late final GameDatabase _gameDatabase =
      (widget.gameDatabaseBuilder ?? GameDatabase.defaultConnection)();
  late final RewardSettingsRepository _rewardSettingsRepository =
      RewardSettingsRepository(_gameDatabase);

  /// 建設タブ（[BuildScreen]）が所持資材を読み出すためのリポジトリ。
  /// `InventoryRepository` は Issue #143 で追加済みの既存クラスをそのまま使う
  /// （新しい Repository は作らない・Issue #150 提案内容3）。
  late final InventoryRepository _inventoryRepository =
      InventoryRepository(_gameDatabase);

  /// 建設タブ横断の「今選んでいる建物」状態（Issue #192・T089）。
  /// [BuildScreen]（選ぶ側）と [MapScreen]（建てる場所を選ぶ側・ハイライト
  /// 表示側）の両方に同じインスタンスを渡す
  /// （`build_selection_controller.dart` クラスdoc参照）。
  final BuildSelectionController _buildSelectionController =
      BuildSelectionController();

  /// 図鑑タブ（[CollectionScreen]）が収集記録を読み出すためのリポジトリ。
  /// `CollectionRepository` は Issue #159 で追加済みの既存クラスをそのまま使う
  /// （建設タブの `InventoryRepository` と同じ方針・T075）。
  late final CollectionRepository _collectionRepository =
      CollectionRepository(_gameDatabase);

  /// セーブデータのエクスポート/インポート（Issue #180・T105）。[SettingsScreen] に
  /// 渡す3つの抽象実装は、いずれも `_gameDatabase`（または Pigeon・SAF）へ
  /// 委譲するだけの薄いラッパー（`save_data_transfer_adapters.dart` 参照）。
  late final SaveDataTransfer _saveDataTransfer = LocationSaveDataTransfer(
    SaveDataTransferService(_gameDatabase),
  );
  final SaveDataFileAccess _saveDataFileAccess = PigeonSaveDataFileAccess();
  final RecordingStatusCheck _recordingStatusCheck =
      NativeRecordingStatusCheck();

  /// チュートリアル開始資材（木50・石10）の1回限りの付与（Issue #188・T116）。
  /// `_gameDatabase` 作成後に構築する（`TutorialStartingResourcesGrant` クラスdoc
  /// 参照）。セーブデータ読み込み後は `_MyAppState` が本ウィジェットの `Key` を
  /// 変えて作り直すため（`onDataRestored`）、[initState] が読み込み直後の
  /// `_gameDatabase` に対しても改めて呼ばれる（印が無ければそこでもう一度
  /// 付与される。`docs/tutorial.md` §5）。
  late final TutorialStartingResourcesGrant _tutorialStartingResourcesGrant =
      TutorialStartingResourcesGrant(_gameDatabase);

  @override
  void initState() {
    super.initState();
    unawaited(_grantTutorialStartingResourcesIfNeeded());
  }

  /// 印が無ければ開始資材を付与し、付与した場合だけトランザクションの確定後に
  /// SnackBar で通知する（`docs/tutorial.md` §3・§4、DESIGN.md「プロジェクト
  /// 固有ルール」の「初回資材付与（チュートリアル）の通知」）。
  Future<void> _grantTutorialStartingResourcesIfNeeded() async {
    final granted = await _tutorialStartingResourcesGrant.grantIfNeeded();
    if (!granted || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'はじめの資材として '
          '木$startingResourceWoodAmount・石$startingResourceStoneAmount '
          'を受け取りました',
        ),
        backgroundColor: Theme.of(context).infoColor,
      ),
    );
  }

  @override
  void dispose() {
    _buildSelectionController.dispose();
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
          buildSelection: _buildSelectionController,
        ),
      1 => BuildScreen(
          inventoryRepository: _inventoryRepository,
          onSelectBuildingToPlace: (buildingType) {
            // 建設タブで建物を選んだら、地図タブへ切り替えて場所を選んでもらう
            // （Issue #192 本文「建設タブ→地図で場所を選ぶ→確認」）。選択の
            // 記録（`select`）→タブ切り替えの順で行う——`MapScreen` は
            // `initState` 時点で `buildSelection.value` を読むため、先に
            // 値を確定させてから作り直す必要がある。
            _buildSelectionController.select(buildingType);
            setState(() => _selectedIndex = 0);
          },
        ),
      2 => CollectionScreen(
          collectionRepository: _collectionRepository,
          loadRegionPack: widget.loadRegionPack ?? defaultLoadRegionPack,
        ),
      3 => SettingsScreen(
          store: _rewardSettingsRepository,
          saveDataTransfer: _saveDataTransfer,
          saveDataFileAccess: _saveDataFileAccess,
          recordingStatusCheck: _recordingStatusCheck,
          onDataRestored: widget.onDataRestored,
        ),
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
